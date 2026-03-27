import CryptoKit
import Flutter
import Foundation
import LibSignalClient

private struct SignalStoreSnapshot: Codable {
  let version: Int
  var identityKeyPair: String
  var registrationId: UInt32
  var publicKeys: [String: String]
  var preKeys: [String: String]
  var signedPreKeys: [String: String]
  var kyberPreKeys: [String: String]
  var sessions: [String: String]
  var senderKeys: [String: String]
  var kyberPrekeysUsed: [UInt32]
  var baseKeysSeen: [String: [String]]
  var nextPreKeyId: UInt32
  var nextSignedPreKeyId: UInt32
  var nextKyberPreKeyId: UInt32
}

private final class PersistentSignalProtocolStore: IdentityKeyStore, PreKeyStore, SignedPreKeyStore, KyberPreKeyStore,
  SessionStore, SenderKeyStore
{
  private struct SenderKeyName: Hashable {
    var sender: ProtocolAddress
    var distributionId: UUID
  }

  private let lock = NSLock()
  private let storageURL: URL

  private var publicKeys: [ProtocolAddress: IdentityKey] = [:]
  private var identityKeyPair: IdentityKeyPair
  private var registrationId: UInt32
  private var prekeyMap: [UInt32: PreKeyRecord] = [:]
  private var signedPrekeyMap: [UInt32: SignedPreKeyRecord] = [:]
  private var kyberPrekeyMap: [UInt32: KyberPreKeyRecord] = [:]
  private var kyberPrekeysUsed: Set<UInt32> = []
  private var baseKeysSeen: [UInt64: [PublicKey]] = [:]
  private var sessionMap: [ProtocolAddress: SessionRecord] = [:]
  private var senderKeyMap: [SenderKeyName: SenderKeyRecord] = [:]

  var nextPreKeyId: UInt32
  var nextSignedPreKeyId: UInt32
  var nextKyberPreKeyId: UInt32

  var onIdentityChanged: ((ProtocolAddress, IdentityKey?, IdentityKey?) -> Void)?

  init(storageURL: URL) throws {
    self.storageURL = storageURL
    if let data = try? Data(contentsOf: storageURL),
       let snapshot = try? JSONDecoder().decode(SignalStoreSnapshot.self, from: data)
    {
      let identityBytes = Data(base64Encoded: snapshot.identityKeyPair) ?? Data()
      self.identityKeyPair = try IdentityKeyPair(bytes: identityBytes)
      self.registrationId = snapshot.registrationId
      self.nextPreKeyId = snapshot.nextPreKeyId
      self.nextSignedPreKeyId = snapshot.nextSignedPreKeyId
      self.nextKyberPreKeyId = snapshot.nextKyberPreKeyId

      for (key, value) in snapshot.publicKeys {
        if let addr = Self.decodeAddress(key), let data = Data(base64Encoded: value) {
          if let identity = try? IdentityKey(bytes: data) {
            self.publicKeys[addr] = identity
          }
        }
      }
      for (key, value) in snapshot.preKeys {
        if let id = UInt32(key), let data = Data(base64Encoded: value),
           let record = try? PreKeyRecord(bytes: data)
        {
          self.prekeyMap[id] = record
        }
      }
      for (key, value) in snapshot.signedPreKeys {
        if let id = UInt32(key), let data = Data(base64Encoded: value),
           let record = try? SignedPreKeyRecord(bytes: data)
        {
          self.signedPrekeyMap[id] = record
        }
      }
      for (key, value) in snapshot.kyberPreKeys {
        if let id = UInt32(key), let data = Data(base64Encoded: value),
           let record = try? KyberPreKeyRecord(bytes: data)
        {
          self.kyberPrekeyMap[id] = record
        }
      }
      for (key, value) in snapshot.sessions {
        if let addr = Self.decodeAddress(key), let data = Data(base64Encoded: value),
           let record = try? SessionRecord(bytes: data)
        {
          self.sessionMap[addr] = record
        }
      }
      for (key, value) in snapshot.senderKeys {
        if let (addr, distributionId) = Self.decodeSenderKeyName(key),
           let data = Data(base64Encoded: value),
           let record = try? SenderKeyRecord(bytes: data)
        {
          self.senderKeyMap[SenderKeyName(sender: addr, distributionId: distributionId)] = record
        }
      }
      self.kyberPrekeysUsed = Set(snapshot.kyberPrekeysUsed)
      for (key, value) in snapshot.baseKeysSeen {
        guard let bothId = UInt64(key) else { continue }
        var keys: [PublicKey] = []
        for item in value {
          if let data = Data(base64Encoded: item),
             let pk = try? PublicKey(data)
          {
            keys.append(pk)
          }
        }
        self.baseKeysSeen[bothId] = keys
      }
    } else {
      self.identityKeyPair = IdentityKeyPair.generate()
      self.registrationId = UInt32.random(in: 1...0x3FFF)
      self.nextPreKeyId = 1
      self.nextSignedPreKeyId = 1
      self.nextKyberPreKeyId = 1
      try persist()
    }
  }

  func snapshot() throws -> SignalStoreSnapshot {
    let publicKeys = self.publicKeys.reduce(into: [String: String]()) { acc, kv in
      acc[Self.encodeAddress(kv.key)] = kv.value.serialize().base64EncodedString()
    }
    let preKeys = self.prekeyMap.reduce(into: [String: String]()) { acc, kv in
      acc[String(kv.key)] = kv.value.serialize().base64EncodedString()
    }
    let signedPreKeys = self.signedPrekeyMap.reduce(into: [String: String]()) { acc, kv in
      acc[String(kv.key)] = kv.value.serialize().base64EncodedString()
    }
    let kyberPreKeys = self.kyberPrekeyMap.reduce(into: [String: String]()) { acc, kv in
      acc[String(kv.key)] = kv.value.serialize().base64EncodedString()
    }
    let sessions = self.sessionMap.reduce(into: [String: String]()) { acc, kv in
      acc[Self.encodeAddress(kv.key)] = kv.value.serialize().base64EncodedString()
    }
    let senderKeys = self.senderKeyMap.reduce(into: [String: String]()) { acc, kv in
      acc[Self.encodeSenderKeyName(kv.key)] = kv.value.serialize().base64EncodedString()
    }
    let baseKeysSeen = self.baseKeysSeen.reduce(into: [String: [String]]()) { acc, kv in
      acc[String(kv.key)] = kv.value.map { $0.serialize().base64EncodedString() }
    }
    return SignalStoreSnapshot(
      version: 1,
      identityKeyPair: identityKeyPair.serialize().base64EncodedString(),
      registrationId: registrationId,
      publicKeys: publicKeys,
      preKeys: preKeys,
      signedPreKeys: signedPreKeys,
      kyberPreKeys: kyberPreKeys,
      sessions: sessions,
      senderKeys: senderKeys,
      kyberPrekeysUsed: Array(kyberPrekeysUsed),
      baseKeysSeen: baseKeysSeen,
      nextPreKeyId: nextPreKeyId,
      nextSignedPreKeyId: nextSignedPreKeyId,
      nextKyberPreKeyId: nextKyberPreKeyId
    )
  }

  func persist() throws {
    let snap = try snapshot()
    let data = try JSONEncoder().encode(snap)
    try data.write(to: storageURL, options: [.atomic])
  }

  func replace(with snapshot: SignalStoreSnapshot) throws {
    let data = try JSONEncoder().encode(snapshot)
    try data.write(to: storageURL, options: [.atomic])
    let reloaded = try PersistentSignalProtocolStore(storageURL: storageURL)
    copyFrom(reloaded)
  }

  private func copyFrom(_ other: PersistentSignalProtocolStore) {
    self.publicKeys = other.publicKeys
    self.identityKeyPair = other.identityKeyPair
    self.registrationId = other.registrationId
    self.prekeyMap = other.prekeyMap
    self.signedPrekeyMap = other.signedPrekeyMap
    self.kyberPrekeyMap = other.kyberPrekeyMap
    self.kyberPrekeysUsed = other.kyberPrekeysUsed
    self.baseKeysSeen = other.baseKeysSeen
    self.sessionMap = other.sessionMap
    self.senderKeyMap = other.senderKeyMap
    self.nextPreKeyId = other.nextPreKeyId
    self.nextSignedPreKeyId = other.nextSignedPreKeyId
    self.nextKyberPreKeyId = other.nextKyberPreKeyId
  }

  static func encodeAddress(_ address: ProtocolAddress) -> String {
    return "\(address.name):\(address.deviceId)"
  }

  static func decodeAddress(_ value: String) -> ProtocolAddress? {
    guard let idx = value.lastIndex(of: ":") else { return nil }
    let name = String(value[..<idx])
    let deviceStr = String(value[value.index(after: idx)...])
    guard let deviceId = UInt32(deviceStr) else { return nil }
    return try? ProtocolAddress(name: name, deviceId: deviceId)
  }

  private static func encodeSenderKeyName(_ name: SenderKeyName) -> String {
    return "\(encodeAddress(name.sender))|\(name.distributionId.uuidString)"
  }

  private static func decodeSenderKeyName(_ value: String) -> (ProtocolAddress, UUID)? {
    guard let idx = value.lastIndex(of: "|") else { return nil }
    let addrStr = String(value[..<idx])
    let uuidStr = String(value[value.index(after: idx)...])
    guard let addr = decodeAddress(addrStr), let uuid = UUID(uuidString: uuidStr) else { return nil }
    return (addr, uuid)
  }

  func identityKeyPair(context: StoreContext) throws -> IdentityKeyPair {
    lock.lock()
    defer { lock.unlock() }
    return identityKeyPair
  }

  func localRegistrationId(context: StoreContext) throws -> UInt32 {
    lock.lock()
    defer { lock.unlock() }
    return registrationId
  }

  func saveIdentity(_ identity: IdentityKey, for address: ProtocolAddress, context: StoreContext) throws -> IdentityChange {
    lock.lock()
    defer { lock.unlock() }
    let oldIdentity = publicKeys.updateValue(identity, forKey: address)
    try persist()
    if let old = oldIdentity, old != identity {
      onIdentityChanged?(address, old, identity)
      return .replacedExisting
    }
    return .newOrUnchanged
  }

  func isTrustedIdentity(
    _ identity: IdentityKey,
    for address: ProtocolAddress,
    direction: Direction,
    context: StoreContext
  ) throws -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if let pk = publicKeys[address] {
      return pk == identity
    }
    return true
  }

  func identity(for address: ProtocolAddress, context: StoreContext) throws -> IdentityKey? {
    lock.lock()
    defer { lock.unlock() }
    return publicKeys[address]
  }

  func loadPreKey(id: UInt32, context: StoreContext) throws -> PreKeyRecord {
    lock.lock()
    defer { lock.unlock() }
    if let record = prekeyMap[id] {
      return record
    }
    throw SignalError.invalidKeyIdentifier("no prekey with this identifier")
  }

  func storePreKey(_ record: PreKeyRecord, id: UInt32, context: StoreContext) throws {
    lock.lock()
    prekeyMap[id] = record
    lock.unlock()
    try persist()
  }

  func removePreKey(id: UInt32, context: StoreContext) throws {
    lock.lock()
    prekeyMap.removeValue(forKey: id)
    lock.unlock()
    try persist()
  }

  func loadSignedPreKey(id: UInt32, context: StoreContext) throws -> SignedPreKeyRecord {
    lock.lock()
    defer { lock.unlock() }
    if let record = signedPrekeyMap[id] {
      return record
    }
    throw SignalError.invalidKeyIdentifier("no signed prekey with this identifier")
  }

  func storeSignedPreKey(_ record: SignedPreKeyRecord, id: UInt32, context: StoreContext) throws {
    lock.lock()
    signedPrekeyMap[id] = record
    lock.unlock()
    try persist()
  }

  func loadKyberPreKey(id: UInt32, context: StoreContext) throws -> KyberPreKeyRecord {
    lock.lock()
    defer { lock.unlock() }
    if let record = kyberPrekeyMap[id] {
      return record
    }
    throw SignalError.invalidKeyIdentifier("no kyber prekey with this identifier")
  }

  func storeKyberPreKey(_ record: KyberPreKeyRecord, id: UInt32, context: StoreContext) throws {
    lock.lock()
    kyberPrekeyMap[id] = record
    lock.unlock()
    try persist()
  }

  func markKyberPreKeyUsed(
    id: UInt32,
    signedPreKeyId: UInt32,
    baseKey: PublicKey,
    context: StoreContext
  ) throws {
    lock.lock()
    let bothKeyIds = (UInt64(id) << 32) | UInt64(signedPreKeyId)
    if baseKeysSeen[bothKeyIds, default: []].contains(baseKey) {
      lock.unlock()
      throw SignalError.invalidMessage("reused base key")
    }
    baseKeysSeen[bothKeyIds, default: []].append(baseKey)
    kyberPrekeysUsed.insert(id)
    lock.unlock()
    try persist()
  }

  func loadSession(for address: ProtocolAddress, context: StoreContext) throws -> SessionRecord? {
    lock.lock()
    defer { lock.unlock() }
    return sessionMap[address]
  }

  func loadExistingSessions(for addresses: [ProtocolAddress], context: StoreContext) throws -> [SessionRecord] {
    lock.lock()
    defer { lock.unlock() }
    return try addresses.map { address in
      if let session = sessionMap[address] {
        return session
      }
      throw SignalError.sessionNotFound("\(address)")
    }
  }

  func storeSession(_ record: SessionRecord, for address: ProtocolAddress, context: StoreContext) throws {
    lock.lock()
    sessionMap[address] = record
    lock.unlock()
    try persist()
  }

  func storeSenderKey(
    from sender: ProtocolAddress,
    distributionId: UUID,
    record: SenderKeyRecord,
    context: StoreContext
  ) throws {
    lock.lock()
    senderKeyMap[SenderKeyName(sender: sender, distributionId: distributionId)] = record
    lock.unlock()
    try persist()
  }

  func loadSenderKey(
    from sender: ProtocolAddress,
    distributionId: UUID,
    context: StoreContext
  ) throws -> SenderKeyRecord? {
    lock.lock()
    defer { lock.unlock() }
    return senderKeyMap[SenderKeyName(sender: sender, distributionId: distributionId)]
  }
}

