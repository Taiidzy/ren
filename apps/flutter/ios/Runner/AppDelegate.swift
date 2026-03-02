import Flutter
import LibSignalClient
import Security
import UIKit

private final class SignalStoreContext: StoreContext {}

private final class KeychainSignalStore: IdentityKeyStore, PreKeyStore, SignedPreKeyStore, KyberPreKeyStore, SessionStore {
  private let service = "ren.signal.protocol"
  private let identityChanged: (_ peerUserId: Int, _ oldFp: String, _ newFp: String) -> Void
  private var activeUserId: Int = 0
  private var activeDeviceId: UInt32 = 1

  init(identityChanged: @escaping (_ peerUserId: Int, _ oldFp: String, _ newFp: String) -> Void) {
    self.identityChanged = identityChanged
  }

  func bindActiveUser(userId: Int, deviceId: UInt32) {
    activeUserId = userId
    activeDeviceId = deviceId
  }

  private func saveData(_ value: Data, key: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
    ]
    SecItemDelete(query as CFDictionary)
    let add: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecValueData as String: value,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]
    SecItemAdd(add as CFDictionary, nil)
  }

  private func loadData(_ key: String) -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess else { return nil }
    return item as? Data
  }

  private func deleteData(_ key: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
    ]
    SecItemDelete(query as CFDictionary)
  }

  private func saveString(_ value: String, key: String) {
    if let data = value.data(using: .utf8) {
      saveData(data, key: key)
    }
  }

  private func loadString(_ key: String) -> String? {
    guard let data = loadData(key) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  private func saveUInt32(_ value: UInt32, key: String) {
    saveString(String(value), key: key)
  }

  private func loadUInt32(_ key: String) -> UInt32? {
    guard let str = loadString(key) else { return nil }
    return UInt32(str)
  }

  private func idsKey(_ bucket: String) -> String { "ids_\(bucket)" }

  private func loadIds(_ bucket: String) -> [UInt32] {
    guard let str = loadString(idsKey(bucket)), !str.isEmpty else { return [] }
    return str.split(separator: ",").compactMap { UInt32($0) }
  }

  private func saveIds(_ ids: [UInt32], bucket: String) {
    let value = ids.map(String.init).joined(separator: ",")
    saveString(value, key: idsKey(bucket))
  }

  private func appendId(_ id: UInt32, bucket: String) {
    var ids = loadIds(bucket)
    if !ids.contains(id) {
      ids.append(id)
      saveIds(ids, bucket: bucket)
    }
  }

  private func removeId(_ id: UInt32, bucket: String) {
    var ids = loadIds(bucket)
    ids.removeAll { $0 == id }
    saveIds(ids, bucket: bucket)
  }

  private func identityKeyPairKey(userId: Int, deviceId: UInt32) -> String {
    "identity_pair_\(userId)_\(deviceId)"
  }

  private func registrationIdKey(userId: Int, deviceId: UInt32) -> String {
    "registration_id_\(userId)_\(deviceId)"
  }

  private func peerIdentityKey(address: ProtocolAddress) -> String {
    "peer_identity_\(address.name)_\(address.deviceId)"
  }

  private func preKeyKey(id: UInt32) -> String { "prekey_\(id)" }
  private func signedPreKeyKey(id: UInt32) -> String { "signed_prekey_\(id)" }
  private func kyberPreKeyKey(id: UInt32) -> String { "kyber_prekey_\(id)" }

  private func sessionKey(address: ProtocolAddress) -> String {
    "session_\(address.name)_\(address.deviceId)"
  }

  func saveLocalIdentity(_ pair: IdentityKeyPair, userId: Int, deviceId: UInt32) {
    saveData(pair.serialize(), key: identityKeyPairKey(userId: userId, deviceId: deviceId))
  }

  func loadLocalIdentity(userId: Int, deviceId: UInt32) throws -> IdentityKeyPair? {
    guard let data = loadData(identityKeyPairKey(userId: userId, deviceId: deviceId)) else { return nil }
    return try IdentityKeyPair(bytes: data)
  }

  func saveLocalRegistrationId(_ id: UInt32, userId: Int, deviceId: UInt32) {
    saveUInt32(id, key: registrationIdKey(userId: userId, deviceId: deviceId))
  }

  func loadLocalRegistrationId(userId: Int, deviceId: UInt32) -> UInt32? {
    loadUInt32(registrationIdKey(userId: userId, deviceId: deviceId))
  }

  func listPreKeyIds() -> [UInt32] { loadIds("prekey") }

  func identityKeyPair(context: StoreContext) throws -> IdentityKeyPair {
    _ = context
    guard let pair = try loadLocalIdentity(userId: activeUserId, deviceId: activeDeviceId) else {
      throw SignalError.invalidState("local identity is missing")
    }
    return pair
  }

  func localRegistrationId(context: StoreContext) throws -> UInt32 {
    _ = context
    guard let id = loadLocalRegistrationId(userId: activeUserId, deviceId: activeDeviceId) else {
      throw SignalError.invalidState("local registration id is missing")
    }
    return id
  }

  func saveIdentity(_ identity: IdentityKey, for address: ProtocolAddress, context: StoreContext) throws -> IdentityChange {
    let key = peerIdentityKey(address: address)
    let nextBytes = identity.serialize()
    if let oldBytes = loadData(key), oldBytes != nextBytes {
      let oldFp = oldBytes.base64EncodedString()
      let newFp = nextBytes.base64EncodedString()
      saveData(nextBytes, key: key)
      if let peerId = Int(address.name) {
        identityChanged(peerId, oldFp, newFp)
      }
      return .replacedExisting
    }
    saveData(nextBytes, key: key)
    return .newOrUnchanged
  }

  func isTrustedIdentity(_ identity: IdentityKey, for address: ProtocolAddress, direction: Direction, context: StoreContext) throws -> Bool {
    guard let existing = try self.identity(for: address, context: context) else {
      return true
    }
    return existing == identity
  }

  func identity(for address: ProtocolAddress, context: StoreContext) throws -> IdentityKey? {
    guard let bytes = loadData(peerIdentityKey(address: address)) else { return nil }
    return try IdentityKey(bytes: bytes)
  }

  func loadPreKey(id: UInt32, context: StoreContext) throws -> PreKeyRecord {
    guard let data = loadData(preKeyKey(id: id)) else {
      throw SignalError.invalidKeyIdentifier("missing prekey \(id)")
    }
    return try PreKeyRecord(bytes: data)
  }

  func storePreKey(_ record: PreKeyRecord, id: UInt32, context: StoreContext) throws {
    saveData(record.serialize(), key: preKeyKey(id: id))
    appendId(id, bucket: "prekey")
  }

  func removePreKey(id: UInt32, context: StoreContext) throws {
    deleteData(preKeyKey(id: id))
    removeId(id, bucket: "prekey")
  }

  func loadSignedPreKey(id: UInt32, context: StoreContext) throws -> SignedPreKeyRecord {
    guard let data = loadData(signedPreKeyKey(id: id)) else {
      throw SignalError.invalidKeyIdentifier("missing signed prekey \(id)")
    }
    return try SignedPreKeyRecord(bytes: data)
  }

  func storeSignedPreKey(_ record: SignedPreKeyRecord, id: UInt32, context: StoreContext) throws {
    saveData(record.serialize(), key: signedPreKeyKey(id: id))
  }

  func loadKyberPreKey(id: UInt32, context: StoreContext) throws -> KyberPreKeyRecord {
    guard let data = loadData(kyberPreKeyKey(id: id)) else {
      throw SignalError.invalidKeyIdentifier("missing kyber prekey \(id)")
    }
    return try KyberPreKeyRecord(bytes: data)
  }

  func storeKyberPreKey(_ record: KyberPreKeyRecord, id: UInt32, context: StoreContext) throws {
    saveData(record.serialize(), key: kyberPreKeyKey(id: id))
  }

  func markKyberPreKeyUsed(id: UInt32, signedPreKeyId: UInt32, baseKey: PublicKey, context: StoreContext) throws {
    _ = signedPreKeyId
    _ = baseKey
    // We currently keep used kyber prekeys stored for auditability.
    _ = id
  }

  func loadSession(for address: ProtocolAddress, context: StoreContext) throws -> SessionRecord? {
    guard let data = loadData(sessionKey(address: address)) else { return nil }
    return try SessionRecord(bytes: data)
  }

  func loadExistingSessions(for addresses: [ProtocolAddress], context: StoreContext) throws -> [SessionRecord] {
    try addresses.map { address in
      guard let session = try loadSession(for: address, context: context) else {
        throw SignalError.sessionNotFound("\(address)")
      }
      return session
    }
  }

  func storeSession(_ record: SessionRecord, for address: ProtocolAddress, context: StoreContext) throws {
    saveData(record.serialize(), key: sessionKey(address: address))
  }
}

