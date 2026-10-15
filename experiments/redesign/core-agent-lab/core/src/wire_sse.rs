//! Strict bounded byte decoder for the experimental profile.
use crate::{Result,model::ModelEvent};
#[derive(Clone,Debug,Default,PartialEq,Eq)]
pub struct Usage { pub prompt:Option<u64>,pub completion:Option<u64> }
#[derive(Clone,Debug,PartialEq,Eq)]
pub struct ArgumentObservation { pub call_ref:String,pub name:String,pub value:String }
#[derive(Clone,Debug,PartialEq,Eq)]
pub struct DecodedTurn {pub event:ModelEvent,pub usage:Usage}
#[derive(Default)]
pub struct Decoder {cancelled:bool}
impl Decoder {
    pub fn new()->Self{Self::default()}
    pub fn feed(&mut self,_byte:u8)->Result<Option<ArgumentObservation>>{Ok(None)}
    pub fn cancel(&mut self){self.cancelled=true;}
    pub fn finish(self)->Result<DecodedTurn>{Err(if self.cancelled{"wire_cancelled"}else{"wire_not_implemented"}.into())}
}
