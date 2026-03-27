package com.example.ren

import android.content.Context
import android.util.Base64
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import org.signal.libsignal.protocol.IdentityKey
import org.signal.libsignal.protocol.IdentityKeyPair
import org.signal.libsignal.protocol.SignalProtocolAddress
import org.signal.libsignal.protocol.SessionBuilder
import org.signal.libsignal.protocol.SessionCipher
import org.signal.libsignal.protocol.SignalMessage
import org.signal.libsignal.protocol.PreKeySignalMessage
import org.signal.libsignal.protocol.state.IdentityKeyStore
import org.signal.libsignal.protocol.state.KyberPreKeyRecord
import org.signal.libsignal.protocol.state.PreKeyRecord
import org.signal.libsignal.protocol.state.PreKeyStore
import org.signal.libsignal.protocol.state.SessionRecord
import org.signal.libsignal.protocol.state.SessionStore
import org.signal.libsignal.protocol.state.SignalProtocolStore
import org.signal.libsignal.protocol.state.SignedPreKeyRecord
import org.signal.libsignal.protocol.state.SignedPreKeyStore
import org.signal.libsignal.protocol.util.KeyHelper
import org.signal.libsignal.protocol.kem.KEMKeyPair
import org.signal.libsignal.protocol.kem.KEMPublicKey
import org.signal.libsignal.protocol.ecc.Curve
import java.io.File
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

private data class SignalStoreSnapshot(
    val version: Int,
    val identityKeyPair: String,
    val registrationId: Int,
    val publicKeys: Map<String, String>,
    val preKeys: Map<String, String>,
    val signedPreKeys: Map<String, String>,
    val kyberPreKeys: Map<String, String>,
    val sessions: Map<String, String>,
    val senderKeys: Map<String, String>,
    val nextPreKeyId: Int,
    val nextSignedPreKeyId: Int,
    val nextKyberPreKeyId: Int
)