private final class SignalStoreManager {
  static let shared = SignalStoreManager()
  private var stores: [String: PersistentSignalProtocolStore] = [:]

  private func key(userId: Int, deviceId: UInt32) -> String {
    return "\(userId):\(deviceId)"
  }

  func store(userId: Int, deviceId: UInt32) throws -> PersistentSignalProtocolStore {
    let storeKey = key(userId: userId, deviceId: deviceId)
    if let existing = stores[storeKey] {
      return existing
    }
    let url = try storageURL(for: userId, deviceId: deviceId)
    let store = try PersistentSignalProtocolStore(storageURL: url)
    stores[storeKey] = store
    return store
  }

  func storageURL(for userId: Int, deviceId: UInt32) throws -> URL {
    let base = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let dir = base.appendingPathComponent("signal_store", isDirectory: true)
    if !FileManager.default.fileExists(atPath: dir.path) {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    return dir.appendingPathComponent("signal_store_\(userId)_\(deviceId).json")
  }
}

final class SignalProtocolBridge: NSObject, FlutterStreamHandler {
  private let methodChannel = "ren/signal_protocol"
  private let eventChannel = "ren/signal_protocol/events"

  private var eventSink: FlutterEventSink?
  private let storeManager = SignalStoreManager.shared
  private var currentUserId: Int?
  private var currentDeviceId: UInt32 = 1

