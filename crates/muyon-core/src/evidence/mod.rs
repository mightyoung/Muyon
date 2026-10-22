//! Revision-bound local evidence and the trusted BusinessStore delivery adapter.
//! The pure processor and owner transaction boundary are separate modules.
mod local;
pub use local::*;
pub mod store;
