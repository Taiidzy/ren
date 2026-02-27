# 1. EXECUTIVE SUMMARY
Риск проекта: **CRITICAL**.

Текущая система уязвима к MITM в E2EE-цепочке, саботажу X3DH prekeys, supply-chain подмене нативного SDK и DoS/операционным отказам. Ключевые security-механизмы частично декларированы, но не доведены до production-grade реализации и местами логически сломаны.

---

# 2. CRITICAL FINDINGS

## C1. Криптографическая аутентификация ключей фактически отсутствует (MITM возможен)
- Что это:
  - endpoint публичного ключа возвращает `signature`, которая равна `SHA256(pubk || key_version)`, а не Ed25519 подписи владельца ключа.
- Где:
  - `backend/src/route/users.rs:538-550`
- Exploit сценарий:
  - атакующий с доступом к backend/DB/прокси подменяет `pubk` жертвы;
  - клиент принимает ключ и шифрует на атакующего;
  - атакующий читает и перешифровывает сообщения (transparent MITM).
- Impact:
  - полный компромисс конфиденциальности 1:1 переписки.
- Как исправить (без компромиссов):
  - Код:
    1. Ввести таблицу `device_identity_keys` (device_id, user_id, ed25519_pub, created_at, revoked_at).
    2. Подписывать `X25519_signed_prekey` приватным Ed25519-ключом устройства при генерации/ротации.
    3. На API возвращать только реальную подпись, `key_version`, `signed_at`, `device_id`.
    4. На клиенте обязательно вызывать verify (`ren_verify_signed_public_key`) до использования ключа.
  - Архитектура:
    1. Перейти к trust model device-based identity, не user-global key.
    2. Добавить key transparency log (append-only) и аудит смены ключей.
  - CI/CD:
    1. Ввести crypto-contract tests: подмена ключа должна детектиться.
    2. Блокировать релиз при падении MITM regression suite.
  - Инфраструктура:
    1. HSM/KMS для серверных signing-операций (если нужны).
    2. Immutable audit-лог key events.
  - Процессы:
    1. Safety-number/QR verification в UX.
    2. Incident playbook для compromise ключа.

## C2. Любой клиент может удалённо «сжигать» чужие one-time prekeys
- Что это:
  - `DELETE /keys/one-time/:prekey_id` не требует auth и не проверяет владельца.
- Где:
  - `backend/src/route/keys.rs:136-152`
- Exploit сценарий:
  - бот перебирает `prekey_id`, массово ставит `used_at`;
  - у пользователей исчезают OTK, X3DH деградирует/ломается.
- Impact:
  - саботаж защищённого канала, отказ в обслуживании E2EE.
- Как исправить:
  - Код:
    1. Требовать `CurrentUser` в `consume_prekey`.
    2. Обновлять только `WHERE id=$1 AND user_id=$2`.
    3. Возвращать `404/403` при несоответствии owner.
    4. Добавить rate limit на endpoint.
  - Архитектура:
    1. Убрать отдельный consume-endpoint.
    2. Делать consume атомарно на сервере при выдаче bundle (см. C3).
  - CI/CD:
    1. Негативные API tests (чужой prekey -> 403).
  - Инфраструктура:
    1. WAF/edge throttling на `/keys/*`.
  - Процессы:
    1. Мониторинг аномалий по `used_at` скорости.

## C3. X3DH bundle выдаётся неатомарно + race condition на OTK
- Что это:
  - `get_prekey_bundle` читает OTK через `SELECT ... used_at IS NULL LIMIT 1` без lock/consume в одной транзакции.
- Где:
  - `backend/src/route/keys.rs:41-51`
- Exploit сценарий:
  - 2+ инициации одновременно получают один OTK;
  - протокол теряет expected one-time semantics, возможны replay/деградации security свойства.
- Impact:
  - потеря крипто-гарантий X3DH, нестабильность сессий.
- Как исправить:
  - Код:
    1. Обернуть выдачу bundle в транзакцию `SERIALIZABLE`/`REPEATABLE READ`.
    2. Выбирать OTK через `FOR UPDATE SKIP LOCKED`.
    3. Сразу `UPDATE ... SET used_at = NOW()` в той же транзакции.
  - Архитектура:
    1. Выделить server-side PreKey service с инвариантами single-consume.
  - CI/CD:
    1. Concurrency tests (N параллельных запросов -> уникальные OTK).
  - Инфраструктура:
    1. Pg lock/transaction metrics.
  - Процессы:
    1. SLA на минимальный пул OTK + alarm.

