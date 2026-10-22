//! Shared product rules and durable business state. Platform UI never writes this database.
pub mod agent;
pub mod archive;
pub mod blobs;
pub mod business;
pub mod contract;
pub mod documents;
pub mod research;
mod review_lifecycle;
pub mod sqlite;

pub mod artifacts;

pub mod bot_drafts;
pub mod bot_definitions;

pub mod document_edit;

pub mod evidence;

pub mod group_governance;

pub mod group_runtime;
#[path = "group_runtime/store.rs"]
pub mod group_runtime_store;