private class PersistentSignalProtocolStore(private val storageFile: File) : SignalProtocolStore,
    IdentityKeyStore, PreKeyStore, SignedPreKeyStore, SessionStore {
    private val lock = Any()
    private var identityKeyPair: IdentityKeyPair
    private var registrationId: Int
    private val publicKeys: MutableMap<SignalProtocolAddress, IdentityKey> = mutableMapOf()
    private val preKeys: MutableMap<Int, PreKeyRecord> = mutableMapOf()
    private val signedPreKeys: MutableMap<Int, SignedPreKeyRecord> = mutableMapOf()
    private val kyberPreKeys: MutableMap<Int, KyberPreKeyRecord> = mutableMapOf()
    private val sessions: MutableMap<SignalProtocolAddress, SessionRecord> = mutableMapOf()
    private val senderKeys: MutableMap<String, ByteArray> = mutableMapOf()
    var nextPreKeyId: Int
    var nextSignedPreKeyId: Int
    var nextKyberPreKeyId: Int
    var onIdentityChanged: ((SignalProtocolAddress, IdentityKey?, IdentityKey?) -> Unit)? = null

    val preKeyRecords: Map<Int, PreKeyRecord>
        get() = preKeys
    val signedPreKeyRecords: Map<Int, SignedPreKeyRecord>
        get() = signedPreKeys
    val kyberPreKeyRecords: Map<Int, KyberPreKeyRecord>
        get() = kyberPreKeys
    val identityKeyPairValue: IdentityKeyPair
        get() = identityKeyPair
    val localRegistrationIdValue: Int
        get() = registrationId

    init {
        if (storageFile.exists()) {
            val raw = storageFile.readText()
            val json = JSONObject(raw)
            val identityBytes = Base64.decode(json.getString("identityKeyPair"), Base64.DEFAULT)
            identityKeyPair = IdentityKeyPair(identityBytes)
            registrationId = json.getInt("registrationId")
            nextPreKeyId = json.optInt("nextPreKeyId", 1)
            nextSignedPreKeyId = json.optInt("nextSignedPreKeyId", 1)
            nextKyberPreKeyId = json.optInt("nextKyberPreKeyId", 1)

            val pkJson = json.optJSONObject("publicKeys") ?: JSONObject()
            pkJson.keys().forEach { key ->
                val value = pkJson.optString(key, "")
                if (value.isNotEmpty()) {
                    decodeAddress(key)?.let { addr ->
                        publicKeys[addr] = IdentityKey(Base64.decode(value, Base64.DEFAULT), 0)
                    }
                }
            }
            val preJson = json.optJSONObject("preKeys") ?: JSONObject()
            preJson.keys().forEach { key ->
                val value = preJson.optString(key, "")
                val id = key.toIntOrNull() ?: return@forEach
                if (value.isNotEmpty()) {
                    preKeys[id] = PreKeyRecord(Base64.decode(value, Base64.DEFAULT))
                }
            }
            val signedJson = json.optJSONObject("signedPreKeys") ?: JSONObject()
            signedJson.keys().forEach { key ->
                val value = signedJson.optString(key, "")
                val id = key.toIntOrNull() ?: return@forEach
                if (value.isNotEmpty()) {
                    signedPreKeys[id] = SignedPreKeyRecord(Base64.decode(value, Base64.DEFAULT))
                }
            }
            val kyberJson = json.optJSONObject("kyberPreKeys") ?: JSONObject()
            kyberJson.keys().forEach { key ->
                val value = kyberJson.optString(key, "")
                val id = key.toIntOrNull() ?: return@forEach
                if (value.isNotEmpty()) {
                    kyberPreKeys[id] = KyberPreKeyRecord(Base64.decode(value, Base64.DEFAULT))
                }
            }
            val sessionJson = json.optJSONObject("sessions") ?: JSONObject()
            sessionJson.keys().forEach { key ->
                val value = sessionJson.optString(key, "")
                if (value.isNotEmpty()) {
                    decodeAddress(key)?.let { addr ->
                        sessions[addr] = SessionRecord(Base64.decode(value, Base64.DEFAULT))
                    }
                }
            }
            val senderJson = json.optJSONObject("senderKeys") ?: JSONObject()
            senderJson.keys().forEach { key ->
                val value = senderJson.optString(key, "")
                if (value.isNotEmpty()) {
                    senderKeys[key] = Base64.decode(value, Base64.DEFAULT)
                }
            }
        } else {
            identityKeyPair = KeyHelper.generateIdentityKeyPair()
            registrationId = KeyHelper.generateRegistrationId(false)
            nextPreKeyId = 1
            nextSignedPreKeyId = 1
            nextKyberPreKeyId = 1
            persist()
        }
    }

    private fun persist() {
        val json = JSONObject()
        json.put("version", 1)
        json.put(
            "identityKeyPair",
            Base64.encodeToString(identityKeyPair.serialize(), Base64.NO_WRAP)
        )
        json.put("registrationId", registrationId)
        json.put("nextPreKeyId", nextPreKeyId)
        json.put("nextSignedPreKeyId", nextSignedPreKeyId)
        json.put("nextKyberPreKeyId", nextKyberPreKeyId)

        val pkJson = JSONObject()
        publicKeys.forEach { (addr, key) ->
            pkJson.put(encodeAddress(addr), Base64.encodeToString(key.serialize(), Base64.NO_WRAP))
        }
        json.put("publicKeys", pkJson)

        val preJson = JSONObject()
        preKeys.forEach { (id, record) ->
            preJson.put(id.toString(), Base64.encodeToString(record.serialize(), Base64.NO_WRAP))
        }
        json.put("preKeys", preJson)

        val signedJson = JSONObject()
        signedPreKeys.forEach { (id, record) ->
            signedJson.put(id.toString(), Base64.encodeToString(record.serialize(), Base64.NO_WRAP))
        }
        json.put("signedPreKeys", signedJson)

        val kyberJson = JSONObject()
        kyberPreKeys.forEach { (id, record) ->
            kyberJson.put(id.toString(), Base64.encodeToString(record.serialize(), Base64.NO_WRAP))
        }
        json.put("kyberPreKeys", kyberJson)

        val sessionJson = JSONObject()
        sessions.forEach { (addr, record) ->
            sessionJson.put(encodeAddress(addr), Base64.encodeToString(record.serialize(), Base64.NO_WRAP))
        }
        json.put("sessions", sessionJson)

        val senderJson = JSONObject()
        senderKeys.forEach { (key, value) ->
            senderJson.put(key, Base64.encodeToString(value, Base64.NO_WRAP))
        }
        json.put("senderKeys", senderJson)

        storageFile.writeText(json.toString())
    }

    override fun getIdentityKeyPair(): IdentityKeyPair = synchronized(lock) { identityKeyPair }

    override fun getLocalRegistrationId(): Int = synchronized(lock) { registrationId }

    override fun saveIdentity(address: SignalProtocolAddress, identityKey: IdentityKey): Boolean {
        synchronized(lock) {
            val old = publicKeys[address]
            publicKeys[address] = identityKey
            persist()
            if (old != null && old != identityKey) {
                onIdentityChanged?.invoke(address, old, identityKey)
                return true
            }
            return false
        }
    }

    override fun isTrustedIdentity(
        address: SignalProtocolAddress,
        identityKey: IdentityKey,
        direction: IdentityKeyStore.Direction
    ): Boolean {
        synchronized(lock) {
            val existing = publicKeys[address]
            return existing == null || existing == identityKey
        }
    }

    override fun getIdentity(address: SignalProtocolAddress): IdentityKey? =
        synchronized(lock) { publicKeys[address] }

    override fun loadPreKey(preKeyId: Int): PreKeyRecord =
        synchronized(lock) { preKeys[preKeyId] ?: throw IllegalStateException("missing prekey") }

    override fun storePreKey(preKeyId: Int, record: PreKeyRecord) {
        synchronized(lock) {
            preKeys[preKeyId] = record
            persist()
        }
    }

    override fun removePreKey(preKeyId: Int) {
        synchronized(lock) {
            preKeys.remove(preKeyId)
            persist()
        }
    }

    override fun loadSignedPreKey(signedPreKeyId: Int): SignedPreKeyRecord =
        synchronized(lock) { signedPreKeys[signedPreKeyId] ?: throw IllegalStateException("missing signed prekey") }

    override fun storeSignedPreKey(signedPreKeyId: Int, record: SignedPreKeyRecord) {
        synchronized(lock) {
            signedPreKeys[signedPreKeyId] = record
            persist()
        }
    }

    fun storeKyberPreKey(kyberPreKeyId: Int, record: KyberPreKeyRecord) {
        synchronized(lock) {
            kyberPreKeys[kyberPreKeyId] = record
            persist()
        }
    }

    override fun loadSession(address: SignalProtocolAddress): SessionRecord? =
        synchronized(lock) { sessions[address] }

    override fun storeSession(address: SignalProtocolAddress, record: SessionRecord) {
        synchronized(lock) {
            sessions[address] = record
            persist()
        }
    }

    override fun containsSession(address: SignalProtocolAddress): Boolean =
        synchronized(lock) { sessions.containsKey(address) }

    override fun deleteSession(address: SignalProtocolAddress) {
        synchronized(lock) {
            sessions.remove(address)
            persist()
        }
    }

    override fun deleteAllSessions(name: String) {
        synchronized(lock) {
            sessions.keys.filter { it.name == name }.forEach { sessions.remove(it) }
            persist()
        }
    }

    fun snapshot(): SignalStoreSnapshot {
        synchronized(lock) {
            return SignalStoreSnapshot(
                version = 1,
                identityKeyPair = Base64.encodeToString(identityKeyPair.serialize(), Base64.NO_WRAP),
                registrationId = registrationId,
                publicKeys = publicKeys.mapKeys { encodeAddress(it.key) }
                    .mapValues { Base64.encodeToString(it.value.serialize(), Base64.NO_WRAP) },
                preKeys = preKeys.mapKeys { it.key.toString() }
                    .mapValues { Base64.encodeToString(it.value.serialize(), Base64.NO_WRAP) },
                signedPreKeys = signedPreKeys.mapKeys { it.key.toString() }
                    .mapValues { Base64.encodeToString(it.value.serialize(), Base64.NO_WRAP) },
                kyberPreKeys = kyberPreKeys.mapKeys { it.key.toString() }
                    .mapValues { Base64.encodeToString(it.value.serialize(), Base64.NO_WRAP) },
                sessions = sessions.mapKeys { encodeAddress(it.key) }
                    .mapValues { Base64.encodeToString(it.value.serialize(), Base64.NO_WRAP) },
                senderKeys = senderKeys.mapValues { Base64.encodeToString(it.value, Base64.NO_WRAP) },
                nextPreKeyId = nextPreKeyId,
                nextSignedPreKeyId = nextSignedPreKeyId,
                nextKyberPreKeyId = nextKyberPreKeyId
            )
        }
    }

    fun replace(snapshot: SignalStoreSnapshot) {
        synchronized(lock) {
            identityKeyPair = IdentityKeyPair(Base64.decode(snapshot.identityKeyPair, Base64.DEFAULT))
            registrationId = snapshot.registrationId
            nextPreKeyId = snapshot.nextPreKeyId
            nextSignedPreKeyId = snapshot.nextSignedPreKeyId
            nextKyberPreKeyId = snapshot.nextKyberPreKeyId
            publicKeys.clear()
            snapshot.publicKeys.forEach { (key, value) ->
                decodeAddress(key)?.let { addr ->
                    publicKeys[addr] = IdentityKey(Base64.decode(value, Base64.DEFAULT), 0)
                }
            }
            preKeys.clear()
            snapshot.preKeys.forEach { (key, value) ->
                preKeys[key.toInt()] = PreKeyRecord(Base64.decode(value, Base64.DEFAULT))
            }
            signedPreKeys.clear()
            snapshot.signedPreKeys.forEach { (key, value) ->
                signedPreKeys[key.toInt()] = SignedPreKeyRecord(Base64.decode(value, Base64.DEFAULT))
            }
            kyberPreKeys.clear()
            snapshot.kyberPreKeys.forEach { (key, value) ->
                kyberPreKeys[key.toInt()] = KyberPreKeyRecord(Base64.decode(value, Base64.DEFAULT))
            }
            sessions.clear()
            snapshot.sessions.forEach { (key, value) ->
                decodeAddress(key)?.let { addr ->
                    sessions[addr] = SessionRecord(Base64.decode(value, Base64.DEFAULT))
                }
            }
            senderKeys.clear()
            snapshot.senderKeys.forEach { (key, value) ->
                senderKeys[key] = Base64.decode(value, Base64.DEFAULT)
            }
            persist()
        }
    }

    private fun encodeAddress(address: SignalProtocolAddress): String =
        "${address.name}:${address.deviceId}"

    private fun decodeAddress(value: String): SignalProtocolAddress? {
        val idx = value.lastIndexOf(':')
        if (idx <= 0) return null
        val name = value.substring(0, idx)
        val deviceId = value.substring(idx + 1).toIntOrNull() ?: return null
        return SignalProtocolAddress(name, deviceId)
    }
}