## C4. FFI SDK в приложении и биндинги рассинхронизированы (symbol mismatch)
- Что это:
  - Dart ожидает функции `ren_generate_identity_key_pair`, `ren_sign_public_key`, `ren_verify_signed_public_key`, `x3dh_initiate_ffi`, `ratchet_*`;
  - в вендорном `libren_sdk.so` эти символы отсутствуют.
- Где:
  - ожидание: `apps/flutter/lib/core/sdk/ren_sdk.dart:528-541`, `:604-626`
  - факт: `nm -D apps/flutter/android/app/src/main/jniLibs/arm64-v8a/libren_sdk.so` показывает только старые символы (`ren_generate_nonce`, `ren_encrypt_data`, ...).
- Exploit сценарий:
  - поставка/подмена устаревшего SDK делает security-проверки недоступными;
  - runtime отказ при lookup/невыполнение заявленной криптозащиты.
- Impact:
  - фактический bypass security-features, непредсказуемые крэши.
- Как исправить:
  - Код:
    1. Добавить отсутствующие экспортируемые FFI функции в `Ren-SDK/src/ffi.rs`.
    2. Ввести runtime capability check с fail-closed (без символьной поддержки запуск запрещён).
  - Архитектура:
    1. Версионировать FFI ABI (`ren_sdk_abi_version`).
    2. Жёсткое сопоставление app_version <-> sdk_abi_version.
  - CI/CD:
    1. На каждый билд выполнять `nm`/`objdump` symbol contract test.
    2. Публиковать checksum + SBOM + signed release artifact.
  - Инфраструктура:
    1. Артефакт-репозиторий с immutable retention.
  - Процессы:
    1. Release gate: без ABI-совместимости релиз блокируется.

## C5. Android release подписывается debug-ключом
- Что это:
  - `build.gradle.kts` явно ставит debug signing для release.
- Где:
  - `apps/flutter/android/app/build.gradle.kts:33-38`
- Exploit сценарий:
  - атакующий распространяет модифицированный APK, подписанный тем же debug key;
  - пользователи могут установить подменённый клиент.
- Impact:
  - полный компромисс целостности мобильного клиента.
- Как исправить:
  - Код:
    1. Удалить debug signing из release buildType.
    2. Настроить production keystore + Play App Signing.
  - Архитектура:
    1. Подписывать все mobile artifacts через централизованный signing pipeline.
  - CI/CD:
    1. Проверка `apksigner verify` + cert fingerprint gate.
    2. Secret keystore только в CI secret manager.
  - Инфраструктура:
    1. KMS-backed key material.
  - Процессы:
    1. Ротация signing keys и compromise-runbook.

---

# 3. HIGH / MEDIUM / LOW

## HIGH

### H1. `keys` API читает несуществующую колонку `identity_public_key`
- Где: `backend/src/route/keys.rs:19-21` (в схеме есть `identity_pubk`, см. `backend/migrations/20260223120000_key_auth.sql`).
- Риск: endpoint деградирует в `404`, E2EE bootstrap ломается, возможен silent fallback в менее защищённые пути.
- План устранения:
  - Код: заменить на `identity_pubk`, добавить миграцию `NOT NULL` для пользователей с E2EE.
  - Архитектура: единый schema-contract слой (sqlx offline checks).
  - CI/CD: contract test между migration и queries.
  - Инфра: pre-deploy smoke на `/keys/:id/bundle`.
  - Процессы: запрет merge без migration+query compatibility check.

### H2. Rate limiter реализован, но не подключён как middleware
- Где: `backend/src/main.rs:128-150`; используется только login-specific limiter.
- Риск: DoS на `ws`, `media`, `chats`.
- План:
  - Код: добавить `.layer(from_fn_with_state(...rate_limit_middleware))` и отдельный stricter профиль на auth/ws.
  - Архитектура: централизованный лимитер с bucket policy per endpoint.
  - CI/CD: нагрузочные тесты на throttling.
  - Инфра: edge rate-limit в nginx/cloud LB.
  - Процессы: SLO по 429 ratio.

