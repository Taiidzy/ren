# Ren SDK

Cross-platform End-to-End Encryption (E2EE) messenger core written in Rust.

## Features

- 🔐 **X25519 ECDH** for key exchange
- 🔒 **ChaCha20-Poly1305** for AEAD encryption
- 🔑 **PBKDF2-HMAC-SHA256** for password-based key derivation
- 🌐 **Cross-platform**: iOS, Android, Web (WASM), Linux, Windows, macOS
- 🚀 **Zero-copy** FFI interfaces
- 📦 **Small binary size** with optimized builds

## Architecture

```
Rust Core (ren-sdk)
├── crypto.rs         - Cryptographic operations
├── types/mod.rs      - Type definitions
├── ffi.rs           - C ABI bindings (iOS, Android, C#, Flutter)
├── wasm.rs          - WebAssembly bindings (TypeScript/React)
└── lib.rs           - Main library entry
```

## Supported Platforms

| Platform | Language | Status |
|----------|----------|--------|
| iOS | Swift | ✅ Ready |
| Android | Kotlin/Java | ✅ Ready |
| Web | TypeScript/JavaScript | ✅ Ready |
| Linux | C/C++/C# | ✅ Ready |
| Windows | C/C++/C# | ✅ Ready |
| macOS | Swift/ObjC | ✅ Ready |
| Flutter | Dart | 🔄 Via FFI |

## Building

### Prerequisites

```bash
# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Install wasm-pack (for WASM)
cargo install wasm-pack

# Install cbindgen (for C headers)
cargo install cbindgen

# Install cargo-ndk (for Android)
cargo install cargo-ndk
```

### Build for All Platforms

```bash
chmod +x build.sh
./build.sh all
```

### Build for Specific Platforms

```bash
# iOS (Swift)
./build.sh ios

# Android (Kotlin/Java)
./build.sh android

# Web (TypeScript/React)
./build.sh wasm

# Linux
./build.sh linux

# Windows
./build.sh windows

# macOS
./build.sh macos
```

## Usage

### TypeScript/React (Web)

```typescript
import init, {
  generateKeyPair,
  generateMessageKey,
  encryptMessage,
  decryptMessage,
} from './pkg/bundler/ren_sdk';

// Initialize
await init();

// Generate keys
const keyPair = generateKeyPair();
const messageKey = generateMessageKey();

// Encrypt/Decrypt
const encrypted = encryptMessage("Hello, World!", messageKey);
const decrypted = decryptMessage(
  encrypted.ciphertext,
  encrypted.nonce,
  messageKey
);
```

### Swift (iOS/macOS)

```swift
import RenSDK

// Generate keys
let keyPair = RenSDK.generateKeyPair()
let messageKey = RenSDK.generateMessageKey()

// Encrypt/Decrypt
let encrypted = try RenSDK.encrypt(message: "Hello, World!", key: messageKey)
let decrypted = try RenSDK.decrypt(
    ciphertext: encrypted.ciphertext,
    nonce: encrypted.nonce,
    key: messageKey
)
```

### Kotlin (Android)

```kotlin
// Generate keys
val keyPair = RenSDK.generateKeyPair()
val messageKey = RenSDK.generateMessageKey()

// Encrypt/Decrypt
val encrypted = RenSDK.encryptMessage("Hello, World!", messageKey)
val decrypted = RenSDK.decryptMessage(
    encrypted.ciphertext,
    encrypted.nonce,
    messageKey
)
```

### C# (.NET)

```csharp
using System.Runtime.InteropServices;

[DllImport("ren_sdk")]
private static extern IntPtr ren_generate_message_key();

[DllImport("ren_sdk")]
private static extern RenEncryptedMessage ren_encrypt_message(
    string message,
    string key
);

// Usage
var key = Marshal.PtrToStringAnsi(ren_generate_message_key());
var encrypted = ren_encrypt_message("Hello, World!", key);
```

## End-to-End Encryption Flow

### 1. Key Generation

```typescript
// Alice and Bob generate their key pairs
const aliceKeys = generateKeyPair();
const bobKeys = generateKeyPair();
```

### 2. Key Exchange

```typescript
// Alice wraps message key for Bob
const messageKey = generateMessageKey();
const wrapped = wrapSymmetricKey(messageKey, bobKeys.public_key);
```

### 3. Message Encryption

```typescript
// Alice encrypts message
const encrypted = encryptMessage("Secret message", messageKey);
```

### 4. Message Decryption

```typescript
// Bob unwraps the key
const unwrappedKey = unwrapSymmetricKey(
  wrapped.wrapped_key,
  wrapped.ephemeral_public_key,
  wrapped.nonce,
  bobKeys.private_key
);

// Bob decrypts message
const decrypted = decryptMessage(
  encrypted.ciphertext,
  encrypted.nonce,
  unwrappedKey
);
```