private final class SignalProtocolManager {
  private let store: KeychainSignalStore
  private let context = SignalStoreContext()

  private static let defaultDeviceId: UInt32 = 1
  private static let signedPreKeyId: UInt32 = 1
  private static let kyberPreKeyId: UInt32 = 1
  private static let oneTimePreKeyStart: UInt32 = 1000
  private static let oneTimePreKeyCount: UInt32 = 50

  private var currentUserId: Int = 0
  private var currentDeviceId: UInt32 = defaultDeviceId

  init(identityChanged: @escaping (_ peerUserId: Int, _ oldFp: String, _ newFp: String) -> Void) {
    store = KeychainSignalStore(identityChanged: identityChanged)
  }

  private func bindContext() {
    store.bindActiveUser(userId: currentUserId, deviceId: currentDeviceId)
  }

  private func makeAddress(peerUserId: Int, deviceId: Int) throws -> ProtocolAddress {
    try ProtocolAddress(name: String(peerUserId), deviceId: UInt32(max(1, deviceId)))
  }

  private func nowMillis() -> UInt64 {
    UInt64(Date().timeIntervalSince1970 * 1000)
  }

  private func ensureLocalIdentity(userId: Int, deviceId: UInt32) throws -> IdentityKeyPair {
    if let existing = try store.loadLocalIdentity(userId: userId, deviceId: deviceId) {
      return existing
    }
    let pair = IdentityKeyPair.generate()
    store.saveLocalIdentity(pair, userId: userId, deviceId: deviceId)
    return pair
  }