### H3. Безлимитные клиентские retry-циклы
- Где:
  - `apps/flutter/lib/core/network/server_retry_interceptor.dart:26-50`
  - `apps/flutter/lib/features/chats/data/chats_api.dart:328-364`
- Риск: батарея/трафик/DoS на backend при длительных сбоях.
- План:
  - Код: max attempts + jittered exponential backoff + circuit breaker.
  - Архитектура: retry budget policy.
  - CI/CD: chaos tests (network down 30 min).
  - Инфра: adaptive throttling.
  - Процессы: observability по retry storms.

### H4. SDK loading допускает DLL/dylib hijacking из CWD
- Где: `apps/flutter/lib/core/sdk/ren_sdk.dart:30-39`, `:53-59`.
- Риск: локальная подмена нативной библиотеки -> произвольный код.
- План:
  - Код: убрать загрузку из `cwd`, загружать только из signed app bundle path.
  - Архитектура: enforce trusted loader + hash verification.
  - CI/CD: проверка отсутствия небезопасных candidate paths.
  - Инфра: code signing enforcement (macOS/Windows notarization).
  - Процессы: secure release checklist.

### H5. PreKeyRepository использует HTTP localhost и не передаёт auth для protected endpoints
- Где: `apps/flutter/lib/core/cryptography/x3dh/prekey_repository.dart:33`, `:55-101`.
- Риск: MITM в dev-контурах, неработоспособность upload/count (401), хаотичная синхронизация prekeys.
- План:
  - Код: использовать `Apiurl.api` (HTTPS), добавить Bearer token в upload/count.
  - Архитектура: единый authenticated API client.
  - CI/CD: integration tests prekey sync.
  - Инфра: запрет plaintext backend в mobile configs.
  - Процессы: config hardening policy.

### H6. Signed prekey хранится/используется как private key в клиенте (логическая крипто-ошибка)
- Где: `apps/flutter/lib/core/cryptography/x3dh/identity_key_store.dart:174-185`.
- Риск: некорректный X3DH state, потенциальные сессионные сбои и утечки ключевого материала.
- План:
  - Код: хранить отдельно `signed_prekey_public` и `signed_prekey_private`; исправить модель `SignedPreKey`.
  - Архитектура: typed key container с invariant checks.
  - CI/CD: property tests на key-pair consistency.
  - Инфра: secure migration для существующих storage записей.
  - Процессы: crypto code review mandatory.

### H7. Privacy leak: presence enumeration через произвольный список `contacts`
- Где: `backend/src/route/ws.rs:528-537` и обработка `Init`.
- Риск: любой авторизованный пользователь может проверять online/offline произвольных user_id.
- План:
  - Код: фильтровать contacts только пересечением реальных relation (общие чаты/друзья).
  - Архитектура: отдельная presence ACL policy.
  - CI/CD: tests на forbidden presence visibility.
  - Инфра: abuse detection на массовые init запросы.
  - Процессы: privacy threat modeling.

### H8. Не пинованные контейнеры/зависимости в runtime build stack
- Где: `docker-compose.yaml:5`, `:27`, `:38`, `:54` (`rust:latest`, `nginx:alpine`, `certbot/certbot`, `postgres:16`).
- Риск: supply-chain drift, непредсказуемый production behavior.
- План:
  - Код: pin image digests (`@sha256:...`).
  - Архитектура: immutable infra builds.
  - CI/CD: daily CVE scan + digest drift fail.
  - Инфра: private registry mirror.
  - Процессы: dependency upgrade cadence.

## MEDIUM

### M1. `docker-compose` публикует Postgres наружу
- Где: `docker-compose.yaml:34-35`.
- Риск: brute-force/экспозиция БД при ошибках сети/фаервола.
- План: убрать port mapping в prod; private network only; firewall allowlist; DB auth hardening.

### M2. Nginx допускает экстремальные body/timeouts
- Где: `nginx/nginx.conf:73`, `:91-94`.
- Риск: slowloris/resource exhaustion.
- План: снизить лимиты, включить request buffering policies, separate upload endpoint tuning.

