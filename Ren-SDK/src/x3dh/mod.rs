/// X3DH (Extended Triple Diffie-Hellman) Protocol Implementation
/// 
/// This module implements the X3DH key agreement protocol used for establishing
/// secure sessions in the Signal Protocol.
/// 
/// # References
/// - [Signal X3DH Specification](https://signal.org/docs/specifications/x3dh/)

pub mod identity;
pub mod bundle;
pub mod protocol;

pub use identity::IdentityKeyStore;
pub use bundle::PreKeyBundle;
pub use protocol::{x3dh_initiate, x3dh_respond, x3dh_respond_with_otk, SharedSecret};