  private func ensureRegistrationId(userId: Int, deviceId: UInt32) -> UInt32 {
    if let existing = store.loadLocalRegistrationId(userId: userId, deviceId: deviceId) {
      return existing
    }
    let generated = UInt32.random(in: 1...0x3FFF)
    store.saveLocalRegistrationId(generated, userId: userId, deviceId: deviceId)
    return generated
  }

  private func ensureSignedPreKey(identity: IdentityKeyPair) throws -> SignedPreKeyRecord {
    if let existing = try? store.loadSignedPreKey(id: Self.signedPreKeyId, context: context) {
      return existing
    }
    let signedPrivate = PrivateKey.generate()
    let signature = identity.privateKey.generateSignature(message: signedPrivate.publicKey.serialize())
    let record = try SignedPreKeyRecord(
      id: Self.signedPreKeyId,
      timestamp: nowMillis(),
      privateKey: signedPrivate,
      signature: signature
    )
    try store.storeSignedPreKey(record, id: Self.signedPreKeyId, context: context)
    return record
  }

  private func ensureKyberPreKey(identity: IdentityKeyPair) throws -> KyberPreKeyRecord {
    if let existing = try? store.loadKyberPreKey(id: Self.kyberPreKeyId, context: context) {
      return existing
    }
    let keyPair = KEMKeyPair.generate()
    let signature = identity.privateKey.generateSignature(message: keyPair.publicKey.serialize())
    let record = try KyberPreKeyRecord(
      id: Self.kyberPreKeyId,
      timestamp: nowMillis(),
      keyPair: keyPair,
      signature: signature
    )
    try store.storeKyberPreKey(record, id: Self.kyberPreKeyId, context: context)
    return record
  }

