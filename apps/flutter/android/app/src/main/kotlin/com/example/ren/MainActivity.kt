package com.example.ren

import android.os.Bundle
import android.util.Base64
import android.view.WindowManager
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.security.SecureRandom
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.time.Instant

class MainActivity : FlutterActivity() {
    private val privacyChannel = "ren/privacy_protection"
    private val signalChannel = "ren/signal_protocol"
    private val signalEventsChannel = "ren/signal_protocol/events"

    private lateinit var securePrefs: android.content.SharedPreferences
    private var signalEventsSink: EventChannel.EventSink? = null

    private val signal = SignalRuntime(
        onIdentityChanged = { peerUserId, oldFp, newFp ->
            signalEventsSink?.success(
                mapOf(
                    "type" to "identity_changed",
                    "peer_user_id" to peerUserId,
                    "previous_fingerprint" to oldFp,
                    "current_fingerprint" to newFp,
                ),
            )
        },
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val masterKey = MasterKey.Builder(this)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        securePrefs = EncryptedSharedPreferences.create(
            this,
            "signal_secure_store",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
        signal.attachPrefs(securePrefs)
    }

    private fun applySecureFlag(enabled: Boolean) {
        if (enabled) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE,
            )
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, privacyChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "configure") {
                    val enabled = call.argument<Boolean>("androidFlagSecure") ?: false
                    applySecureFlag(enabled)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, signalEventsChannel)
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        signalEventsSink = events
                    }

                    override fun onCancel(arguments: Any?) {
                        signalEventsSink = null
                    }
                },
            )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, signalChannel)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "initUser" -> {
                            val userId = call.argument<Int>("userId") ?: 0
                            val deviceId = call.argument<Int>("deviceId") ?: 1
                            if (userId <= 0) {
                                result.error("bad_args", "Invalid userId", null)
                                return@setMethodCallHandler
                            }
                            result.success(signal.initUser(userId, deviceId))
                        }
                        "hasSession" -> {
                            val peerUserId = call.argument<Int>("peerUserId") ?: 0
                            val deviceId = call.argument<Int>("deviceId") ?: 1
                            if (peerUserId <= 0) {
                                result.success(false)
                                return@setMethodCallHandler
                            }
                            result.success(signal.hasSession(peerUserId, deviceId))
                        }
                        "encrypt" -> {
                            val peerUserId = call.argument<Int>("peerUserId") ?: 0
                            val deviceId = call.argument<Int>("deviceId") ?: 1
                            val plaintext = call.argument<String>("plaintext") ?: ""
                            @Suppress("UNCHECKED_CAST")
                            val bundle = call.argument<Map<String, Any?>>("preKeyBundle")
                            if (peerUserId <= 0 || plaintext.isEmpty()) {
                                result.error("bad_args", "Invalid encrypt args", null)
                                return@setMethodCallHandler
                            }
                            result.success(signal.encrypt(peerUserId, deviceId, plaintext, bundle))
                        }
                        "decrypt" -> {
                            val peerUserId = call.argument<Int>("peerUserId") ?: 0
                            val deviceId = call.argument<Int>("deviceId") ?: 1
                            val ciphertext = call.argument<String>("ciphertext") ?: ""
                            if (peerUserId <= 0 || ciphertext.isEmpty()) {
                                result.error("bad_args", "Invalid decrypt args", null)
                                return@setMethodCallHandler
                            }
                            result.success(signal.decrypt(peerUserId, deviceId, ciphertext))
                        }
                        "resetSession" -> {
                            val peerUserId = call.argument<Int>("peerUserId") ?: 0
                            val deviceId = call.argument<Int>("deviceId") ?: 1
                            if (peerUserId <= 0) {
                                result.error("bad_args", "Invalid resetSession args", null)
                                return@setMethodCallHandler
                            }
                            signal.resetSession(peerUserId, deviceId)
                            result.success(null)
                        }
                        "getFingerprint" -> {
                            val peerUserId = call.argument<Int>("peerUserId") ?: 0
                            val deviceId = call.argument<Int>("deviceId") ?: 1
                            if (peerUserId <= 0) {
                                result.error("bad_args", "Invalid getFingerprint args", null)
                                return@setMethodCallHandler
                            }
                            result.success(signal.getFingerprint(peerUserId, deviceId))
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("signal_error", e.message ?: "signal failure", null)
                }
            }
    }
}

