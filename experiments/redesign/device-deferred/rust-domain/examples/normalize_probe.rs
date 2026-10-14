//! Offline synthetic test protocol, not a product wire schema.
use std::io::{self, Read};
use serde_json::{json, Value};
fn main() {
    let mut input = String::new(); io::stdin().read_to_string(&mut input).unwrap();
    let cases: Vec<Value> = serde_json::from_str(&input).unwrap();
    let rows: Vec<Value> = cases.iter().map(|c| {
        let units: Vec<u16> = c["units"].as_array().unwrap().iter().map(|x| u16::try_from(x.as_u64().unwrap()).unwrap()).collect();
        match rd_p01_domain_experiment::normalize_raw(&units) {
            Ok(name) => json!({"id": c["id"], "outcome": "accepted", "normalized": name}),
            Err(error) => json!({"id": c["id"], "outcome": "rejected", "reason": format!("{error:?}")}),
        }
    }).collect();
    println!("{}", serde_json::to_string(&rows).unwrap());
}
