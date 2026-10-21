//! Local process-fault harness, never an Android trusted-host authorization entry.
//! Compile the product store source directly to exercise its crate-private
//! transaction seam without exporting a production fault-injection API.
#[path = "../archive.rs"]
#[allow(dead_code)]
mod archive;
#[path = "../blobs.rs"]
#[allow(dead_code)]
mod blobs;
#[path = "../business.rs"]
#[allow(dead_code)]
mod business;
#[path = "../contract.rs"]
#[allow(dead_code)]
mod contract;
#[path = "../research.rs"]
#[allow(dead_code)]
mod research;
#[path = "../review_lifecycle.rs"]
#[allow(dead_code)]
mod review_lifecycle;
#[path = "../sqlite.rs"]
#[allow(dead_code)]
mod sqlite;
use business::{BusinessStore, SupplierRecord};
use contract::*;
use std::{
    io::{self, Write},
    path::Path,
};

fn checkpoint(label: &str) {
    println!("{label}");
    io::stdout().flush().unwrap();
    let mut line = String::new();
    let _ = io::stdin().read_line(&mut line);
}
fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        std::process::exit(2);
    }
}
fn run() -> Result<(), ContractError> {
    let args: Vec<String> = std::env::args().collect();
    let mode = args.get(1).ok_or(ContractError::InvalidPayload)?;
    let path = Path::new(args.get(2).ok_or(ContractError::InvalidPayload)?);
    let store = BusinessStore::open_existing(path, "workspace-a", "epoch-a")?;
    if mode == "hold-owner" {
        checkpoint("OWNER_READY");
        return Ok(());
    }
    let raw = std::fs::read_to_string(args.get(3).ok_or(ContractError::InvalidPayload)?)
        .map_err(|_| ContractError::Storage)?;
    let command = CommandEnvelope::decode(&raw)?;
    store.issue_grant_trusted(&command, None)?;
    if mode == "after-sql" {
        store.execute_with(&command, |db, _transaction, command| {
            let Operation::SupplierCreate {
                supplier_id,
                payload,
            } = &command.command
            else {
                return Err(ContractError::InvalidPayload);
            };
            let record = SupplierRecord {
                id: supplier_id.clone(),
                payload: payload.normalize()?,
                revision: Revision::new(1),
                deleted: false,
            };
            let payload = serde_json::to_string(&record.payload).unwrap();
            db.exec(
                "INSERT INTO supplier(id,workspace,payload,revision,deleted) VALUES(?,?,?,'1',0)",
                &[supplier_id, "workspace-a", &payload],
            )
            .map_err(|_| ContractError::Storage)?;
            checkpoint("SQL_APPLIED_UNCOMMITTED");
            Ok(serde_json::to_value(record).unwrap())
        })?;
    } else if mode == "after-commit" {
        let result = store.execute(&command)?;
        if result.status != ExecutionStatus::Committed {
            return Err(ContractError::Unknown);
        }
        checkpoint("COMMITTED_REPLY_WITHHELD");
    } else {
        return Err(ContractError::Unsupported);
    }
    Ok(())
}