class SignalProtocolBridge(
    private val context: Context,
    private val methodChannel: MethodChannel,
    private val eventChannel: EventChannel
) : EventChannel.StreamHandler {
    private var eventSink: EventChannel.EventSink? = null
    private var currentUserId: Int? = null
    private var currentDeviceId: Int = 1
    private val stores: MutableMap<String, PersistentSignalProtocolStore> = mutableMapOf()

    fun register() {
        methodChannel.setMethodCallHandler { call, result ->
            val args = call.arguments as? Map<*, *>
            when (call.method) {
                "initUser" -> {
                    val userId = (args?.get("userId") as? Int) ?: run {
                        result.error("bad_args", null, null)
                        return@setMethodCallHandler
                    }
                    val deviceId = (args["deviceId"] as? Int) ?: 1
                    currentUserId = userId
                    currentDeviceId = deviceId
                    val bundle = initUser(userId, deviceId)
                    result.success(bundle)
                }
                "hasSession" -> {
                    val peerId = (args?.get("peerUserId") as? Int) ?: run {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val store = currentStore() ?: run {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val address = SignalProtocolAddress(peerId.toString(), currentDeviceId)
                    result.success(store.containsSession(address))
                }
                "encrypt" -> {
                    val peerId = (args?.get("peerUserId") as? Int) ?: run {
                        result.error("bad_args", null, null)
                        return@setMethodCallHandler
                    }
                    val plaintext = args?.get("plaintext") as? String ?: ""
                    val preKeyBundle = args?.get("preKeyBundle") as? Map<*, *>
                    try {
                        val out = encrypt(peerId, plaintext, preKeyBundle)
                        result.success(out)
                    } catch (e: Exception) {
                        result.error("encrypt_failed", e.message, null)
                    }
                }
                "decrypt" -> {
                    val peerId = (args?.get("peerUserId") as? Int) ?: run {
                        result.error("bad_args", null, null)
                        return@setMethodCallHandler
                    }
                    val ciphertext = args?.get("ciphertext") as? String ?: ""
                    try {
                        val out = decrypt(peerId, ciphertext)
                        result.success(out)
                    } catch (e: Exception) {
                        result.error("decrypt_failed", e.message, null)
                    }
                }
                "resetSession" -> {
                    val peerId = (args?.get("peerUserId") as? Int) ?: run {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    val store = currentStore()
                    if (store != null) {
                        store.deleteSession(SignalProtocolAddress(peerId.toString(), currentDeviceId))
                    }
                    result.success(null)
                }
                "getFingerprint" -> {
                    // Placeholder: Android fingerprint support can be added later
                    result.success("")
                }
                "exportBackup" -> {
                    val userId = (args?.get("userId") as? Int) ?: run {
                        result.success("")
                        return@setMethodCallHandler
                    }
                    val secret = args["backupSecretBase64"] as? String ?: ""
                    val store = storeFor(userId, currentDeviceId)
                    val snapshot = store.snapshot()
                    val json = JSONObject()
                    json.put("version", snapshot.version)
                    json.put("identityKeyPair", snapshot.identityKeyPair)
                    json.put("registrationId", snapshot.registrationId)
                    json.put("publicKeys", JSONObject(snapshot.publicKeys))
                    json.put("preKeys", JSONObject(snapshot.preKeys))
                    json.put("signedPreKeys", JSONObject(snapshot.signedPreKeys))
                    json.put("kyberPreKeys", JSONObject(snapshot.kyberPreKeys))
                    json.put("sessions", JSONObject(snapshot.sessions))
                    json.put("senderKeys", JSONObject(snapshot.senderKeys))
                    json.put("nextPreKeyId", snapshot.nextPreKeyId)
                    json.put("nextSignedPreKeyId", snapshot.nextSignedPreKeyId)
                    json.put("nextKyberPreKeyId", snapshot.nextKyberPreKeyId)
                    val encrypted = encryptBackup(json.toString().toByteArray(), secret)
                    result.success(encrypted)
                }
                "importBackup" -> {
                    val userId = (args?.get("userId") as? Int) ?: run {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val secret = args["backupSecretBase64"] as? String ?: ""
                    val payload = args["encryptedPayload"] as? String ?: ""
                    try {
                        val raw = decryptBackup(payload, secret)
                        val json = JSONObject(String(raw))
                        val snapshot = SignalStoreSnapshot(
                            version = json.optInt("version", 1),
                            identityKeyPair = json.getString("identityKeyPair"),
                            registrationId = json.getInt("registrationId"),
                            publicKeys = json.optJSONObject("publicKeys")?.toMapString()
                                ?: emptyMap(),
                            preKeys = json.optJSONObject("preKeys")?.toMapString()
                                ?: emptyMap(),
                            signedPreKeys = json.optJSONObject("signedPreKeys")?.toMapString()
                                ?: emptyMap(),
                            kyberPreKeys = json.optJSONObject("kyberPreKeys")?.toMapString()
                                ?: emptyMap(),
                            sessions = json.optJSONObject("sessions")?.toMapString()
                                ?: emptyMap(),
                            senderKeys = json.optJSONObject("senderKeys")?.toMapString()
                                ?: emptyMap(),
                            nextPreKeyId = json.optInt("nextPreKeyId", 1),
                            nextSignedPreKeyId = json.optInt("nextSignedPreKeyId", 1),
                            nextKyberPreKeyId = json.optInt("nextKyberPreKeyId", 1)
                        )
                        storeFor(userId, currentDeviceId).replace(snapshot)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
        eventChannel.setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun currentStore(): PersistentSignalProtocolStore? {
        val userId = currentUserId ?: return null
        return storeFor(userId, currentDeviceId)
    }

    private fun storeFor(userId: Int, deviceId: Int): PersistentSignalProtocolStore {
        val key = "$userId:$deviceId"
        return stores.getOrPut(key) {
            val dir = File(context.filesDir, "signal_store")
            if (!dir.exists()) dir.mkdirs()
            val file = File(dir, "signal_store_${userId}_$deviceId.json")
            PersistentSignalProtocolStore(file)
        }
    }

    private fun initUser(userId: Int, deviceId: Int): Map<String, Any?> {
        val store = storeFor(userId, deviceId)
        store.onIdentityChanged = { address, old, new ->
            val event = mapOf(
                "type" to "identity_changed",
                "peer_user_id" to address.name.toIntOrNull(),
                "previous_fingerprint" to old?.serialize()?.let { Base64.encodeToString(it, Base64.NO_WRAP) },
                "current_fingerprint" to new?.serialize()?.let { Base64.encodeToString(it, Base64.NO_WRAP) }
            )
            eventSink?.success(event)
        }

        if (store.signedPreKeyRecords.isEmpty()) {
            val signedId = store.nextSignedPreKeyId
            val signedPreKey = KeyHelper.generateSignedPreKey(store.identityKeyPairValue, signedId)
            store.storeSignedPreKey(signedId, signedPreKey)
            store.nextSignedPreKeyId = signedId + 1
        }
        if (store.kyberPreKeyRecords.isEmpty()) {
            val kyberId = store.nextKyberPreKeyId
            val kemKeyPair = KEMKeyPair.generate()
            val signature = Curve.calculateSignature(
                store.identityKeyPairValue.privateKey,
                kemKeyPair.publicKey.serialize()
            )
            val record = KyberPreKeyRecord(kyberId, System.currentTimeMillis(), kemKeyPair, signature)
            store.storeKyberPreKey(kyberId, record)
            store.nextKyberPreKeyId = kyberId + 1
        }
        val target = 50
        while (store.preKeyRecords.size < target) {
            val id = store.nextPreKeyId
            val record = KeyHelper.generatePreKeys(id, 1).first()
            store.storePreKey(id, record)
            store.nextPreKeyId = id + 1
        }

        val signedRecord = store.signedPreKeyRecords.values.first()
        val kyberRecord = store.kyberPreKeyRecords.values.first()
        val oneTimeKeys = JSONArray()
        store.preKeyRecords.forEach { (id, record) ->
            val keyB64 = Base64.encodeToString(record.keyPair.publicKey.serialize(), Base64.NO_WRAP)
            val obj = JSONObject()
            obj.put("id", id)
            obj.put("key", keyB64)
            oneTimeKeys.put(obj)
        }

        val identityKey = store.identityKeyPairValue.publicKey.serialize()
        return mapOf(
            "public_key" to Base64.encodeToString(identityKey, Base64.NO_WRAP),
            "identity_key" to Base64.encodeToString(identityKey, Base64.NO_WRAP),
            "signature" to "",
            "key_version" to 1,
            "signed_at" to java.time.Instant.now().toString(),
            "registration_id" to store.localRegistrationIdValue,
            "signed_pre_key_id" to signedRecord.id,
            "signed_pre_key" to Base64.encodeToString(
                signedRecord.keyPair.publicKey.serialize(),
                Base64.NO_WRAP
            ),
            "signed_pre_key_signature" to Base64.encodeToString(
                signedRecord.signature,
                Base64.NO_WRAP
            ),
            "kyber_pre_key_id" to kyberRecord.id,
            "kyber_pre_key" to Base64.encodeToString(
                kyberRecord.publicKey.serialize(),
                Base64.NO_WRAP
            ),
            "kyber_pre_key_signature" to Base64.encodeToString(
                kyberRecord.signature,
                Base64.NO_WRAP
            ),
            "one_time_pre_keys" to oneTimeKeys.toList()
        )
    }

    private fun encrypt(peerUserId: Int, plaintext: String, bundle: Map<*, *>?): String {
        val store = currentStore() ?: throw IllegalStateException("not initialized")
        val address = SignalProtocolAddress(peerUserId.toString(), currentDeviceId)
        if (bundle != null) {
            val preKeyBundle = buildPreKeyBundle(bundle)
            SessionBuilder(store, address).process(preKeyBundle)
        }
        val cipher = SessionCipher(store, address)
        val message = cipher.encrypt(plaintext.toByteArray())
        return Base64.encodeToString(message.serialize(), Base64.NO_WRAP)
    }

    private fun decrypt(peerUserId: Int, ciphertext: String): String {
        val store = currentStore() ?: throw IllegalStateException("not initialized")
        val address = SignalProtocolAddress(peerUserId.toString(), currentDeviceId)
        val raw = Base64.decode(ciphertext, Base64.DEFAULT)
        val cipher = SessionCipher(store, address)
        return try {
            val msg = PreKeySignalMessage(raw)
            String(cipher.decrypt(msg))
        } catch (e: Exception) {
            val msg = SignalMessage(raw)
            String(cipher.decrypt(msg))
        }
    }

    private fun buildPreKeyBundle(bundle: Map<*, *>): org.signal.libsignal.protocol.state.PreKeyBundle {
        val registrationId = (bundle["registration_id"] as? Int) ?: 1
        val signedPreKeyId = (bundle["signed_pre_key_id"] as? Int) ?: 1
        val signedPreKeyB64 = bundle["signed_pre_key"] as? String ?: ""
        val signedPreKeySigB64 = bundle["signed_pre_key_signature"] as? String ?: ""
        val kyberPreKeyId = (bundle["kyber_pre_key_id"] as? Int) ?: 1
        val kyberPreKeyB64 = bundle["kyber_pre_key"] as? String ?: ""
        val kyberPreKeySigB64 = bundle["kyber_pre_key_signature"] as? String ?: ""
        val identityKeyB64 = (bundle["identity_key"] as? String)
            ?: (bundle["public_key"] as? String) ?: ""

        val preKeyJson = bundle["one_time_pre_keys"] as? List<*>
        val preKeyEntry = preKeyJson?.firstOrNull() as? Map<*, *>
        val preKeyId = preKeyEntry?.get("id") as? Int
        val preKeyB64 = preKeyEntry?.get("key") as? String

        val identityKey = IdentityKey(Base64.decode(identityKeyB64, Base64.DEFAULT), 0)
        val signedPreKey = org.signal.libsignal.protocol.ecc.Curve.decodePoint(
            Base64.decode(signedPreKeyB64, Base64.DEFAULT), 0
        )
        val signedPreKeySig = Base64.decode(signedPreKeySigB64, Base64.DEFAULT)
        val kyberPreKey = KEMPublicKey(Base64.decode(kyberPreKeyB64, Base64.DEFAULT))
        val kyberPreKeySig = Base64.decode(kyberPreKeySigB64, Base64.DEFAULT)

        return if (preKeyId != null && !preKeyB64.isNullOrEmpty()) {
            val preKey = org.signal.libsignal.protocol.ecc.Curve.decodePoint(
                Base64.decode(preKeyB64, Base64.DEFAULT), 0
            )
            org.signal.libsignal.protocol.state.PreKeyBundle(
                registrationId,
                currentDeviceId,
                preKeyId,
                preKey,
                signedPreKeyId,
                signedPreKey,
                signedPreKeySig,
                identityKey,
                kyberPreKeyId,
                kyberPreKey,
                kyberPreKeySig
            )
        } else {
            org.signal.libsignal.protocol.state.PreKeyBundle(
                registrationId,
                currentDeviceId,
                signedPreKeyId,
                signedPreKey,
                signedPreKeySig,
                identityKey,
                kyberPreKeyId,
                kyberPreKey,
                kyberPreKeySig
            )
        }
    }

    private fun encryptBackup(payload: ByteArray, secretBase64: String): String {
        val keyBytes = Base64.decode(secretBase64, Base64.DEFAULT)
        val key = SecretKeySpec(keyBytes, "AES")
        val nonce = ByteArray(12)
        SecureRandom().nextBytes(nonce)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(128, nonce))
        val encrypted = cipher.doFinal(payload)
        val combined = ByteArray(nonce.size + encrypted.size)
        System.arraycopy(nonce, 0, combined, 0, nonce.size)
        System.arraycopy(encrypted, 0, combined, nonce.size, encrypted.size)
        val json = JSONObject()
        json.put("v", 1)
        json.put("alg", "A256GCM")
        json.put("payload", Base64.encodeToString(combined, Base64.NO_WRAP))
        return json.toString()
    }

    private fun decryptBackup(payload: String, secretBase64: String): ByteArray {
        val keyBytes = Base64.decode(secretBase64, Base64.DEFAULT)
        val key = SecretKeySpec(keyBytes, "AES")
        val json = JSONObject(payload)
        val blob = json.getString("payload")
        val combined = Base64.decode(blob, Base64.DEFAULT)
        val nonce = combined.copyOfRange(0, 12)
        val cipherBytes = combined.copyOfRange(12, combined.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, nonce))
        return cipher.doFinal(cipherBytes)
    }
}

private fun JSONObject.toMapString(): Map<String, String> {
    val map = mutableMapOf<String, String>()
    keys().forEach { key ->
        map[key] = optString(key, "")
    }
    return map
}

private fun JSONArray.toList(): List<Map<String, Any>> {
    val out = mutableListOf<Map<String, Any>>()
    for (i in 0 until length()) {
        val item = optJSONObject(i) ?: continue
        val map = mutableMapOf<String, Any>()
        item.keys().forEach { key ->
            map[key] = item.get(key)
        }
        out.add(map)
    }
    return out
}