### M3. CORS default включает localhost даже для prod-контура
- Где: `backend/src/main.rs:67-70`.
- Риск: расширение attack surface при неправильной конфигурации reverse proxy.
- План: environment-specific strict allowlist + startup fail on insecure prod config.

### M4. Отсутствует certificate pinning в mobile клиентах
- Где: HTTP/WS слой Flutter (`dio`, `web_socket_channel` без pinning).
- Риск: компрометированный CA/enterprise MITM.
- План: добавить TLS pinset + rotation strategy + failover pin.

### M5. Нет CI workflows в репозитории
- Где: отсутствует `.github/workflows`.
- Риск: нет обязательных security gates, reproducibility и policy enforcement.
- План: ввести pipeline (SAST, secret scan, dependency scan, tests, signed artifacts).

### M6. iOS SDK artifact/toolchain mismatch risk
- Где: вендорный `apps/flutter/ios/RenSDK.xcframework/*` + `nm` ошибки LLVM attribute compatibility.
- Риск: build/runtime несовместимость при обновлении Xcode/toolchain.
- План: reproducible build matrix per target toolchain + ABI smoke tests на CI macOS runners.

### M7. Нет crash reporting/telemetry/операционных метрик
- Где: `apps/flutter/lib/main.dart` логирует в консоль; backend только stdout.
- Риск: silent failures, позднее обнаружение атак/регрессий.
- План: structured logging + metrics + alerts + mobile crash SDK.

## LOW

### L1. Security claims расходятся с реализацией
- Где: `SECURITY.md` прямо указывает на неполную key-auth цепочку, но код частично использует «временные» решения.
- План: синхронизировать docs с фактическим статусом и убрать ambiguous формулировки.

### L2. Избыточные Android permissions
- Где: `apps/flutter/android/app/src/main/AndroidManifest.xml` (`READ/WRITE_EXTERNAL_STORAGE`).
- Риск: лишняя приватностная поверхность.
- План: удалить deprecated permissions, перейти на scoped storage.

### L3. Отсутствует формализованная feature-flag система
- Риск: risky rollout security-фич.
- План: remote config with signed config + staged rollout rules.

---

# 4. ATTACK SCENARIOS

1. **Server-side MITM ключей**
- Пререквизит: доступ к backend/DB или уязвимый CI deploy.
- Ход атаки: подмена `pubk` жертвы -> клиент не валидирует реальную подпись -> переписка читается атакующим.
- Итог: полный компромисс конфиденциальности.

2. **PreKey exhaustion DoS**
- Пререквизит: любой сетевой доступ к API.
- Ход атаки: массовые `DELETE /keys/one-time/{id}` -> prekeys расходуются.
- Итог: срывы X3DH и деградация безопасного канала.

3. **SDK binary hijack (desktop)**
- Пререквизит: запись в рабочий каталог/рядом с бинарём.
- Ход атаки: подмена `libren_sdk.dylib`/`ren_sdk.dll` -> загрузка через candidate path.
- Итог: RCE в контексте приложения.

4. **Retry storm during outage**
- Пререквизит: сетевой сбой/partial outage.
- Ход атаки: бесконечные retries тысяч клиентов.
- Итог: self-inflicted DDoS и деградация SLA.

---

# 5. ARCHITECTURE RISKS

1. Криптография разорвана между слоями (backend claims, SDK exports, Flutter bindings), нет строгого protocol contract.
2. Нет device-centric key lifecycle (регистрация/ротация/ревокация/transparency).
3. Смешаны concerns: transport/auth/business logic/realtime без централизованной policy engine.
4. Отсутствует обязательный security gate в delivery pipeline.

---

# 6. SUPPLY CHAIN RISKS

1. Вендорные бинарники SDK (`.so`, `.a`) коммитятся в репо без подписи и без checksum-политики.
2. Docker images не pinned по digest.
3. Build scripts ставят tooling из сети (`cargo install wasm-pack`, `cbindgen`) без pinning.
4. Нет SBOM, provenance attestation, artifact signing.
5. В репо присутствуют user-specific Xcode workspace artifacts (`xcuserdata`), что ухудшает hygiene и reproducibility.

---

# 7. CRYPTO REVIEW

