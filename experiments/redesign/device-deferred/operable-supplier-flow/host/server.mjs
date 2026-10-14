import http from 'node:http';
import {randomBytes, timingSafeEqual} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';
import {Flow, FlowError, validateAction} from './flow.mjs';
// Flat string-only action grammar rejects duplicate keys before JSON.parse.
function parseAction(text) {
 let i=0;const out={};const seen=new Set();const ws=()=>{while(/[\x20\t\r\n]/.test(text[i]??'!'))i++;};
 const take=c=>{ws();if(text[i++]!==c)throw new FlowError('invalid_action');};
 const string=()=>{ws();const token=/"(?:[^"\\\x00-\x1f]|\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4}))*"/y;token.lastIndex=i;const m=token.exec(text);if(!m)throw new FlowError('invalid_action');i=token.lastIndex;return JSON.parse(m[0]);};
 take('{');ws();if(text[i]!=='}')while(true){const k=string();if(seen.has(k))throw new FlowError('invalid_action');seen.add(k);take(':');const v=string();Object.defineProperty(out,k,{value:v,enumerable:true});ws();if(text[i]!==',')break;i++;}take('}');ws();if(i!==text.length)throw new FlowError('invalid_action');return validateAction(out);
}
function same(a,b){return typeof a==='string'&&Buffer.byteLength(a)===Buffer.byteLength(b)&&timingSafeEqual(Buffer.from(a),Buffer.from(b));}
export async function startServer({flow,port=0}) {
 const csrf=randomBytes(32).toString('hex');let url;
 const assets={'/':['index.html','text/html; charset=utf-8'],'/index.html':['index.html','text/html; charset=utf-8'],'/app.mjs':['app.mjs','text/javascript; charset=utf-8'],'/styles.css':['styles.css','text/css; charset=utf-8']};
 const server=http.createServer({maxHeaderSize:8192},async(req,res)=>{
  res.setHeader('Cache-Control','no-store');res.setHeader('X-Content-Type-Options','nosniff');res.setHeader('Referrer-Policy','no-referrer');res.setHeader('Content-Security-Policy',"default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'");
  const send=(status,value)=>{res.writeHead(status,{'Content-Type':'application/json; charset=utf-8'});res.end(JSON.stringify(value));};
  try {
   if(req.headers.host!==new URL(url).host||(req.headers.origin!==undefined&&req.headers.origin!==url)||req.headers['sec-fetch-site']==='cross-site')return send(403,{error:'loopback_origin_required'});
   const names=req.rawHeaders.filter((_,i)=>i%2===0).map(s=>s.toLowerCase());
   for(const name of ['host','origin','content-type','x-rd-p08-session','x-rd-p08-csrf'])if(names.filter(n=>n===name).length>1)return send(403,{error:'duplicate_header'});
   if(req.method==='GET'&&Object.hasOwn(assets,req.url)) {const [file,type]=assets[req.url];try{const body=await readFile(new URL(`../desktop/${file}`,import.meta.url));res.writeHead(200,{'Content-Type':type});res.end(body);}catch{send(404,{error:'asset_unavailable'});}return;}
   if(req.method==='GET'&&req.url==='/api/state') {const session=req.headers['x-rd-p08-session']??await flow.createSession();return send(200,{...await flow.state(session),csrf});}
   if(req.method!=='POST'||req.url!=='/api/action')return send(404,{error:'not_found'});
   if(req.headers.origin!==url||req.headers['content-type']!=='application/json'||req.headers['content-encoding']!==undefined||!same(req.headers['x-rd-p08-csrf'],csrf))return send(403,{error:'action_headers_required'});
   let size=0;const chunks=[];for await(const chunk of req){size+=chunk.length;if(size>32768){send(413,{error:'body_limit'});return;}chunks.push(chunk);}
   let body;try{body=new TextDecoder('utf-8',{fatal:true}).decode(Buffer.concat(chunks));}catch{return send(400,{error:'invalid_utf8'});}
   return send(200,{...await flow.action(req.headers['x-rd-p08-session'],parseAction(body)),csrf});
  }catch(e){const code=e instanceof FlowError?e.code:'host_unavailable';send(['unknown_session','invalid_state','session_limit'].includes(code)?409:code==='invalid_action'?400:503,{error:code});}
 });
 server.requestTimeout=5000;server.headersTimeout=5000;server.keepAliveTimeout=1000;
 await new Promise((yes,no)=>{server.once('error',no);server.listen(port,'127.0.0.1',yes);});url=`http://127.0.0.1:${server.address().port}`;
 return {server,url,close:()=>new Promise(r=>{server.close(r);server.closeIdleConnections();})};
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
 try {
  const args=process.argv.slice(2);let dir,port=8787;
  for(let i=0;i<args.length;i+=2){if(args[i]==='--data'&&!dir)dir=args[i+1];else if(args[i]==='--port'&&/^\d+$/.test(args[i+1]??''))port=Number(args[i+1]);else throw new Error();}
  if(!dir||!Number.isInteger(port)||port<0||port>65535)throw new Error();
  const flow=await Flow.open({dir});const host=await startServer({flow,port});process.stdout.write(JSON.stringify({url:host.url})+'\n');
  for(const signal of ['SIGINT','SIGTERM'])process.once(signal,async()=>{await host.close();await flow.close();process.exit(0);});
 }catch{process.stderr.write('RD-P08 host unavailable; verify private storage and trusted runtime.\n');process.exit(1);}
}
