//! muyon-office: pure-Rust OOXML engine for on-device use on every Muyon front end.
//!
//! Design constraints (enforced by dependency choice, not by convention):
//! * no C code, no native libraries, no process spawn, no network, no filesystem access;
//! * all input is untrusted bytes with hard size / depth / count limits;
//! * edits are narrow and pre-declared; every untouched package member is copied raw, so it is
//!   byte-identical by construction;
//! * the engine never claims publication, recalculation or visual fidelity - those belong to the
//!   host protocol and to separate evidence.

mod edit;
mod error;
mod package;
mod text;
pub mod xml;

pub use error::{OfficeError, Result};
pub use package::{EditReceipt, Format, Limits, Package};
pub use text::Section;
