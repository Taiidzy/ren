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

pub mod chain;
pub mod dh_ratchet;
pub mod symmetric_ratchet;
pub mod session;

pub use session::RatchetSession;
pub use session::RatchetMessage;
pub use session::RatchetSessionState;
pub use chain::ChainKey;
pub use chain::RootKey;
pub use chain::MessageKey;
pub use chain::SkippedMessageKey;
pub use dh_ratchet::DhRatchet;
pub use symmetric_ratchet::SymmetricRatchet;
