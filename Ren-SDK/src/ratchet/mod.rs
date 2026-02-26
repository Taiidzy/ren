/// Double Ratchet Protocol Implementation
/// 
/// This module implements the Double Ratchet protocol using our existing crypto primitives.
/// The Double Ratchet provides:
/// - Forward Secrecy: Past messages remain secure if keys are compromised
/// - Post-Compromise Security: Future messages become secure after key ratcheting
/// - Out-of-order message decryption support
/// 
/// # References
/// - [Signal Double Ratchet Specification](https://signal.org/docs/specifications/doubleratchet/)

pub mod crypto_provider;
pub mod session;

pub use session::RatchetSession;
pub use session::RatchetMessage;