private class SignalRuntime(
    private val onIdentityChanged: (peerUserId: Int, oldFp: String?, newFp: String?) -> Unit,
) {
    private var prefs: android.content.SharedPreferences? = null

    private var currentUserId: Int = 0
    private var currentDeviceId: Int = 1

    private var protocolStore: Any? = null

    private val storeIdentityPair = "signal_identity_pair"
    private val storeRegistrationId = "signal_registration_id"
    private val storeSignedPreKey = "signal_signed_pre_key"
    private val storeKyberPreKey = "signal_kyber_pre_key"
    private val storeOneTimePreKeys = "signal_one_time_pre_keys"
    private val storeSessionsPrefix = "signal_session_"
    private val storePeerIdentityPrefix = "signal_peer_identity_"
    private val oneTimePreKeyStart = 1000
    private val oneTimePreKeyTargetCount = 50

    fun attachPrefs(sharedPrefs: android.content.SharedPreferences) {
        prefs = sharedPrefs
    }

    private fun requirePrefs(): android.content.SharedPreferences {
        return prefs ?: throw IllegalStateException("Signal prefs not attached")
    }

    private fun k(base: String): String = "${base}_${currentUserId}_${currentDeviceId}"

    private fun sessionKey(peerUserId: Int, deviceId: Int): String =
        "${k(storeSessionsPrefix)}_${peerUserId}_${deviceId}"

    private fun peerIdentityKey(peerUserId: Int, deviceId: Int): String =
        "${k(storePeerIdentityPrefix)}_${peerUserId}_${deviceId}"

    private fun b64(data: ByteArray): String = Base64.encodeToString(data, Base64.NO_WRAP)

    private fun b64d(value: String): ByteArray = Base64.decode(value, Base64.DEFAULT)

    private fun nowInstant(): Any {
        return Instant.now()
    }

    private fun cls(name: String): Class<*> = Class.forName(name)

    private fun findMethod(target: Class<*>, name: String, argc: Int): java.lang.reflect.Method {
        return target.methods.firstOrNull { it.name == name && it.parameterTypes.size == argc }
            ?: target.declaredMethods.firstOrNull { it.name == name && it.parameterTypes.size == argc }
            ?: throw NoSuchMethodException("$name/$argc in ${target.name}")
    }

    private fun invoke(instance: Any, name: String, vararg args: Any?): Any? {
        val m = findMethod(instance.javaClass, name, args.size)
        m.isAccessible = true
        return m.invoke(instance, *args)
    }

    private fun invokeMaybe(instance: Any, name: String, vararg args: Any?): Any? {
        return try {
            invoke(instance, name, *args)
        } catch (_: Exception) {
            null
        }
    }

    private fun invokeStatic(className: String, name: String, vararg args: Any?): Any? {
        val c = cls(className)
        val m = findMethod(c, name, args.size)
        m.isAccessible = true
        return m.invoke(null, *args)
    }

    private fun invokeStaticMaybe(className: String, name: String, vararg args: Any?): Any? {
        return try {
            invokeStatic(className, name, *args)
        } catch (_: Exception) {
            null
        }
    }

    private fun ctor(className: String, vararg args: Any?): Any {
        val c = cls(className)
        val cons = c.constructors.firstOrNull { it.parameterTypes.size == args.size }
            ?: throw NoSuchMethodException("ctor ${c.name}/${args.size}")
        cons.isAccessible = true
        return cons.newInstance(*args)
    }

    private fun parseStoredPreKeys(raw: String?): LinkedHashMap<Int, String> {
        val out = LinkedHashMap<Int, String>()
        if (raw.isNullOrEmpty()) return out
        val arr = try {
            org.json.JSONArray(raw)
        } catch (_: Exception) {
            return out
        }
        for (i in 0 until arr.length()) {
            val item = arr.optJSONObject(i) ?: continue
            val id = item.optInt("id", 0)
            val recordB64 = item.optString("record")
            if (id <= 0 || recordB64.isEmpty()) continue
            out[id] = recordB64
        }
        return out
    }

    private fun persistOneTimePreKeys(records: Map<Int, String>) {
        val p = requirePrefs()
        val arr = org.json.JSONArray()
        for ((id, recordB64) in records.toSortedMap()) {
            arr.put(JSONObject().put("id", id).put("record", recordB64))
        }
        p.edit().putString(k(storeOneTimePreKeys), arr.toString()).apply()
    }

    private fun syncAndTopUpOneTimePreKeys(store: Any) {
        val p = requirePrefs()
        val saved = parseStoredPreKeys(p.getString(k(storeOneTimePreKeys), null))
        val active = LinkedHashMap<Int, String>()

        for ((id, recordB64) in saved) {
            val record = try {
                ctor(
                    "org.signal.libsignal.protocol.state.PreKeyRecord",
                    b64d(recordB64),
                )
            } catch (_: Exception) {
                null
            } ?: continue
            try {
                invoke(store, "storePreKey", id, record)
                val serialized = invoke(record, "serialize") as? ByteArray ?: continue
                active[id] = b64(serialized)
            } catch (_: Exception) {
                // Skip malformed persisted pre-key entries.
            }
        }

        if (active.size < oneTimePreKeyTargetCount) {
            val need = oneTimePreKeyTargetCount - active.size
            val nextId = maxOf(oneTimePreKeyStart, (active.keys.maxOrNull() ?: (oneTimePreKeyStart - 1)) + 1)
            val generated = invokeStatic(
                "org.signal.libsignal.protocol.util.KeyHelper",
                "generatePreKeys",
                nextId,
                need,
            ) as? List<*> ?: emptyList<Any>()

            for (item in generated) {
                if (item == null) continue
                val id = (invoke(item, "getId") as? Number)?.toInt() ?: continue
                val serialized = invoke(item, "serialize") as? ByteArray ?: continue
                try {
                    invoke(store, "storePreKey", id, item)
                    active[id] = b64(serialized)
                } catch (_: Exception) {
                    // Skip failed generated pre-key, continue with others.
                }
            }
        }

        persistOneTimePreKeys(active)
    }

    private fun ensureLoaded(userId: Int, deviceId: Int) {
        if (protocolStore != null && currentUserId == userId && currentDeviceId == deviceId) return

        currentUserId = userId
        currentDeviceId = deviceId.coerceAtLeast(1)
        val p = requirePrefs()

        val identityPairObj = run {
            val saved = p.getString(k(storeIdentityPair), null)
            if (!saved.isNullOrEmpty()) {
                try {
                    ctor(
                        "org.signal.libsignal.protocol.IdentityKeyPair",
                        b64d(saved),
                    )
                } catch (_: Exception) {
                    null
                }
            } else {
                null
            }
        } ?: run {
            val generated = invokeStatic(
                "org.signal.libsignal.protocol.util.KeyHelper",
                "generateIdentityKeyPair",
            ) ?: throw IllegalStateException("Unable to generate identity key pair")
            val serialized = invoke(generated, "serialize") as? ByteArray
                ?: throw IllegalStateException("Unable to serialize identity key pair")
            p.edit().putString(k(storeIdentityPair), b64(serialized)).apply()
            generated
        }

        val registrationId = p.getInt(k(storeRegistrationId), 0).takeIf { it > 0 } ?: run {
            val generated = try {
                (invokeStatic("org.signal.libsignal.protocol.util.KeyHelper", "generateRegistrationId", false) as Number).toInt()
            } catch (_: Exception) {
                SecureRandom().nextInt(16380) + 1
            }
            p.edit().putInt(k(storeRegistrationId), generated).apply()
            generated
        }

        val store = ctor(
            "org.signal.libsignal.protocol.state.impl.InMemorySignalProtocolStore",
            identityPairObj,
            registrationId,
        )

        // Signed pre-key
        val signedRecordObj = run {
            val saved = p.getString(k(storeSignedPreKey), null)
            if (!saved.isNullOrEmpty()) {
                try {
                    ctor("org.signal.libsignal.protocol.state.SignedPreKeyRecord", b64d(saved))
                } catch (_: Exception) {
                    null
                }
            } else {
                null
            }
        } ?: run {
            val generated = invokeStatic(
                "org.signal.libsignal.protocol.util.KeyHelper",
                "generateSignedPreKey",
                identityPairObj,
                1,
            ) ?: throw IllegalStateException("Unable to generate signed pre-key")
            val serialized = invoke(generated, "serialize") as? ByteArray
                ?: throw IllegalStateException("Unable to serialize signed pre-key")
            p.edit().putString(k(storeSignedPreKey), b64(serialized)).apply()
            generated
        }
        invoke(store, "storeSignedPreKey", 1, signedRecordObj)

        val kyberRecordObj = run {
            val saved = p.getString(k(storeKyberPreKey), null)
            if (!saved.isNullOrEmpty()) {
                try {
                    ctor("org.signal.libsignal.protocol.state.KyberPreKeyRecord", b64d(saved))
                } catch (_: Exception) {
                    null
                }
            } else {
                null
            }
        } ?: run {
            val generated = generateKyberPreKeyRecord(identityPairObj, signedRecordObj)
                ?: throw IllegalStateException("Unable to generate kyber pre-key")
            val serialized = invoke(generated, "serialize") as? ByteArray
                ?: throw IllegalStateException("Unable to serialize kyber pre-key")
            p.edit().putString(k(storeKyberPreKey), b64(serialized)).apply()
            generated
        }
        invokeMaybe(store, "storeKyberPreKey", 1, kyberRecordObj)

        // One-time pre-keys: load persisted, purge invalid/consumed, and top up pool.
        syncAndTopUpOneTimePreKeys(store)

        // Sessions
        val all = p.all
        for ((key, value) in all) {
            if (!key.startsWith(k(storeSessionsPrefix))) continue
            val b64v = value as? String ?: continue
            if (b64v.isEmpty()) continue
            val parts = key.removePrefix("${k(storeSessionsPrefix)}_").split("_")
            if (parts.size < 2) continue
            val peer = parts[0].toIntOrNull() ?: continue
            val dev = parts[1].toIntOrNull() ?: continue
            val address = ctor(
                "org.signal.libsignal.protocol.SignalProtocolAddress",
                peer.toString(),
                dev,
            )
            val session = ctor(
                "org.signal.libsignal.protocol.state.SessionRecord",
                b64d(b64v),
            )
            invoke(store, "storeSession", address, session)
        }

        protocolStore = store
    }

    private fun generateKyberPreKeyRecord(identityPairObj: Any, signedRecordObj: Any): Any? {
        val candidates: List<() -> Any?> = listOf(
            {
                invokeStaticMaybe(
                    "org.signal.libsignal.protocol.util.KeyHelper",
                    "generateLastResortKyberPreKey",
                    identityPairObj,
                    signedRecordObj,
                )
            },
            {
                invokeStaticMaybe(
                    "org.signal.libsignal.protocol.util.KeyHelper",
                    "generateKyberPreKey",
                    identityPairObj,
                    1,
                    1,
                )
            },
            {
                invokeStaticMaybe(
                    "org.signal.libsignal.protocol.util.KeyHelper",
                    "generateKyberPreKey",
                    identityPairObj,
                    1,
                )
            },
            {
                val list = invokeStaticMaybe(
                    "org.signal.libsignal.protocol.util.KeyHelper",
                    "generateKyberPreKeys",
                    identityPairObj,
                    1,
                    1,
                ) as? List<*>
                list?.firstOrNull()
            },
        )
        for (candidate in candidates) {
            val value = candidate() ?: continue
            if (value is List<*>) {
                val first = value.firstOrNull()
                if (first != null) return first
            } else {
                return value
            }
        }

        // Low-level fallback: KEMKeyPair + signature + KyberPreKeyRecord constructor
        val kemPair = run {
            invokeStaticMaybe("org.signal.libsignal.protocol.kem.KEMKeyPair", "generate")
                ?: run {
                    val keyTypeCls = cls("org.signal.libsignal.protocol.kem.KEMKeyType")
                    val enumVals = keyTypeCls.enumConstants
                    if (enumVals != null && enumVals.isNotEmpty()) {
                        invokeStaticMaybe(
                            "org.signal.libsignal.protocol.kem.KEMKeyPair",
                            "generate",
                            enumVals[0],
                        )
                    } else {
                        null
                    }
                }
        } ?: return null

        val kemPublic = invoke(kemPair, "getPublicKey") ?: invoke(kemPair, "publicKey") ?: return null
        val kemPublicBytes = (invoke(kemPublic, "serialize") as? ByteArray) ?: return null
        val identityPrivate = invoke(identityPairObj, "getPrivateKey") ?: return null
        val signature = (invokeMaybe(identityPrivate, "calculateSignature", kemPublicBytes) as? ByteArray)
            ?: (invokeMaybe(identityPrivate, "generateSignature", kemPublicBytes) as? ByteArray)
            ?: return null

        return try {
            ctor(
                "org.signal.libsignal.protocol.state.KyberPreKeyRecord",
                1,
                Instant.now().toEpochMilli(),
                kemPair,
                signature,
            )
        } catch (_: Exception) {
            null
        }
    }

    private fun parseBundle(bundle: Map<String, Any?>): Any {
        val regId = (bundle["registration_id"] as? Number)?.toInt() ?: 1
        val deviceId = (bundle["device_id"] as? Number)?.toInt() ?: 1
        val signedPreKeyId = (bundle["signed_pre_key_id"] as? Number)?.toInt() ?: 1
        val signedPreKeyB64 = (bundle["signed_pre_key"] as? String).orEmpty()
        val signedPreKeySigB64 = (bundle["signed_pre_key_signature"] as? String).orEmpty()
        val identityB64 = (bundle["identity_key"] as? String).orEmpty()

        if (signedPreKeyB64.isEmpty() || signedPreKeySigB64.isEmpty() || identityB64.isEmpty()) {
            throw IllegalArgumentException("Malformed preKeyBundle")
        }

        val signedPreKeyPublic = invokeStatic(
            "org.signal.libsignal.protocol.ecc.Curve",
            "decodePoint",
            b64d(signedPreKeyB64),
            0,
        ) ?: throw IllegalStateException("Unable to decode signed pre-key")

        val identityKey = ctor(
            "org.signal.libsignal.protocol.IdentityKey",
            b64d(identityB64),
            0,
        )

        @Suppress("UNCHECKED_CAST")
        val oneTime = bundle["one_time_pre_keys"] as? List<Map<String, Any?>>
        val firstPre = oneTime?.firstOrNull()

        if (firstPre != null) {
            val preKeyId = (firstPre["id"] as? Number)?.toInt() ?: -1
            val preKeyB64 = (firstPre["key"] as? String).orEmpty()
            if (preKeyId > 0 && preKeyB64.isNotEmpty()) {
                val preKeyPublic = invokeStatic(
                    "org.signal.libsignal.protocol.ecc.Curve",
                    "decodePoint",
                    b64d(preKeyB64),
                    0,
                ) ?: throw IllegalStateException("Unable to decode pre-key")
                return ctor(
                    "org.signal.libsignal.protocol.state.PreKeyBundle",
                    regId,
                    deviceId,
                    preKeyId,
                    preKeyPublic,
                    signedPreKeyId,
                    signedPreKeyPublic,
                    b64d(signedPreKeySigB64),
                    identityKey,
                )
            }
        }

        return ctor(
            "org.signal.libsignal.protocol.state.PreKeyBundle",
            regId,
            deviceId,
            -1,
            null,
            signedPreKeyId,
            signedPreKeyPublic,
            b64d(signedPreKeySigB64),
            identityKey,
        )
    }

    private fun saveSession(peerUserId: Int, deviceId: Int, address: Any) {
        val p = requirePrefs()
        val store = protocolStore ?: return
        val session = invoke(store, "loadSession", address) ?: return
        val serialized = invoke(session, "serialize") as? ByteArray ?: return
        p.edit().putString(sessionKey(peerUserId, deviceId), b64(serialized)).apply()
    }

    private fun rememberPeerIdentity(peerUserId: Int, deviceId: Int, identityB64: String) {
        if (identityB64.isEmpty()) return
        val p = requirePrefs()
        val key = peerIdentityKey(peerUserId, deviceId)
        val old = p.getString(key, null)
        if (!old.isNullOrEmpty() && old != identityB64) {
            onIdentityChanged(peerUserId, old, identityB64)
        }
        p.edit().putString(key, identityB64).apply()
    }

    fun initUser(userId: Int, deviceId: Int): Map<String, Any> {
        ensureLoaded(userId, deviceId)
        val store = protocolStore ?: throw IllegalStateException("store not initialized")

        val identityPair = invoke(store, "getIdentityKeyPair")
            ?: invoke(store, "identityKeyPair")
            ?: throw IllegalStateException("identity pair missing")

        val registrationId = (invoke(store, "getLocalRegistrationId") as? Number)?.toInt()
            ?: (invoke(store, "localRegistrationId") as? Number)?.toInt()
            ?: throw IllegalStateException("registration id missing")

        val identityKey = invoke(identityPair, "getPublicKey")
            ?: throw IllegalStateException("identity public key missing")
        val identityBytes = invoke(identityKey, "serialize") as? ByteArray
            ?: throw IllegalStateException("identity serialize failed")
        val keyVersion = 1
        val identityPrivate = invoke(identityPair, "getPrivateKey")
            ?: throw IllegalStateException("identity private key missing")
        val signedPayload = ByteBuffer
            .allocate(identityBytes.size + 4)
            .order(ByteOrder.LITTLE_ENDIAN)
            .put(identityBytes)
            .putInt(keyVersion)
            .array()
        val identitySignature = (invokeMaybe(identityPrivate, "calculateSignature", signedPayload) as? ByteArray)
            ?: (invokeMaybe(identityPrivate, "generateSignature", signedPayload) as? ByteArray)
            ?: throw IllegalStateException("identity signature failed")

        val signedRecord = invoke(store, "loadSignedPreKey", 1)
            ?: throw IllegalStateException("signed pre-key missing")
        val signedPub = invoke(signedRecord, "getKeyPair")?.let { invoke(it, "getPublicKey") }
            ?: invoke(signedRecord, "getPublicKey")
            ?: throw IllegalStateException("signed pre-key public missing")
        val signedPubBytes = invoke(signedPub, "serialize") as? ByteArray
            ?: throw IllegalStateException("signed pre-key serialize failed")
        val signedSig = (invoke(signedRecord, "getSignature") as? ByteArray) ?: ByteArray(0)
        val kyberRecord = invokeMaybe(store, "loadKyberPreKey", 1)
        val kyberPub = kyberRecord?.let { invokeMaybe(it, "getKeyPair")?.let { kp -> invokeMaybe(kp, "getPublicKey") } }
            ?: kyberRecord?.let { invokeMaybe(it, "getPublicKey") }
        val kyberPubBytes = (kyberPub?.let { invokeMaybe(it, "serialize") } as? ByteArray) ?: ByteArray(0)
        val kyberSig = (kyberRecord?.let { invokeMaybe(it, "getSignature") } as? ByteArray) ?: ByteArray(0)

        val p = requirePrefs()
        val oneTimeRaw = p.getString(k(storeOneTimePreKeys), "[]") ?: "[]"
        val arr = org.json.JSONArray(oneTimeRaw)
        val oneTime = mutableListOf<Map<String, Any>>()
        for (i in 0 until arr.length()) {
            val item = arr.getJSONObject(i)
            val id = item.optInt("id", 0)
            val recordB64 = item.optString("record")
            if (id <= 0 || recordB64.isEmpty()) continue
            val rec = ctor("org.signal.libsignal.protocol.state.PreKeyRecord", b64d(recordB64))
            val pub = invoke(rec, "getKeyPair")?.let { invoke(it, "getPublicKey") }
                ?: invoke(rec, "getPublicKey")
                ?: continue
            val pubBytes = invoke(pub, "serialize") as? ByteArray ?: continue
            oneTime += mapOf("id" to id, "key" to b64(pubBytes))
        }

        return mapOf(
            "public_key" to b64(identityBytes),
            "identity_key" to b64(identityBytes),
            "signature" to b64(identitySignature),
            "key_version" to keyVersion,
            "signed_at" to Instant.now().toString(),
            "registration_id" to registrationId,
            "signed_pre_key_id" to 1,
            "signed_pre_key" to b64(signedPubBytes),
            "signed_pre_key_signature" to b64(signedSig),
            "kyber_pre_key_id" to 1,
            "kyber_pre_key" to b64(kyberPubBytes),
            "kyber_pre_key_signature" to b64(kyberSig),
            "one_time_pre_keys" to oneTime,
        )
    }

    fun hasSession(peerUserId: Int, deviceId: Int): Boolean {
        ensureLoaded(currentUserId.takeIf { it > 0 } ?: throw IllegalStateException("initUser required"), currentDeviceId)
        val p = requirePrefs()
        return !p.getString(sessionKey(peerUserId, deviceId.coerceAtLeast(1)), null).isNullOrEmpty()
    }

    fun encrypt(peerUserId: Int, deviceId: Int, plaintext: String, bundle: Map<String, Any?>?): String {
        val me = currentUserId
        if (me <= 0) throw IllegalStateException("initUser required")
        val peerDevice = deviceId.coerceAtLeast(1)
        ensureLoaded(me, currentDeviceId)

        val store = protocolStore ?: throw IllegalStateException("store not initialized")
        val address = ctor("org.signal.libsignal.protocol.SignalProtocolAddress", peerUserId.toString(), peerDevice)

        val has = hasSession(peerUserId, peerDevice)
        if (!has) {
            val preKeyBundle = bundle ?: throw IllegalStateException("Missing preKeyBundle")
            val parsed = parseBundle(preKeyBundle)

            val builder = try {
                ctor(
                    "org.signal.libsignal.protocol.SessionBuilder",
                    store,
                    store,
                    store,
                    store,
                    address,
                )
            } catch (_: Exception) {
                ctor(
                    "org.signal.libsignal.protocol.SessionBuilder",
                    store,
                    store,
                    store,
                    address,
                )
            }

            try {
                invoke(builder, "process", parsed, nowInstant())
            } catch (_: Exception) {
                invoke(builder, "process", parsed)
            }

            val identityB64 = (preKeyBundle["identity_key"] as? String).orEmpty()
            rememberPeerIdentity(peerUserId, peerDevice, identityB64)
            saveSession(peerUserId, peerDevice, address)
        }

        val cipher = try {
            ctor(
                "org.signal.libsignal.protocol.SessionCipher",
                store,
                store,
                store,
                store,
                store,
                address,
            )
        } catch (_: Exception) {
            ctor(
                "org.signal.libsignal.protocol.SessionCipher",
                store,
                store,
                store,
                store,
                address,
            )
        }

        val ciphertextMessage = try {
            invoke(cipher, "encrypt", plaintext.toByteArray(Charsets.UTF_8), nowInstant())
        } catch (_: Exception) {
            invoke(cipher, "encrypt", plaintext.toByteArray(Charsets.UTF_8))
        } ?: throw IllegalStateException("Signal encrypt failed")

        val serialized = invoke(ciphertextMessage, "serialize") as? ByteArray
            ?: throw IllegalStateException("Signal ciphertext serialize failed")

        val typeNum = (invoke(ciphertextMessage, "getType") as? Number)?.toInt()
            ?: (invoke(ciphertextMessage, "getMessageType") as? Number)?.toInt()
            ?: 2
        val type = if (typeNum == 3 || typeNum == 1) "prekey" else "whisper"

        saveSession(peerUserId, peerDevice, address)

        val envelope = JSONObject()
            .put("v", 2)
            .put("t", type)
            .put("b", b64(serialized))
        return b64(envelope.toString().toByteArray(Charsets.UTF_8))
    }

    fun decrypt(peerUserId: Int, deviceId: Int, ciphertext: String): String {
        val me = currentUserId
        if (me <= 0) throw IllegalStateException("initUser required")
        val peerDevice = deviceId.coerceAtLeast(1)
        ensureLoaded(me, currentDeviceId)

        val store = protocolStore ?: throw IllegalStateException("store not initialized")
        val address = ctor("org.signal.libsignal.protocol.SignalProtocolAddress", peerUserId.toString(), peerDevice)

        val env = JSONObject(String(b64d(ciphertext), Charsets.UTF_8))
        val body = env.optString("b")
        val type = env.optString("t")
        if (body.isEmpty()) {
            throw IllegalArgumentException("Malformed ciphertext envelope")
        }

        val cipher = try {
            ctor(
                "org.signal.libsignal.protocol.SessionCipher",
                store,
                store,
                store,
                store,
                store,
                address,
            )
        } catch (_: Exception) {
            ctor(
                "org.signal.libsignal.protocol.SessionCipher",
                store,
                store,
                store,
                store,
                address,
            )
        }

        val plainBytes = if (type == "prekey") {
            val msg = ctor("org.signal.libsignal.protocol.PreKeySignalMessage", b64d(body))
            try {
                invoke(cipher, "decrypt", msg) as ByteArray
            } catch (_: Exception) {
                invoke(cipher, "decrypt", msg, nowInstant()) as ByteArray
            }
        } else {
            val msg = ctor("org.signal.libsignal.protocol.SignalMessage", b64d(body))
            try {
                invoke(cipher, "decrypt", msg) as ByteArray
            } catch (_: Exception) {
                invoke(cipher, "decrypt", msg, nowInstant()) as ByteArray
            }
        }

        if (type == "prekey") {
            syncAndTopUpOneTimePreKeys(store)
        }
        saveSession(peerUserId, peerDevice, address)
        return String(plainBytes, Charsets.UTF_8)
    }

    fun resetSession(peerUserId: Int, deviceId: Int) {
        val me = currentUserId
        if (me <= 0) throw IllegalStateException("initUser required")
        val peerDevice = deviceId.coerceAtLeast(1)
        ensureLoaded(me, currentDeviceId)

        val p = requirePrefs()
        p.edit().remove(sessionKey(peerUserId, peerDevice)).apply()

        // Force store reload from persisted state on next operation.
        protocolStore = null
    }

    fun getFingerprint(peerUserId: Int, deviceId: Int): String {
        val p = requirePrefs()
        val peer = p.getString(peerIdentityKey(peerUserId, deviceId.coerceAtLeast(1)), "") ?: ""
        if (peer.isEmpty()) {
            throw IllegalStateException("No peer identity for fingerprint")
        }
        return peer
    }
}
