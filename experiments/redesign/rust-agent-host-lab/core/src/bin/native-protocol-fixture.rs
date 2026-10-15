//! Synthetic process-fault endpoint, never a business handler/model.
use std::io::{Read, Write};
fn main() {
    let mode = std::env::args().nth(1).unwrap_or_default();
    let mut byte = [0];
    let _ = std::io::stdin().read(&mut byte);
    match mode.as_str() {
        "silent" => std::thread::sleep(std::time::Duration::from_secs(30)),
        "invalid" => {
            print!("invalid\n");
        }
        "oversize" => {
            let _ = std::io::stdout().write_all(&vec![b'x'; 65538]);
        }
        _ => {}
    }
}
