mod engine_protocol { #[derive(Debug)] pub enum ProtocolError { InvalidOperation } }
#[path="/workspace/Muyon/crates/muyon-core/src/document_edit/fingerprint.rs"] mod fingerprint;
use fingerprint::*;
fn main() {
 let cps=(0..256).chain((0..2048).map(|i|i*543)).chain([0xffff,0x10000,0x10ffff,0xd7ff,0xe000,0x1f600,0x2028,0x2029]);
 for cp in cps {if let Some(c)=char::from_u32(cp) {let s=c.to_string();let n=ExpandedNode{tag:"root".into(),attributes:vec![("z".into(),s.clone()),("{urn:é}a".into(),"value".into())],text:Some(s),tail:None,children:vec![]};println!("{}\t{}\t{}",cp,local_fingerprint(&n).unwrap(),String::from_utf8(canonical_tree_bytes(&n).unwrap()).unwrap());}}
}