  func register(with controller: FlutterViewController) {
    let method = FlutterMethodChannel(name: methodChannel, binaryMessenger: controller.binaryMessenger)
    method.setMethodCallHandler(handleMethodCall)
    let events = FlutterEventChannel(name: eventChannel, binaryMessenger: controller.binaryMessenger)
    events.setStreamHandler(self)
  }

  func onListen(withArguments _: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments _: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func emitIdentityChanged(peerUserId: Int, previous: IdentityKey?, current: IdentityKey?) {
    guard let eventSink = eventSink else { return }
    let prev = previous?.serialize().base64EncodedString()
    let curr = current?.serialize().base64EncodedString()
    eventSink([
      "type": "identity_changed",
      "peer_user_id": peerUserId,
      "previous_fingerprint": prev,
      "current_fingerprint": curr,
    ])
  }

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "bad_args", message: nil, details: nil))
      return
    }
    switch call.method {
    case "initUser":
      guard let userId = args["userId"] as? Int else {
        result(FlutterError(code: "bad_user_id", message: nil, details: nil))
        return
      }
      let deviceId = (args["deviceId"] as? Int) ?? 1
      currentUserId = userId
      currentDeviceId = UInt32(deviceId)
      do {
        let bundle = try initUser(userId: userId, deviceId: UInt32(deviceId))
        result(bundle)
      } catch {
        result(FlutterError(code: "init_failed", message: "\(error)", details: nil))
      }
    case "hasSession":
      guard let peerId = args["peerUserId"] as? Int else {
        result(false)
        return
      }
      do {
        guard let localUserId = currentUserId else {
          result(false)
          return
        }
        let store = try storeManager.store(userId: localUserId, deviceId: currentDeviceId)
        let address = try ProtocolAddress(name: "\(peerId)", deviceId: currentDeviceId)
        let session = try store.loadSession(for: address, context: NullContext())
        result(session != nil)
      } catch {
        result(false)
      }
    case "encrypt":
      guard let peerId = args["peerUserId"] as? Int,
            let plaintext = args["plaintext"] as? String
      else {
        result(FlutterError(code: "bad_args", message: nil, details: nil))
        return
      }
      let preKeyBundle = args["preKeyBundle"] as? [String: Any]
      do {
        guard let _ = currentUserId else {
          result(FlutterError(code: "not_initialized", message: nil, details: nil))
          return
        }
        let cipher = try encrypt(
          peerUserId: peerId,
          deviceId: currentDeviceId,
          plaintext: plaintext,
          preKeyBundle: preKeyBundle
        )
        result(cipher)
      } catch {
        result(FlutterError(code: "encrypt_failed", message: "\(error)", details: nil))
      }
    case "decrypt":
      guard let peerId = args["peerUserId"] as? Int,
            let ciphertext = args["ciphertext"] as? String
      else {
        result(FlutterError(code: "bad_args", message: nil, details: nil))
        return
      }
      do {
        guard let _ = currentUserId else {
          result(FlutterError(code: "not_initialized", message: nil, details: nil))
          return
        }
        let plain = try decrypt(peerUserId: peerId, deviceId: currentDeviceId, ciphertext: ciphertext)
        result(plain)
      } catch {
        result(FlutterError(code: "decrypt_failed", message: "\(error)", details: nil))
      }
    case "resetSession":
      guard let peerId = args["peerUserId"] as? Int else {
        result(nil)
        return
      }
      do {
        guard let localUserId = currentUserId else {
          result(nil)
          return
        }
        let store = try storeManager.store(userId: localUserId, deviceId: currentDeviceId)
        let address = try ProtocolAddress(name: "\(peerId)", deviceId: currentDeviceId)
        _ = try store.loadSession(for: address, context: NullContext())
        store.removeSession(for: address)
        result(nil)
      } catch {
        result(nil)
      }
    case "getFingerprint":
      guard let peerId = args["peerUserId"] as? Int else {
        result("")
        return
      }
      do {
        guard let localUserId = currentUserId else {
          result("")
          return
        }
        let store = try storeManager.store(userId: localUserId, deviceId: currentDeviceId)
        let address = try ProtocolAddress(name: "\(peerId)", deviceId: currentDeviceId)
        guard let remoteIdentity = try store.identity(for: address, context: NullContext()) else {
          result("")
          return
        }
        let localIdentity = try store.identityKeyPair(context: NullContext()).publicKey
        let generator = NumericFingerprintGenerator(iterations: 5200)
        let fingerprint = try generator.create(
          version: 2,
          localIdentifier: Data("\(localUserId)".utf8),
          localKey: localIdentity,
          remoteIdentifier: Data("\(peerId)".utf8),
          remoteKey: remoteIdentity.publicKey
        )
        result(fingerprint.displayable.formatted)
      } catch {
        result("")
      }
    case "exportBackup":
      guard let userId = args["userId"] as? Int,
            let backupSecret = args["backupSecretBase64"] as? String
      else {
        result("")
        return
      }
      do {
        let store = try storeManager.store(userId: userId, deviceId: currentDeviceId)
        let snap = try store.snapshot()
        let raw = try JSONEncoder().encode(snap)
        let encrypted = try encryptBackup(payload: raw, backupSecretBase64: backupSecret)
        result(encrypted)
      } catch {
        result("")
      }
    case "importBackup":
      guard let userId = args["userId"] as? Int,
            let backupSecret = args["backupSecretBase64"] as? String,
            let encryptedPayload = args["encryptedPayload"] as? String
      else {
        result(false)
        return
      }
      do {
        let raw = try decryptBackup(payload: encryptedPayload, backupSecretBase64: backupSecret)
        let snapshot = try JSONDecoder().decode(SignalStoreSnapshot.self, from: raw)
        let store = try storeManager.store(userId: userId, deviceId: currentDeviceId)
        try store.replace(with: snapshot)
        result(true)
      } catch {
        result(false)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func initUser(userId: Int, deviceId: UInt32) throws -> [String: Any] {
    let store = try storeManager.store(userId: userId, deviceId: deviceId)
    store.onIdentityChanged = { [weak self] address, old, new in
      let peerId = Int(address.name) ?? 0
      self?.emitIdentityChanged(peerUserId: peerId, previous: old, current: new)
    }

    let context = NullContext()
    let identity = try store.identityKeyPair(context: context)
    let registrationId = try store.localRegistrationId(context: context)

    if store.signedPreKeys.isEmpty {
      let signedId = store.nextSignedPreKeyId
      let preKey = PrivateKey.generate()
      let signature = identity.privateKey.generateSignature(message: preKey.publicKey.serialize())
      let record = try SignedPreKeyRecord(
        id: signedId,
        timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
        privateKey: preKey,
        signature: signature
      )
      try store.storeSignedPreKey(record, id: signedId, context: context)
      store.nextSignedPreKeyId = signedId &+ 1
    }

    if store.kyberPreKeys.isEmpty {
      let kyberId = store.nextKyberPreKeyId
      let keyPair = KEMKeyPair.generate()
      let signature = identity.privateKey.generateSignature(message: keyPair.publicKey.serialize())
      let record = try KyberPreKeyRecord(
        id: kyberId,
        timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
        keyPair: keyPair,
        signature: signature
      )
      try store.storeKyberPreKey(record, id: kyberId, context: context)
      store.nextKyberPreKeyId = kyberId &+ 1
    }

    let targetPreKeys = 50
    while store.preKeys.count < targetPreKeys {
      let preKeyId = store.nextPreKeyId
      let privateKey = PrivateKey.generate()
      let record = try PreKeyRecord(id: preKeyId, privateKey: privateKey)
      try store.storePreKey(record, id: preKeyId, context: context)
      store.nextPreKeyId = preKeyId &+ 1
    }

    let signedRecord = store.signedPreKeys.values.first!
    let signedPreKey = try signedRecord.publicKey()
    let kyberRecord = store.kyberPreKeys.values.first!
    let kyberPreKey = try kyberRecord.publicKey()

    let oneTimeKeys = store.preKeys.map { id, record in
      let pub = try? record.publicKey().serialize().base64EncodedString()
      return [
        "id": Int(id),
        "key": pub ?? "",
      ]
    }

    try store.persist()

    return [
      "public_key": identity.publicKey.serialize().base64EncodedString(),
      "identity_key": identity.publicKey.serialize().base64EncodedString(),
      "signature": "",
      "key_version": 1,
      "signed_at": ISO8601DateFormatter().string(from: Date()),
      "registration_id": registrationId,
      "signed_pre_key_id": signedRecord.id,
      "signed_pre_key": signedPreKey.serialize().base64EncodedString(),
      "signed_pre_key_signature": signedRecord.signature.base64EncodedString(),
      "kyber_pre_key_id": kyberRecord.id,
      "kyber_pre_key": kyberPreKey.serialize().base64EncodedString(),
      "kyber_pre_key_signature": kyberRecord.signature.base64EncodedString(),
      "one_time_pre_keys": oneTimeKeys,
    ]
  }

  private func encrypt(
    peerUserId: Int,
    deviceId: UInt32,
    plaintext: String,
    preKeyBundle: [String: Any]?
  ) throws -> String {
    guard let localUserId = currentUserId else {
      throw SignalError.invalidState("not initialized")
    }
    let store = try storeManager.store(userId: localUserId, deviceId: deviceId)
    let address = try ProtocolAddress(name: "\(peerUserId)", deviceId: deviceId)
    let context = NullContext()

    if let bundle = preKeyBundle {
      let preKey = try buildPreKeyBundle(from: bundle, deviceId: deviceId)
      try processPreKeyBundle(preKey, for: address, sessionStore: store, identityStore: store, context: context)
    }

    let cipher = try signalEncrypt(
      message: Array(plaintext.utf8),
      for: address,
      sessionStore: store,
      identityStore: store,
      context: context
    )
    return cipher.serialize().base64EncodedString()
  }

  private func decrypt(peerUserId: Int, deviceId: UInt32, ciphertext: String) throws -> String {
    guard let localUserId = currentUserId else {
      throw SignalError.invalidState("not initialized")
    }
    let store = try storeManager.store(userId: localUserId, deviceId: deviceId)
    let address = try ProtocolAddress(name: "\(peerUserId)", deviceId: deviceId)
    let context = NullContext()
    guard let data = Data(base64Encoded: ciphertext) else {
      throw SignalError.invalidMessage("bad ciphertext")
    }
    if let preKey = try? PreKeySignalMessage(bytes: data) {
      let plain = try signalDecryptPreKey(
        message: preKey,
        from: address,
        sessionStore: store,
        identityStore: store,
        preKeyStore: store,
        signedPreKeyStore: store,
        kyberPreKeyStore: store,
        context: context
      )
      return String(decoding: plain, as: UTF8.self)
    }
    let message = try SignalMessage(bytes: data)
    let plain = try signalDecrypt(
      message: message,
      from: address,
      sessionStore: store,
      identityStore: store,
      context: context
    )
    return String(decoding: plain, as: UTF8.self)
  }

  private func buildPreKeyBundle(from bundle: [String: Any], deviceId: UInt32) throws -> PreKeyBundle {
    let registrationId = (bundle["registration_id"] as? Int) ?? 1
    let signedPreKeyId = (bundle["signed_pre_key_id"] as? Int) ?? 1
    let signedPreKeyB64 = (bundle["signed_pre_key"] as? String) ?? ""
    let signedPreKeySigB64 = (bundle["signed_pre_key_signature"] as? String) ?? ""
    let kyberPreKeyId = (bundle["kyber_pre_key_id"] as? Int) ?? 1
    let kyberPreKeyB64 = (bundle["kyber_pre_key"] as? String) ?? ""
    let kyberPreKeySigB64 = (bundle["kyber_pre_key_signature"] as? String) ?? ""
    let identityKeyB64 = (bundle["identity_key"] as? String) ?? (bundle["public_key"] as? String) ?? ""

    let signedPreKeyData = Data(base64Encoded: signedPreKeyB64) ?? Data()
    let signedPreKeySig = Data(base64Encoded: signedPreKeySigB64) ?? Data()
    let kyberPreKeyData = Data(base64Encoded: kyberPreKeyB64) ?? Data()
    let kyberPreKeySig = Data(base64Encoded: kyberPreKeySigB64) ?? Data()
    let identityKeyData = Data(base64Encoded: identityKeyB64) ?? Data()

    let signedPreKey = try PublicKey(signedPreKeyData)
    let kyberPreKey = try KEMPublicKey(kyberPreKeyData)
    let identityKey = try IdentityKey(bytes: identityKeyData)

    if let oneTimeList = bundle["one_time_pre_keys"] as? [[String: Any]],
       let entry = oneTimeList.first,
       let preKeyId = entry["id"] as? Int,
       let preKeyB64 = entry["key"] as? String,
       let preKeyData = Data(base64Encoded: preKeyB64)
    {
      let preKey = try PublicKey(preKeyData)
      return try PreKeyBundle(
        registrationId: UInt32(registrationId),
        deviceId: deviceId,
        prekeyId: UInt32(preKeyId),
        prekey: preKey,
        signedPrekeyId: UInt32(signedPreKeyId),
        signedPrekey: signedPreKey,
        signedPrekeySignature: signedPreKeySig,
        identity: identityKey,
        kyberPrekeyId: UInt32(kyberPreKeyId),
        kyberPrekey: kyberPreKey,
        kyberPrekeySignature: kyberPreKeySig
      )
    }

    return try PreKeyBundle(
      registrationId: UInt32(registrationId),
      deviceId: deviceId,
      signedPrekeyId: UInt32(signedPreKeyId),
      signedPrekey: signedPreKey,
      signedPrekeySignature: signedPreKeySig,
      identity: identityKey,
      kyberPrekeyId: UInt32(kyberPreKeyId),
      kyberPrekey: kyberPreKey,
      kyberPrekeySignature: kyberPreKeySig
    )
  }

  private func encryptBackup(payload: Data, backupSecretBase64: String) throws -> String {
    guard let keyData = Data(base64Encoded: backupSecretBase64) else {
      return ""
    }
    let key = SymmetricKey(data: keyData)
    let nonce = AES.GCM.Nonce()
    let sealed = try AES.GCM.seal(payload, using: key, nonce: nonce)
    guard let combined = sealed.combined else { return "" }
    let json: [String: Any] = [
      "v": 1,
      "alg": "A256GCM",
      "payload": combined.base64EncodedString(),
    ]
    let data = try JSONSerialization.data(withJSONObject: json)
    return String(data: data, encoding: .utf8) ?? ""
  }

  private func decryptBackup(payload: String, backupSecretBase64: String) throws -> Data {
    guard let keyData = Data(base64Encoded: backupSecretBase64) else {
      throw SignalError.invalidMessage("bad backup key")
    }
    guard let jsonData = payload.data(using: .utf8),
          let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
          let blob = json["payload"] as? String,
          let combined = Data(base64Encoded: blob)
    else {
      throw SignalError.invalidMessage("bad backup payload")
    }
    let key = SymmetricKey(data: keyData)
    let box = try AES.GCM.SealedBox(combined: combined)
    return try AES.GCM.open(box, using: key)
  }
}

private extension PersistentSignalProtocolStore {
  var signedPreKeys: [UInt32: SignedPreKeyRecord] { signedPrekeyMap }
  var kyberPreKeys: [UInt32: KyberPreKeyRecord] { kyberPrekeyMap }
  var preKeys: [UInt32: PreKeyRecord] { prekeyMap }

  func removeSession(for address: ProtocolAddress) {
    lock.lock()
    sessionMap.removeValue(forKey: address)
    lock.unlock()
    try? persist()
  }
}