  private func ensureOneTimePreKeys() throws -> [[String: Any]] {
    var ids = store.listPreKeyIds()
    if ids.count < Int(Self.oneTimePreKeyCount) {
      let targetEnd = Self.oneTimePreKeyStart + Self.oneTimePreKeyCount
      for id in Self.oneTimePreKeyStart..<targetEnd {
        if ids.contains(id) { continue }
        let privateKey = PrivateKey.generate()
        let record = try PreKeyRecord(id: id, privateKey: privateKey)
        try store.storePreKey(record, id: id, context: context)
      }
      ids = store.listPreKeyIds()
    }

    return try ids.sorted().prefix(Int(Self.oneTimePreKeyCount)).compactMap { id in
      guard let record = try? store.loadPreKey(id: id, context: context) else { return nil }
      guard let pub = try? record.publicKey() else { return nil }
      return [
        "id": Int(id),
        "key": pub.serialize().base64EncodedString(),
      ]
    }
  }

  func initUser(userId: Int, deviceId: Int) throws -> [String: Any] {
    currentUserId = userId
    currentDeviceId = UInt32(max(1, deviceId))
    bindContext()

    let identity = try ensureLocalIdentity(userId: userId, deviceId: currentDeviceId)
    let registrationId = ensureRegistrationId(userId: userId, deviceId: currentDeviceId)
    let signedPreKey = try ensureSignedPreKey(identity: identity)
    let kyberPreKey = try ensureKyberPreKey(identity: identity)
    let oneTimePreKeys = try ensureOneTimePreKeys()

    let signedPreKeyPublic = try signedPreKey.publicKey().serialize().base64EncodedString()
    let kyberPreKeyPublic = try kyberPreKey.publicKey().serialize().base64EncodedString()

    return [
      "public_key": identity.publicKey.serialize().base64EncodedString(),
      "identity_key": identity.identityKey.serialize().base64EncodedString(),
      "signature": "",
      "key_version": 1,
      "signed_at": ISO8601DateFormatter().string(from: Date()),
      "registration_id": Int(registrationId),
      "signed_pre_key_id": Int(Self.signedPreKeyId),
      "signed_pre_key": signedPreKeyPublic,
      "signed_pre_key_signature": signedPreKey.signature.base64EncodedString(),
      "kyber_pre_key_id": Int(Self.kyberPreKeyId),
      "kyber_pre_key": kyberPreKeyPublic,
      "kyber_pre_key_signature": kyberPreKey.signature.base64EncodedString(),
      "one_time_pre_keys": oneTimePreKeys,
    ]
  }

  func hasSession(peerUserId: Int, deviceId: Int) throws -> Bool {
    let address = try makeAddress(peerUserId: peerUserId, deviceId: deviceId)
    return try store.loadSession(for: address, context: context) != nil
  }