1. **X3DH trust bootstrap broken**: нет строгой signature verification цепочки.
2. **OTK lifecycle broken**: неатомарная выдача + неавторизованное consume.
3. **Double Ratchet integration неконсистентна**:
- FFI `ratchet_*` передаёт только public identity keys (`Ren-SDK/src/ffi.rs:985-993`, `1040-1048`), а respondent flow ожидает private key (`Ren-SDK/src/ratchet/session.rs:107-110`).
4. **Key management bugs в Flutter**:
- signed prekey путает private/public (`identity_key_store.dart:174-185`).
5. **Recovery security**:
- в бизнес-логике используется слабый recovery key path (`deriveKeyFromString`) вместо enforced Argon2id policy.

Рекомендация: остановить rollout новых E2EE фич до устранения C1-C4.

---

# 8. PERFORMANCE BOTTLENECKS

1. Бесконечные retries клиента -> лишний трафик и wakeups.
2. Ненастроенные лимиты nginx (`15G`, `86400`) -> риск удержания ресурсов.
3. Отсутствие централизованных rate-limits -> нагрузка масштабируется неконтролируемо.
4. В backend много `unwrap_or_default` на hot paths JSON/DB mapping, теряется сигнал ошибок и растёт стоимость диагностики.
5. Коммит бинарников увеличивает репозиторий и стоимость CI checkout.

Оптимизации:
- ввести bounded retry + jitter;
- strict upstream limits/timeout profiles per endpoint;
- убрать бинарники из git в artifact registry;
- добавить perf budget tests (p95 ws send, media upload).

---

# 9. RELIABILITY RISKS

1. Single-point runtime checks отсутствуют для ABI-совместимости SDK.
2. PreKey sync логически хрупкий (auth отсутствует в repo-клиенте + `myUserId=1`).
3. Нет structured health/readiness beyond `/health`.
4. Нет rollback-safe deployment process (нет CI/CD state machine).
5. Наблюдаемость недостаточна для расследования сбоев.

---

# 10. QUICK WINS

1. Закрыть `consume_prekey` auth/owner check и добавить rate-limit.
2. Исправить `identity_public_key` -> `identity_pubk` в `keys` API.
3. Убрать debug-signing release Android.
4. Добавить bounded retries (max attempts 5) в оба бесконечных цикла.
5. Подключить global rate-limit middleware.
6. Удалить загрузку SDK из `cwd` candidate paths.
7. Pin docker images by digest.

---

# 11. LONG TERM REFACTOR

1. Перепроектировать E2EE на device-centric модель:
- device identity (Ed25519), signed prekeys, atomic OTK service, strict verification.
2. Ввести formal protocol versioning + compatibility matrix.
3. Перевести SDK delivery на signed artifact pipeline (SLSA-like provenance).
4. Разделить backend на bounded-contexts:
- Auth/Session,
- Messaging,
- Key Management,
- Realtime Presence.
5. Внедрить observability stack (logs+metrics+traces+alerts).

---

# 12. SECURITY ROADMAP

## Этап 0 (24-48 часов)
1. Hotfix C2 (`consume_prekey` auth+owner).
2. Hotfix C1 временный fail-closed: запрет E2EE отправки при неподтверждённой подписи.
3. Удалить debug signing release.
4. Ограничить retries, включить базовый edge throttling.

## Этап 1 (1 неделя)
1. Исправить schema/query mismatch (`identity_pubk`).
2. Подключить global+auth rate limit middleware.
3. Ввести security CI baseline (secret scan, SAST, dependency audit).
4. Зафиксировать docker image digests.

## Этап 2 (2-4 недели)
1. Реальный Ed25519 key-auth chain end-to-end.
2. Атомарный OTK issuance/consume.
3. ABI contract tests для SDK symbols + runtime version checks.
4. Убрать SDK бинарники из git, перейти на signed artifact repo.

## Этап 3 (1-2 месяца)
1. Довести X3DH+DoubleRatchet до production-инвариантов.
2. Device management (register/revoke/verify/safety numbers).
3. Full observability + incident response drills.

## Этап 4 (2-3 месяца)
1. Group E2EE (Sender Keys/MLS).
2. Key transparency log.
3. External security review + pentest + chaos testing.

---

## Итог
Текущий baseline нельзя считать безопасным для hostile environment. До закрытия C1-C5 систему нужно считать компрометируемой при мотивированном атакующем.