## API Reference

### Key Generation

- `generateKeyPair()` - Generate X25519 key pair
- `generateMessageKey()` - Generate random symmetric key
- `generateNonce()` - Generate random nonce (12 bytes)
- `generateSalt()` - Generate random salt (16 bytes)

### Key Derivation

- `deriveKeyFromPassword(password, salt)` - PBKDF2 key derivation
- `deriveKeyFromString(secret)` - SHA-256 based derivation

### Encryption/Decryption

- `encryptMessage(message, key)` - Encrypt text message
- `decryptMessage(ciphertext, nonce, key)` - Decrypt message
- `encryptFile(bytes, filename, mimetype, key)` - Encrypt file
- `decryptFile(ciphertext, nonce, key)` - Decrypt file

### Key Wrapping

- `wrapSymmetricKey(key, receiverPublicKey)` - Wrap key for receiver
- `unwrapSymmetricKey(wrappedKey, ephemeralPublicKey, nonce, receiverPrivateKey)` - Unwrap key

## File Structure After Build

```
target/
├── xcframework/          # iOS libraries
│   ├── libren_sdk_sim.a    # iOS Simulator
│   └── libren_sdk_device.a # iOS Device
├── android/             # Android libraries
│   └── jniLibs/
│       ├── arm64-v8a/
│       ├── armeabi-v7a/
│       ├── x86/
│       └── x86_64/
├── linux/
│   └── libren_sdk.so
├── windows/
│   └── ren_sdk.dll
├── macos/
│   └── libren_sdk.dylib
├── pkg/                 # WASM packages
│   ├── web/            # For vanilla JS
│   ├── bundler/        # For Webpack/Vite
│   └── node/           # For Node.js
└── ren_sdk.h           # C header file
```

## Integration Examples

### iOS (Swift Package Manager)

1. Copy `libren_sdk.a` and `ren_sdk.h` to your Xcode project
2. Add to "Link Binary With Libraries"
3. Use `RenSDK.swift` wrapper

### Android (Gradle)

```gradle
android {
    sourceSets {
        main {
            jniLibs.srcDirs = ['libs/jniLibs']
        }
    }
}
```

### Web (Vite/React)

```bash
npm install ./pkg/bundler
```

```typescript
import init from 'ren-sdk';
await init();
```

### Flutter

```yaml
# pubspec.yaml
dependencies:
  ffi: ^2.0.0

flutter:
  assets:
    - assets/libren_sdk.so
```

## Security Considerations

- ✅ Keys are never logged or exposed
- ✅ Memory is zeroed after use (where possible)
- ✅ Constant-time operations for crypto primitives
- ✅ No key material in error messages
- ⚠️ Protect private keys at rest (use secure storage)
- ⚠️ Implement proper key rotation policies
- ⚠️ Use secure random number generators

## Performance

| Operation | Time (avg) | Notes |
|-----------|-----------|-------|
| Key Generation | ~1ms | X25519 |
| Encryption (1KB) | ~0.1ms | ChaCha20-Poly1305 |
| Decryption (1KB) | ~0.1ms | ChaCha20-Poly1305 |
| PBKDF2 (100k) | ~50ms | Password derivation |
| Key Wrapping | ~1ms | ECDH + HKDF |

*Benchmarks on Apple M1*

## Testing

```bash
# Unit tests
cargo test

# WASM tests
wasm-pack test --node

# FFI tests (requires native build)
cargo test --features ffi
```

## Troubleshooting

### iOS Build Fails

```bash
# Install iOS targets
rustup target add aarch64-apple-ios x86_64-apple-ios aarch64-apple-ios-sim
```

### Android Build Fails

```bash
# Install Android NDK
export ANDROID_NDK_HOME=/path/to/ndk
rustup target add aarch64-linux-android armv7-linux-androideabi
```

### WASM Build Fails

```bash
# Update wasm-pack
cargo install --force wasm-pack

# Clear cache
rm -rf pkg/ target/
```

## License

MIT License - see LICENSE file

## Contributing

Contributions are welcome! Please follow:

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing`)
5. Open Pull Request

## Support

- 📧 Email: taiidzy@yandex.ru
- 🐛 Issues: [GitHub Issues](https://github.com/yourusername/ren-sdk/issues)
- 📖 Docs: [Documentation](https://docs.example.com)

## Roadmap

- [ ] Flutter/Dart bindings
- [ ] Python bindings
- [ ] Go bindings
- [ ] Rust async API
- [ ] Key backup/recovery
- [ ] Group encryption
- [ ] Forward secrecy
- [ ] Post-quantum cryptography

---

Made with ❤️ by Taiidzy