  private func preKeyBundleFromMap(_ map: [String: Any], fallbackDeviceId: Int) throws -> PreKeyBundle {
    func readInt(_ key: String) -> Int? {
      if let v = map[key] as? Int { return v }
      if let v = map[key] as? NSNumber { return v.intValue }
      if let v = map[key] as? String { return Int(v.trimmingCharacters(in: .whitespacesAndNewlines)) }
      return nil
    }
    func readInt(from any: Any?) -> Int? {
      if let v = any as? Int { return v }
      if let v = any as? NSNumber { return v.intValue }
      if let v = any as? String { return Int(v.trimmingCharacters(in: .whitespacesAndNewlines)) }
      return nil
    }

    let reg = readInt("registration_id") ?? 1
    let signedPreKeyId = readInt("signed_pre_key_id") ?? 1
    let signedPreKeyB64 = ((map["signed_pre_key"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let signedPreKeySigB64 = ((map["signed_pre_key_signature"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let identityB64 = (((map["identity_key"] as? String) ?? (map["public_key"] as? String) ?? "")).trimmingCharacters(in: .whitespacesAndNewlines)

    guard
      !signedPreKeyB64.isEmpty,
      !signedPreKeySigB64.isEmpty,
      !identityB64.isEmpty,
      let signedPreKeyBytes = Data(base64Encoded: signedPreKeyB64),
      let signedPreKeySig = Data(base64Encoded: signedPreKeySigB64),
      let identityBytes = Data(base64Encoded: identityB64)
    else {
      throw SignalError.invalidArgument("Malformed preKeyBundle")
    }

    let signedPreKey = try PublicKey(signedPreKeyBytes)
    let identity = try IdentityKey(bytes: identityBytes)
    let remoteDeviceId = UInt32(max(1, readInt("device_id") ?? fallbackDeviceId))
    let kyberId = readInt("kyber_pre_key_id")
    let kyberB64 = ((map["kyber_pre_key"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let kyberSigB64 = ((map["kyber_pre_key_signature"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let kyberBytes = Data(base64Encoded: kyberB64)
    let kyberSig = Data(base64Encoded: kyberSigB64)
    let kyberKey = try kyberBytes.map { try KEMPublicKey($0) }
    guard let finalKyberId = kyberId, let finalKyberKey = kyberKey, let finalKyberSig = kyberSig else {
      throw SignalError.invalidArgument("Malformed preKeyBundle: missing Kyber fields")
    }

    let preKeys = (map["one_time_pre_keys"] as? [Any]) ?? []
    if let first = preKeys.first as? [String: Any],
      let preId = readInt(from: first["id"]),
      let preB64 = first["key"] as? String,
      let preBytes = Data(base64Encoded: preB64)
    {
      let preKey = try PublicKey(preBytes)
      return try PreKeyBundle(
        registrationId: UInt32(reg),
        deviceId: remoteDeviceId,
        prekeyId: UInt32(preId),
        prekey: preKey,
        signedPrekeyId: UInt32(signedPreKeyId),
        signedPrekey: signedPreKey,
        signedPrekeySignature: signedPreKeySig,
        identity: identity,
        kyberPrekeyId: UInt32(finalKyberId),
        kyberPrekey: finalKyberKey,
        kyberPrekeySignature: finalKyberSig
      )
    }

    return try PreKeyBundle(
      registrationId: UInt32(reg),
      deviceId: remoteDeviceId,
      signedPrekeyId: UInt32(signedPreKeyId),
      signedPrekey: signedPreKey,
      signedPrekeySignature: signedPreKeySig,
      identity: identity,
      kyberPrekeyId: UInt32(finalKyberId),
      kyberPrekey: finalKyberKey,
      kyberPrekeySignature: finalKyberSig
    )
  }

  func encrypt(peerUserId: Int, deviceId: Int, plaintext: String, preKeyBundle: [String: Any]?) throws -> String {
    let address = try makeAddress(peerUserId: peerUserId, deviceId: deviceId)
    let existingSession = try store.loadSession(for: address, context: context)
    if existingSession == nil {
      guard let bundle = preKeyBundle else {
        throw SignalError.invalidState("missing preKeyBundle for new session")
      }
      let parsedBundle = try preKeyBundleFromMap(bundle, fallbackDeviceId: deviceId)
      try processPreKeyBundle(
        parsedBundle,
        for: address,
        sessionStore: store,
        identityStore: store,
        context: context
      )
    }

    let ciphertext = try signalEncrypt(
      message: Data(plaintext.utf8),
      for: address,
      sessionStore: store,
      identityStore: store,
      context: context
    )

    let messageType: String = (ciphertext.messageType == .preKey) ? "prekey" : "whisper"
    let envelope: [String: Any] = [
      "v": 2,
      "t": messageType,
      "b": ciphertext.serialize().base64EncodedString(),
    ]
    let data = try JSONSerialization.data(withJSONObject: envelope)
    return data.base64EncodedString()
  }

  func decrypt(peerUserId: Int, deviceId: Int, ciphertext: String) throws -> String {
    guard
      let envelopeData = Data(base64Encoded: ciphertext),
      let obj = try JSONSerialization.jsonObject(with: envelopeData) as? [String: Any],
      let type = obj["t"] as? String,
      let bodyB64 = obj["b"] as? String,
      let bodyData = Data(base64Encoded: bodyB64)
    else {
      throw SignalError.invalidMessage("Malformed Signal ciphertext envelope")
    }

    let address = try makeAddress(peerUserId: peerUserId, deviceId: deviceId)
    let plain: Data
    if type == "prekey" {
      let message = try PreKeySignalMessage(bytes: bodyData)
      plain = try signalDecryptPreKey(
        message: message,
        from: address,
        sessionStore: store,
        identityStore: store,
        preKeyStore: store,
        signedPreKeyStore: store,
        kyberPreKeyStore: store,
        context: context
      )
    } else {
      let message = try SignalMessage(bytes: bodyData)
      plain = try signalDecrypt(
        message: message,
        from: address,
        sessionStore: store,
        identityStore: store,
        context: context
      )
    }

    guard let text = String(data: plain, encoding: .utf8) else {
      throw SignalError.invalidMessage("Decrypted payload is not valid UTF-8")
    }
    return text
  }

  func fingerprint(peerUserId: Int, deviceId: Int) throws -> String {
    let address = try makeAddress(peerUserId: peerUserId, deviceId: deviceId)
    guard let peerIdentity = try store.identity(for: address, context: context) else {
      throw SignalError.invalidState("No peer identity for fingerprint")
    }
    let myIdentity = try store.identityKeyPair(context: context)
    let generator = NumericFingerprintGenerator(iterations: 5200)
    let fp = try generator.create(
      version: 2,
      localIdentifier: Data(String(currentUserId).utf8),
      localKey: myIdentity.publicKey,
      remoteIdentifier: Data(String(peerUserId).utf8),
      remoteKey: peerIdentity.publicKey
    )
    return fp.displayable.formatted
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let privacyChannel = "ren/privacy_protection"
  private let signalChannel = "ren/signal_protocol"
  private let signalEventsChannel = "ren/signal_protocol/events"
  private let privacyOverlayTag = 774401

  private var privacyOverlayEnabled = false
  private var antiCaptureEnabled = false
  private var isAppInactive = false
  private var isScreenCaptured = false
  private var captureObserverInstalled = false
  private var signalEventsSink: FlutterEventSink?

  private lazy var signalManager = SignalProtocolManager { [weak self] peerId, oldFp, newFp in
    self?.signalEventsSink?([
      "type": "identity_changed",
      "peer_user_id": peerId,
      "previous_fingerprint": oldFp,
      "current_fingerprint": newFp,
    ])
  }

  private func currentKeyWindow() -> UIWindow? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
  }

  private func installCaptureObserverIfNeeded() {
    if captureObserverInstalled { return }
    captureObserverInstalled = true
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleScreenCaptureChanged),
      name: UIScreen.capturedDidChangeNotification,
      object: nil
    )
  }

  @objc private func handleScreenCaptureChanged() {
    isScreenCaptured = UIScreen.main.isCaptured
    refreshPrivacyOverlay()
  }

  private func refreshPrivacyOverlay() {
    let shouldShow = (privacyOverlayEnabled && isAppInactive) || (antiCaptureEnabled && isScreenCaptured)
    if shouldShow {
      showPrivacyOverlay()
    } else {
      hidePrivacyOverlay()
    }
  }

  private func showPrivacyOverlay() {
    guard let window = currentKeyWindow() else { return }
    if window.viewWithTag(privacyOverlayTag) != nil { return }

    let overlay = UIView(frame: window.bounds)
    overlay.tag = privacyOverlayTag
    overlay.backgroundColor = .systemBackground
    overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(overlay)
  }

  private func hidePrivacyOverlay() {
    currentKeyWindow()?.viewWithTag(privacyOverlayTag)?.removeFromSuperview()
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let privacy = FlutterMethodChannel(name: privacyChannel, binaryMessenger: controller.binaryMessenger)
      privacy.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(FlutterError(code: "deallocated", message: nil, details: nil))
          return
        }
        guard call.method == "configure", let args = call.arguments as? [String: Any] else {
          result(FlutterMethodNotImplemented)
          return
        }

        self.privacyOverlayEnabled = (args["iosPrivacyOverlay"] as? Bool) ?? false
        self.antiCaptureEnabled = (args["iosAntiCapture"] as? Bool) ?? false
        if self.antiCaptureEnabled {
          self.installCaptureObserverIfNeeded()
          self.isScreenCaptured = UIScreen.main.isCaptured
        } else {
          self.isScreenCaptured = false
        }
        self.refreshPrivacyOverlay()
        result(nil)
      }

      let events = FlutterEventChannel(name: signalEventsChannel, binaryMessenger: controller.binaryMessenger)
      events.setStreamHandler(self)

      let signal = FlutterMethodChannel(name: signalChannel, binaryMessenger: controller.binaryMessenger)
      signal.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(FlutterError(code: "deallocated", message: nil, details: nil))
          return
        }

        do {
          switch call.method {
          case "initUser":
            guard let args = call.arguments as? [String: Any], let userId = args["userId"] as? Int else {
              result(FlutterError(code: "bad_args", message: "Invalid userId", details: nil))
              return
            }
            let deviceId = (args["deviceId"] as? Int) ?? 1
            let bundle = try self.signalManager.initUser(userId: userId, deviceId: deviceId)
            UserDefaults.standard.set(userId, forKey: "signal_current_user_id")
            UserDefaults.standard.set(deviceId, forKey: "signal_current_device_id")
            result(bundle)

          case "hasSession":
            guard let args = call.arguments as? [String: Any], let peerUserId = args["peerUserId"] as? Int else {
              result(false)
              return
            }
            let deviceId = (args["deviceId"] as? Int) ?? UserDefaults.standard.integer(forKey: "signal_current_device_id")
            result(try self.signalManager.hasSession(peerUserId: peerUserId, deviceId: max(deviceId, 1)))

          case "encrypt":
            guard
              let args = call.arguments as? [String: Any],
              let peerUserId = args["peerUserId"] as? Int,
              let plaintext = args["plaintext"] as? String
            else {
              result(FlutterError(code: "bad_args", message: "Invalid encrypt args", details: nil))
              return
            }
            let deviceId = (args["deviceId"] as? Int) ?? UserDefaults.standard.integer(forKey: "signal_current_device_id")
            let bundle = args["preKeyBundle"] as? [String: Any]
            result(try self.signalManager.encrypt(
              peerUserId: peerUserId,
              deviceId: max(deviceId, 1),
              plaintext: plaintext,
              preKeyBundle: bundle
            ))

          case "decrypt":
            guard
              let args = call.arguments as? [String: Any],
              let peerUserId = args["peerUserId"] as? Int,
              let ciphertext = args["ciphertext"] as? String
            else {
              result(FlutterError(code: "bad_args", message: "Invalid decrypt args", details: nil))
              return
            }
            let deviceId = (args["deviceId"] as? Int) ?? UserDefaults.standard.integer(forKey: "signal_current_device_id")
            result(try self.signalManager.decrypt(
              peerUserId: peerUserId,
              deviceId: max(deviceId, 1),
              ciphertext: ciphertext
            ))

          case "getFingerprint":
            guard let args = call.arguments as? [String: Any], let peerUserId = args["peerUserId"] as? Int else {
              result(FlutterError(code: "bad_args", message: "Invalid getFingerprint args", details: nil))
              return
            }
            let deviceId = (args["deviceId"] as? Int) ?? UserDefaults.standard.integer(forKey: "signal_current_device_id")
            result(try self.signalManager.fingerprint(peerUserId: peerUserId, deviceId: max(deviceId, 1)))

          default:
            result(FlutterMethodNotImplemented)
          }
        } catch {
          let details = String(describing: error)
          let message = details.isEmpty ? error.localizedDescription : details
          result(FlutterError(code: "signal_error", message: message, details: nil))
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    super.applicationWillResignActive(application)
    isAppInactive = true
    refreshPrivacyOverlay()
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    isAppInactive = false
    if antiCaptureEnabled {
      isScreenCaptured = UIScreen.main.isCaptured
    } else {
      isScreenCaptured = false
    }
    refreshPrivacyOverlay()
  }
}

extension AppDelegate: FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    signalEventsSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    signalEventsSink = nil
    return nil
  }
}
