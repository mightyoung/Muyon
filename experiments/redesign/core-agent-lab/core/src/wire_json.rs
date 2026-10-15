//! Bounded JSON grammar for the offline fixture profile; no permissive extraction.
use std::collections::BTreeMap;
use crate::Result;
#[derive(Clone,Debug,PartialEq,Eq)]
pub enum Json { Null, Bool(bool), Number(String), String(String), Array(Vec<Json>), Object(BTreeMap<String,Json>) }
impl Json {
    pub fn object(&self)->Result<&BTreeMap<String,Json>>{if let Self::Object(v)=self{Ok(v)}else{Err("wire_json_object".into())}}
    pub fn array(&self)->Result<&[Json]>{if let Self::Array(v)=self{Ok(v)}else{Err("wire_json_array".into())}}
    pub fn string(&self)->Result<&str>{if let Self::String(v)=self{Ok(v)}else{Err("wire_json_string".into())}}
    pub fn integer(&self)->Result<u64>{match self{Self::Number(s) if !s.is_empty()&&s.bytes().all(|b|b.is_ascii_digit())=>s.parse().map_err(|_|"wire_json_integer".into()),_=>Err("wire_json_integer".into())}}
    pub fn encode(&self)->String{match self{Self::Null=>"null".into(),Self::Bool(b)=>b.to_string(),Self::Number(n)=>n.clone(),Self::String(s)=>quote(s),Self::Array(a)=>format!("[{}]",a.iter().map(Json::encode).collect::<Vec<_>>().join(",")),Self::Object(o)=>format!("{{{}}}",o.iter().map(|(k,v)|format!("{}:{}",quote(k),v.encode())).collect::<Vec<_>>().join(","))}}
}
pub fn object(fields:impl IntoIterator<Item=(impl Into<String>,Json)>)->Json{Json::Object(fields.into_iter().map(|(k,v)|(k.into(),v)).collect())}
pub fn string(s:impl Into<String>)->Json{Json::String(s.into())}
pub fn quote(s:&str)->String{let mut out=String::from("\"");for c in s.chars(){match c{'"'=>out.push_str("\\\""),'\\'=>out.push_str("\\\\"),'\n'=>out.push_str("\\n"),'\r'=>out.push_str("\\r"),'\t'=>out.push_str("\\t"),c if c<'\u{20}'=>out.push_str(&format!("\\u{:04x}",c as u32)),c=>out.push(c)}}out.push('"');out}
pub fn parse(bytes:&[u8])->Result<Json>{
    if bytes.len()>65536{return Err("wire_json_size".into());}std::str::from_utf8(bytes).map_err(|_|"wire_utf8")?;
    let mut p=Parser{bytes,pos:0,nodes:0};let value=p.value(0)?;p.space();if p.pos!=bytes.len(){return Err("wire_json_trailing".into());}Ok(value)
}
struct Parser<'a>{bytes:&'a[u8],pos:usize,nodes:usize}
impl Parser<'_>{
    fn space(&mut self){while self.bytes.get(self.pos).is_some_and(|b|matches!(b,b' '|b'\n'|b'\r'|b'\t')){self.pos+=1;}}
    fn take(&mut self,b:u8)->bool{if self.bytes.get(self.pos)==Some(&b){self.pos+=1;true}else{false}}
    fn require(&mut self,b:u8)->Result<()>{if self.take(b){Ok(())}else{Err("wire_json_syntax".into())}}
    fn value(&mut self,depth:usize)->Result<Json>{
        self.space();self.nodes+=1;if depth>32||self.nodes>32768{return Err("wire_json_depth".into());}
        match self.bytes.get(self.pos).copied(){
            Some(b'"')=>Ok(Json::String(self.text()?)),
            Some(b'{')=>{self.pos+=1;self.space();let mut map=BTreeMap::new();if self.take(b'}'){return Ok(Json::Object(map));}loop{self.space();let key=self.text()?;self.space();self.require(b':')?;let value=self.value(depth+1)?;if map.insert(key,value).is_some(){return Err("wire_json_duplicate".into());}self.space();if self.take(b'}'){break;}self.require(b',')?;}Ok(Json::Object(map))},
            Some(b'[')=>{self.pos+=1;self.space();let mut values=Vec::new();if self.take(b']'){return Ok(Json::Array(values));}loop{values.push(self.value(depth+1)?);self.space();if self.take(b']'){break;}self.require(b',')?;}Ok(Json::Array(values))},
            Some(b't')=>{self.literal(b"true")?;Ok(Json::Bool(true))},Some(b'f')=>{self.literal(b"false")?;Ok(Json::Bool(false))},Some(b'n')=>{self.literal(b"null")?;Ok(Json::Null)},
            Some(b'-'|b'0'..=b'9')=>self.number(),_=>Err("wire_json_syntax".into()),
        }
    }
    fn literal(&mut self,s:&[u8])->Result<()>{if self.bytes.get(self.pos..self.pos+s.len())==Some(s){self.pos+=s.len();Ok(())}else{Err("wire_json_literal".into())}}
    fn digits(&mut self)->Result<()>{let start=self.pos;while self.bytes.get(self.pos).is_some_and(u8::is_ascii_digit){self.pos+=1;}if self.pos==start{Err("wire_json_number".into())}else{Ok(())}}
    fn number(&mut self)->Result<Json>{let start=self.pos;self.take(b'-');if self.take(b'0'){if self.bytes.get(self.pos).is_some_and(u8::is_ascii_digit){return Err("wire_json_number".into());}}else{self.digits()?;}if self.take(b'.'){self.digits()?;}if self.take(b'e')||self.take(b'E'){if !self.take(b'+'){self.take(b'-');}self.digits()?;}Ok(Json::Number(std::str::from_utf8(&self.bytes[start..self.pos]).map_err(|_|"wire_utf8")?.into()))}
    fn hex4(&mut self)->Result<u32>{let mut value=0;for _ in 0..4{let b=*self.bytes.get(self.pos).ok_or("wire_json_escape")?;self.pos+=1;value=value*16+match b{b'0'..=b'9'=>(b-b'0')as u32,b'a'..=b'f'=>(b-b'a'+10)as u32,b'A'..=b'F'=>(b-b'A'+10)as u32,_=>return Err("wire_json_escape".into())};}Ok(value)}
    fn text(&mut self)->Result<String>{
        self.require(b'"')?;let mut out=Vec::new();loop{let b=*self.bytes.get(self.pos).ok_or("wire_json_string")?;self.pos+=1;match b{
            b'"'=>return String::from_utf8(out).map_err(|_|"wire_utf8".into()),
            0..=31=>return Err("wire_json_control".into()),
            b'\\'=>{let escape=*self.bytes.get(self.pos).ok_or("wire_json_escape")?;self.pos+=1;match escape{
                b'"'|b'\\'|b'/'=>out.push(escape),b'b'=>out.push(8),b'f'=>out.push(12),b'n'=>out.push(b'\n'),b'r'=>out.push(b'\r'),b't'=>out.push(b'\t'),
                b'u'=>{let mut cp=self.hex4()?;if(0xD800..=0xDBFF).contains(&cp){self.require(b'\\')?;self.require(b'u')?;let low=self.hex4()?;if !(0xDC00..=0xDFFF).contains(&low){return Err("wire_json_surrogate".into());}cp=0x10000+((cp-0xD800)<<10)+(low-0xDC00);}else if(0xDC00..=0xDFFF).contains(&cp){return Err("wire_json_surrogate".into());}let c=char::from_u32(cp).ok_or("wire_json_surrogate")?;let mut buf=[0;4];out.extend_from_slice(c.encode_utf8(&mut buf).as_bytes());},
                _=>return Err("wire_json_escape".into()),
            }},_=>out.push(b),
        }}
    }
}
