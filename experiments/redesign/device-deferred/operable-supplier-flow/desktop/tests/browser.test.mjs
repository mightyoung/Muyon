// These are real Chromium DOM/event tests against a MOCK host, never SQLite evidence.
import assert from 'node:assert/strict';
import { test, before, after, afterEach } from 'node:test';
import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import { mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const desktop = dirname(dirname(fileURLToPath(import.meta.url)));
const row = (supplier='S1', name='同名合成供应商', revision='1') => ({ supplier, name, revision });
const edit = (status='editing', extra={}) => ({ intent:'mock-intent', supplier:'S1', raw:' 我的修改 ', status, expected_revision:'1', preview:null, current:row(), receipt:null, reason:null, ...extra });
const receipt = () => ({ intent:'mock-intent', binding:{domain:'mock',scope:'mock',supplier:'S1',intent:'mock-intent',operation:'supplier.name',raw_utf16:[32,65,32],expected_revision:'1',plan:'mock-plan',candidate:'mock-candidate'}, binding_sha256:'a'.repeat(64), source:'mock-source', supplier:'S1', old_name:'同名合成供应商', new_name:'A', old_revision:'1', new_revision:'2' });
const fixture = (editor=null) => ({ suppliers:[row(),row('S2')], selected:row(), editor, capability:'合成实验可信本机能力；正式授权未接线 · M03 blocked_contract', csrf:'mock-nonce',session:'mock-session',list_status:'available',recoverable_sessions:[] });
let state, actions, requestHeaders, reply, failRead=false, server, browser, ws, origin, profile, sequence=0;
const pending=new Map();
let pageErrors=[], externalRequests=[];
const keyActivate=async id=>{await evaluate(`document.getElementById(${JSON.stringify(id)}).focus()`);await call('Input.dispatchKeyEvent',{type:'keyDown',key:'Enter',code:'Enter',windowsVirtualKeyCode:13,text:'\r',unmodifiedText:'\r'});await call('Input.dispatchKeyEvent',{type:'keyUp',key:'Enter',code:'Enter',windowsVirtualKeyCode:13});};
const call=(method,params={})=>new Promise((resolve,reject)=>{const id=++sequence;pending.set(id,{resolve,reject});ws.send(JSON.stringify({id,method,params}));});
const evaluate=async expression=>{const r=await call('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(r.exceptionDetails)throw new Error(r.exceptionDetails.exception?.description??r.exceptionDetails.text);return r.result.value;};
const wait=async fn=>{for(let i=0;i<100;i++){if(await fn())return;await new Promise(r=>setTimeout(r,30));}throw new Error('Timed out waiting for browser/request condition');};
const click=id=>evaluate(`document.getElementById(${JSON.stringify(id)}).click()`);
const text=id=>evaluate(`document.getElementById(${JSON.stringify(id)})?.textContent`);
const exists=id=>evaluate(`Boolean(document.getElementById(${JSON.stringify(id)}))`);
async function open(next=fixture()) { state=structuredClone(next);actions=[];requestHeaders=[];reply=null;failRead=false;pageErrors=[];externalRequests=[];await evaluate('sessionStorage.clear()');await call('Page.navigate',{url:origin});await wait(()=>evaluate("document.readyState==='complete'"));await wait(()=>Promise.resolve(requestHeaders.length>0));await wait(()=>evaluate("document.body.dataset.busy==='false'")); }
async function input(raw){await evaluate(`{const el=document.getElementById('raw-name');el.focus();el.value=${JSON.stringify(raw)};el.dispatchEvent(new Event('input',{bubbles:true}));}`);}
async function requests(count){await wait(()=>Promise.resolve(actions.length>=count));await wait(()=>evaluate("document.body.dataset.busy!=='true'"));}

before(async()=>{
  profile=await mkdtemp(join(tmpdir(),'rd-p08-browser-mock-'));
  state=fixture();actions=[];requestHeaders=[];
  server=createServer(async(req,res)=>{
    if(req.url==='/api/state'){requestHeaders.push(req.headers);res.setHeader('Content-Type','application/json');if(failRead){res.writeHead(503);res.end('{}');return;}res.end(JSON.stringify({...state,session:req.headers['x-rd-p08-session']??state.session}));return;}
    if(req.url==='/api/action') { let raw='';for await(const chunk of req)raw+=chunk;const action=JSON.parse(raw);actions.push(action);requestHeaders.push(req.headers);if(reply){await reply(action,res);return;}if(action.action==='draft'&&state.editor){state.editor.raw=action.raw;state.editor.status='editing';state.editor.preview=null;}res.setHeader('Content-Type','application/json');res.end(JSON.stringify(state));return; }
    const assets={'/':'index.html','/app.mjs':'app.mjs','/styles.css':'styles.css'};
    try {const name=assets[req.url];if(!name)throw Error('not asset');res.setHeader('Content-Type',name.endsWith('.mjs')?'text/javascript':name.endsWith('.css')?'text/css':'text/html');res.end(await readFile(join(desktop,name)));} catch {res.writeHead(404);res.end('Page not implemented');}
  });await new Promise(r=>server.listen(0,'127.0.0.1',r));origin=`http://127.0.0.1:${server.address().port}`;
  browser=spawn('/usr/bin/chromium',['--headless','--no-sandbox','--disable-dev-shm-usage','--remote-debugging-port=0',`--user-data-dir=${profile}`,'about:blank'],{stdio:'ignore'});
  let port;await wait(async()=>{try {port=(await readFile(join(profile,'DevToolsActivePort'),'utf8')).split('\n')[0];return !!port;}catch{return false;}});
  const targets=await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();ws=new WebSocket(targets.find(t=>t.type==='page').webSocketDebuggerUrl);await new Promise(r=>ws.addEventListener('open',r,{once:true}));ws.addEventListener('message',event=>{const m=JSON.parse(event.data);if(m.method==='Runtime.exceptionThrown')pageErrors.push(m.params.exceptionDetails);if(m.method==='Runtime.consoleAPICalled'&&m.params.type==='error')pageErrors.push(m.params);if(m.method==='Network.requestWillBeSent'&&/^https?:/.test(m.params.request.url)&&!m.params.request.url.startsWith(origin+'/'))externalRequests.push(m.params.request.url);if(m.id){const p=pending.get(m.id);pending.delete(m.id);m.error?p.reject(m.error):p.resolve(m.result);}});await call('Page.enable');await call('Runtime.enable');await call('Network.enable');await call('Page.navigate',{url:origin});await wait(()=>evaluate(`location.href===${JSON.stringify(origin+'/')}`));
});
afterEach(()=>{assert.deepEqual(pageErrors,[],'unexpected page runtime/console errors');assert.deepEqual(externalRequests,[],'unexpected external browser request');});
after(async()=>{if(ws){await call('Browser.close').catch(()=>{});ws.close();}browser?.kill();await new Promise(r=>server?.close(r));});

test('MOCK host: renders same-name rows by stable supplier ID and sends selected ID',async()=>{
 await open();assert.equal(await evaluate('document.title'),'供应商名称 · RD-P08 合成实验');assert.equal(await exists('D01.1-LIST'),true,'required supplier list is missing');assert.match(await text('supplier-S1'),/S1/);assert.match(await text('supplier-S2'),/S2/);await click('supplier-S2');await requests(1);assert.deepEqual(actions,[{action:'select',supplier:'S2'}]);assert.equal(requestHeaders.at(-1)['x-rd-p08-csrf'],'mock-nonce');assert.equal(requestHeaders.at(-1)['x-rd-p08-session'],'mock-session');assert.equal(requestHeaders.at(-1).origin,origin);
});
test('MOCK host: renders markup as text and preserves current/draft/historical receipt independently',async()=>{
 const r=receipt();r.new_name='historical';const s=fixture(edit('saved',{raw:'<svg onload="window.pwned=1">',current:row('S1','<img src=x onerror="window.pwned=1">','3'),receipt:r}));s.selected=s.editor.current;await open(s);assert.match(await text('current-name'),/<img/);assert.match(await text('D01.1-RECEIPT'),/historical/);assert.equal(await evaluate('window.pwned'),undefined);assert.equal(await evaluate("document.querySelectorAll('#current-name img,#receipt-json svg').length"),0);assert.match(await text('editor-status'),/已保存/);assert.match(await text('current-revision'),/3/);
});
test('MOCK host: version conflict retains exact raw input and original expected revision',async()=>{
 await open(fixture(edit('conflict',{raw:'  冲突\n\ud800  ',reason:'Revision',current:row('S1','别人的修改','2')})));assert.match(await text('editor-status'),/版本冲突/);assert.equal(await evaluate("document.getElementById('raw-name').value"),'  冲突\n\ud800  ');assert.match(await text('expected-revision'),/1/);assert.match(await text('current-name'),/别人的修改/);assert.equal(await evaluate("document.getElementById('save').disabled"),true);
});
test('MOCK host: binding conflict is distinct from stale revision',async()=>{
 await open(fixture(edit('conflict',{reason:'Binding'})));assert.match(await text('editor-status'),/绑定冲突/);assert.doesNotMatch(await text('editor-status'),/版本冲突/);
});
test('MOCK host: unknown keeps immutable editor visible after other supplier selection and offers lookup only',async()=>{
 const s=fixture(edit('unknown'));s.selected=row('S2');await open(s);assert.match(await text('editor-identity'),/S1/);assert.match(await text('selected-identity'),/S2/);assert.equal(await evaluate("document.getElementById('raw-name').readOnly"),true);for(const id of ['edit','preview','save','cancel'])assert.equal(await evaluate(`document.getElementById('${id}').disabled`),true);await click('lookup');await requests(1);assert.deepEqual(actions,[{action:'lookup'}]);assert.doesNotMatch(await text('editor-status'),/已保存/);
});
test('MOCK host: serializes latest exact raw UTF16 before preview, deduplicates double preview, and preserves focus',async()=>{
 await open(fixture(edit()));const raw='  A\n\ud800\u0000  ';await input(raw);await evaluate("document.getElementById('preview').click();document.getElementById('preview').click()");await requests(2);assert.deepEqual(actions,[{action:'draft',raw},{action:'preview'}]);assert.equal(await evaluate("document.getElementById('raw-name').value"),raw);
});
test('MOCK host: late draft response does not erase newer input or move keyboard focus',async()=>{
 await open(fixture(edit()));let release;reply=async(a,res)=>{if(a.action==='draft'&&a.raw==='first'){await new Promise(r=>{release=r;});}state.editor.raw=a.raw;res.setHeader('Content-Type','application/json');res.end(JSON.stringify(state));};await input('first');await wait(()=>Promise.resolve(!!release));await input('newest');release();await requests(2);assert.equal(await evaluate("document.getElementById('raw-name').value"),'newest');assert.equal(await evaluate('document.activeElement.id'),'raw-name');
});
test('MOCK host: double save sends once and acknowledgement without a receipt never shows saved',async()=>{
 await open(fixture(edit('prepared',{preview:{normalized_name:'A',candidate_revision:'2'}})));let release;reply=async(a,res)=>{await new Promise(r=>{release=r;});res.setHeader('Content-Type','application/json');res.end(JSON.stringify(fixture(edit('saved'))));};await evaluate("document.getElementById('save').click();document.getElementById('save').click()");await wait(()=>Promise.resolve(!!release));try{assert.equal(actions.length,1);assert.match(await text('transport-status'),/保存请求进行中/);assert.equal(await evaluate("document.getElementById('raw-name').readOnly"),true,'saving freezes raw editor before host reply');assert.doesNotMatch(await text('editor-status'),/已保存/);}finally{release();}await requests(1);assert.doesNotMatch(await text('editor-status'),/已保存/);assert.match(await text('transport-status'),/未核实|无效/);
});
test('MOCK host: cancel shows unsaved buffer before explicit discard and never sends edit automatically',async()=>{
 await open(fixture(edit()));await click('cancel');assert.match(await text('discard-warning'),/未保存/);assert.equal(actions.length,0);await click('confirm-discard');await requests(1);assert.deepEqual(actions,[{action:'cancel'}]);
});
test('MOCK host: partial list and read failure stay visible and retain local raw draft',async()=>{
 const s=fixture(edit());s.list_status='partial';s.suppliers=[row()];await open(s);assert.match(await text('list-status'),/部分/);await input('本地保留');await requests(1);failRead=true;await click('refresh');await wait(()=>evaluate("document.body.dataset.busy!=='true'"));assert.match(await text('transport-status'),/未核实|不可用/);assert.equal(await evaluate("document.getElementById('raw-name').value"),'本地保留');
});
test('MOCK host: explicit recovery selects original session by read only and keeps lab authority label',async()=>{
 const s=fixture();s.recoverable_sessions=[{session:'original-session',supplier:'S1',status:'unknown'}];await open(s);assert.match(await text('capability'),/M03 blocked_contract/);await click('recover-original-session');await wait(()=>Promise.resolve(requestHeaders.at(-1)['x-rd-p08-session']==='original-session'));assert.equal(actions.length,0);assert.equal(await evaluate("sessionStorage.getItem('rd-p08-session')"),'original-session');
});
test('MOCK host: mobile list → detail → full editor and 200% text remain operable without horizontal overflow',async()=>{
 await call('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});await open();assert.equal(await evaluate('document.body.dataset.view'),'list');await click('supplier-S1');await requests(1);assert.equal(await evaluate('document.body.dataset.view'),'detail');reply=async(a,res)=>{state.editor=edit();res.setHeader('Content-Type','application/json');res.end(JSON.stringify(state));};await click('edit');await requests(2);assert.equal(await evaluate('document.body.dataset.view'),'editor');await evaluate("document.documentElement.style.fontSize='32px'");const layout=await evaluate("({width:innerWidth,scroll:document.documentElement.scrollWidth,rawBottom:document.getElementById('raw-name').getBoundingClientRect().bottom,buttonsTop:document.getElementById('editor-actions').getBoundingClientRect().top})");assert.ok(layout.scroll<=layout.width,JSON.stringify(layout));assert.ok(layout.buttonsTop>=layout.rawBottom,JSON.stringify(layout));if(process.env.RD_P08_SCREENSHOT_DIR){const shot=await call('Page.captureScreenshot',{format:'png',captureBeyondViewport:true});await writeFile(join(process.env.RD_P08_SCREENSHOT_DIR,'mock-mobile-200.png'),Buffer.from(shot.data,'base64'));}await evaluate("document.documentElement.style.fontSize=''");await call('Emulation.setDeviceMetricsOverride',{width:1400,height:1000,deviceScaleFactor:1,mobile:false});
});


test('MOCK host: failed draft remains raw and explicit preview persists the retained raw after read refresh',async()=>{
 await open(fixture(edit()));reply=async(a,res)=>{res.writeHead(503);res.end('{}');};await input(' retained raw ');await requests(1);assert.match(await text('transport-status'),/未核实/);reply=null;await click('refresh');await wait(()=>evaluate("document.body.dataset.busy==='false'"));await click('preview');await requests(3);assert.deepEqual(actions,[{action:'draft',raw:' retained raw '},{action:'draft',raw:' retained raw '},{action:'preview'}]);
});
test('MOCK host: existing unresolved editor blocks restoration of a different session',async()=>{
 const s=fixture(edit('unknown'));s.recoverable_sessions=[{session:'other-session',supplier:'S2',status:'editing'}];await open(s);assert.equal(await evaluate("document.getElementById('recover-other-session').disabled"),true);await click('recover-other-session');assert.equal(await evaluate("sessionStorage.getItem('rd-p08-session')"),'mock-session');
});
test('MOCK host: desktop columns reflow at 200% font with input and buttons in normal flow',async()=>{
 await call('Emulation.setDeviceMetricsOverride',{width:1400,height:1000,deviceScaleFactor:1,mobile:false});await open(fixture(edit()));const columns=await evaluate("['directory-search','D01.1-LIST','D01.1-DETAIL'].map(id=>{const r=document.getElementById(id).getBoundingClientRect();return {x:r.x,y:r.y};})");assert.ok(columns[0].x<columns[1].x&&columns[1].x<columns[2].x,JSON.stringify(columns));if(process.env.RD_P08_SCREENSHOT_DIR){const shot=await call('Page.captureScreenshot',{format:'png',captureBeyondViewport:true});await writeFile(join(process.env.RD_P08_SCREENSHOT_DIR,'mock-desktop.png'),Buffer.from(shot.data,'base64'));}await evaluate("document.documentElement.style.fontSize='32px'");const layout=await evaluate("({width:innerWidth,scroll:document.documentElement.scrollWidth,rawBottom:document.getElementById('raw-name').getBoundingClientRect().bottom,buttonsTop:document.getElementById('editor-actions').getBoundingClientRect().top})");assert.ok(layout.scroll<=layout.width,JSON.stringify(layout));assert.ok(layout.buttonsTop>=layout.rawBottom,JSON.stringify(layout));if(process.env.RD_P08_SCREENSHOT_DIR){const shot=await call('Page.captureScreenshot',{format:'png',captureBeyondViewport:true});await writeFile(join(process.env.RD_P08_SCREENSHOT_DIR,'mock-desktop-200.png'),Buffer.from(shot.data,'base64'));}await evaluate("document.documentElement.style.fontSize=''");
});


test('MOCK host: keyboard Enter follows stable-ID select → edit → preview → verified receipt controls',async()=>{
 await call('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});await open();
 reply=async(a,res)=>{if(a.action==='select')state.selected=row(a.supplier);if(a.action==='edit')state.editor=edit();if(a.action==='draft')state.editor.raw=a.raw;if(a.action==='preview'){state.editor.status='prepared';state.editor.preview={normalized_name:'A',candidate_revision:'2'};}if(a.action==='save'){state.editor.status='saved';state.editor.receipt=receipt();state.editor.current=row('S1','A','2');state.selected=state.editor.current;}res.setHeader('Content-Type','application/json');res.end(JSON.stringify(state));};
 await keyActivate('supplier-S1');await requests(1);await keyActivate('edit');await requests(2);assert.equal(await evaluate('document.activeElement.id'),'raw-name');await call('Input.dispatchKeyEvent',{type:'keyDown',key:'a',code:'KeyA',windowsVirtualKeyCode:65,modifiers:2});await call('Input.dispatchKeyEvent',{type:'keyUp',key:'a',code:'KeyA',windowsVirtualKeyCode:65,modifiers:2});await call('Input.insertText',{text:' A '});await requests(3);await keyActivate('preview');await requests(4);assert.match(await text('editor-status'),/尚未保存/);await keyActivate('save');await requests(5);assert.match(await text('editor-status'),/已保存/);assert.deepEqual(actions.map(a=>a.action),['select','edit','draft','preview','save']);assert.equal(actions[2].raw,' A ');assert.equal(await evaluate("document.getElementById('raw-name').labels[0].textContent"),'名称原始输入');
});

test('MOCK host: untouched recovered CR/CRLF draft reaches preview without replacement',async()=>{
 const original='A\r\nB\rC';await open(fixture(edit('editing',{raw:original})));await click('preview');await requests(1);assert.deepEqual(actions,[{action:'preview'}]);assert.equal(state.editor.raw,original);
});
test('MOCK host: native prepend and append preserve recovered CR/CRLF UTF16 units',async()=>{
 const original='A\r\nB\rC';await open(fixture(edit('editing',{raw:original})));await evaluate("document.getElementById('raw-name').focus();document.getElementById('raw-name').setSelectionRange(0,0)");await call('Input.insertText',{text:'前'});await requests(1);assert.equal(actions[0].raw,'前'+original);await evaluate("document.getElementById('raw-name').setSelectionRange(1000,1000)");await call('Input.insertText',{text:'后'});await requests(2);assert.equal(actions[1].raw,'前'+original+'后');
});
test('MOCK host: new native insertion uses original beforeinput data when display folds CRLF',async()=>{
 await open(fixture(edit('editing',{raw:'A'})));await evaluate("window.rawInsertionEvents=[];document.getElementById('raw-name').addEventListener('beforeinput',e=>window.rawInsertionEvents.push({type:e.inputType,data:e.data}));document.getElementById('raw-name').focus();document.getElementById('raw-name').setSelectionRange(1,1)");await call('Input.insertText',{text:'\r\nZ'});await requests(1);assert.equal(await evaluate('window.rawInsertionEvents[0].data'),'\r\nZ','CDP source beforeinput data differs from raw probe');assert.equal(actions[0].raw,'A\r\nZ');
});

test('MOCK host: pre-dispatch preview unavailability allows editing/preview/cancel and disables lookup',async()=>{
 await open(fixture(edit('unavailable',{reason:'preview_unavailable'})));for(const id of ['preview','cancel'])assert.equal(await evaluate(`document.getElementById('${id}').disabled`),false);assert.equal(await evaluate("document.getElementById('raw-name').readOnly"),false);assert.equal(await evaluate("document.getElementById('lookup').disabled"),true);assert.match(await text('editor-status'),/预览/);
});
test('MOCK host: dispatched lookup unavailability retains raw and permits lookup only',async()=>{
 await open(fixture(edit('unknown',{reason:'lookup_unavailable'})));assert.equal(await evaluate("document.getElementById('raw-name').readOnly"),true);for(const id of ['edit','preview','save','cancel'])assert.equal(await evaluate(`document.getElementById('${id}').disabled`),true);assert.equal(await evaluate("document.getElementById('lookup').disabled"),false);
});
test('MOCK host: lookup binding conflict remains unknown and labels binding mismatch distinctly',async()=>{
 await open(fixture(edit('unknown',{reason:'binding_conflict'})));assert.match(await text('editor-status'),/绑定冲突/);assert.match(await text('editor-status'),/未知/);assert.equal(await evaluate("document.getElementById('cancel').disabled"),true);
});

test('MOCK host: actual Chromium clipboard paste retains browser-provided CRLF source units',async()=>{
 await open(fixture(edit('editing',{raw:'A\rB'})));await call('Browser.grantPermissions',{origin,permissions:['clipboardReadWrite','clipboardSanitizedWrite']});await call('Emulation.setFocusEmulationEnabled',{enabled:true});await evaluate("navigator.clipboard.writeText('X\\r\\nY')");await evaluate("window.pasteSources=[];const el=document.getElementById('raw-name');el.addEventListener('paste',event=>window.pasteSources.push(event.clipboardData.getData('text/plain')));el.focus();el.setSelectionRange(0,0)");await call('Input.dispatchKeyEvent',{type:'keyDown',key:'v',code:'KeyV',windowsVirtualKeyCode:86,modifiers:2});await call('Input.dispatchKeyEvent',{type:'keyUp',key:'v',code:'KeyV',windowsVirtualKeyCode:86,modifiers:2});await requests(1);assert.equal(await evaluate('window.pasteSources[0]'),'X\r\nY','browser clipboard boundary changes CRLF source');assert.equal(actions[0].raw,'X\r\nYA\rB');
});

test('MOCK host: native deletion targets the selected original CRLF among identical displayed newlines',async()=>{
 await open(fixture(edit('editing',{raw:'\r\n\nX'})));await evaluate("document.getElementById('raw-name').focus();document.getElementById('raw-name').setSelectionRange(1,1)");await call('Input.dispatchKeyEvent',{type:'keyDown',key:'Backspace',code:'Backspace',windowsVirtualKeyCode:8});await call('Input.dispatchKeyEvent',{type:'keyUp',key:'Backspace',code:'Backspace',windowsVirtualKeyCode:8});await requests(1);assert.equal(actions[0].raw,'\nX');await call('Input.dispatchKeyEvent',{type:'keyDown',key:'Delete',code:'Delete',windowsVirtualKeyCode:46});await call('Input.dispatchKeyEvent',{type:'keyUp',key:'Delete',code:'Delete',windowsVirtualKeyCode:46});await requests(2);assert.equal(actions[1].raw,'X');
});


test('MOCK host: unchanged editing status is not repeatedly announced during draft acknowledgements',async()=>{
 await open(fixture(edit()));await evaluate("window.statusChanges=0;new MutationObserver(records=>window.statusChanges+=records.length).observe(document.getElementById('editor-status'),{childList:true,characterData:true,subtree:true})");await input('another raw draft');await requests(1);assert.equal(await evaluate('window.statusChanges'),0);
});

test('MOCK host regression: pre-opened discard confirmation blocks cancel after unknown save result',async()=>{
 await open(fixture(edit('prepared',{preview:{normalized_name:'A',candidate_revision:'2'}})));
 await click('cancel');assert.equal(await evaluate("document.getElementById('discard-warning').hidden"),false);
 reply=async(a,res)=>{state.editor.status='unknown';res.setHeader('Content-Type','application/json');res.end(JSON.stringify(state));};
 await click('save');await requests(1);assert.equal(await evaluate("document.getElementById('cancel').disabled"),true);
 const confirmDisabled=await evaluate("document.getElementById('confirm-discard').disabled");
 await click('confirm-discard');await new Promise(r=>setTimeout(r,100));
 console.log('INDEPENDENT discard state',JSON.stringify({confirmDisabled,actions}));
 assert.equal(confirmDisabled,true,'unknown must also disable an already-open discard confirmation');
 assert.deepEqual(actions.map(a=>a.action),['save']);
});
test('MOCK host regression: native undo restores deleted original CRLF units',async()=>{
 await open(fixture(edit('editing',{raw:'A\r\nB'})));
 await evaluate("document.getElementById('raw-name').focus();document.getElementById('raw-name').setSelectionRange(1,2)");
 await call('Input.dispatchKeyEvent',{type:'keyDown',key:'Backspace',code:'Backspace',windowsVirtualKeyCode:8});
 await call('Input.dispatchKeyEvent',{type:'keyUp',key:'Backspace',code:'Backspace',windowsVirtualKeyCode:8});await requests(1);
 await call('Input.dispatchKeyEvent',{type:'keyDown',key:'z',code:'KeyZ',windowsVirtualKeyCode:90,modifiers:2});
 await call('Input.dispatchKeyEvent',{type:'keyUp',key:'z',code:'KeyZ',windowsVirtualKeyCode:90,modifiers:2});await requests(2);
 console.log('INDEPENDENT undo actions',JSON.stringify(actions));assert.equal(actions[1].raw,'A\r\nB');
});

test('MOCK host regression: native redo reuses exact original buffer history after CRLF undo',async()=>{
 await open(fixture(edit('editing',{raw:'A\r\nB\ud800'})));await evaluate("document.getElementById('raw-name').focus();document.getElementById('raw-name').setSelectionRange(1,2)");
 for(const type of ['keyDown','keyUp'])await call('Input.dispatchKeyEvent',{type,key:'Backspace',code:'Backspace',windowsVirtualKeyCode:8});await requests(1);assert.equal(actions[0].raw,'AB\ud800');
 for(const type of ['keyDown','keyUp'])await call('Input.dispatchKeyEvent',{type,key:'z',code:'KeyZ',windowsVirtualKeyCode:90,modifiers:2});await requests(2);assert.equal(actions[1].raw,'A\r\nB\ud800');
 for(const type of ['keyDown','keyUp'])await call('Input.dispatchKeyEvent',{type,key:'y',code:'KeyY',windowsVirtualKeyCode:89,modifiers:2});await requests(3);assert.equal(actions[2].raw,'AB\ud800');
});

test('MOCK host regression: two durable sessions keep mobile detail/editor free of directory at 200% text',async()=>{
 const s=fixture(edit());s.recoverable_sessions=[{session:'mock-session',supplier:'S1',status:'editing'},{session:'other-original-session',supplier:'S2',status:'unknown'}];
 try{
  await call('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});await open(s);await evaluate("document.documentElement.style.fontSize='32px'");
  assert.equal(state.recoverable_sessions.length,2);assert.equal(await evaluate("document.querySelectorAll('#recoverable-sessions button').length"),1);
  assert.equal(await evaluate('document.body.dataset.view'),'editor');assert.equal(await evaluate("getComputedStyle(document.getElementById('directory-search')).display"),'none','mobile full editor must hide directory even with a recovery button');
  await click('back-detail');assert.equal(await evaluate('document.body.dataset.view'),'detail');assert.equal(await evaluate("getComputedStyle(document.getElementById('directory-search')).display"),'none','mobile detail must hide directory even with a recovery button');
  await click('back-list');assert.equal(await evaluate('document.body.dataset.view'),'list');assert.notEqual(await evaluate("getComputedStyle(document.getElementById('directory-search')).display"),'none','mobile list retains directory and original-session recovery');
  await click('supplier-S1');await requests(1);await click('resume-editor');assert.equal(await evaluate('document.body.dataset.view'),'editor');assert.equal(await evaluate("document.getElementById('directory-search').getClientRects().length"),0);
  const layout=await evaluate("({width:innerWidth,scroll:document.documentElement.scrollWidth,rawBottom:document.getElementById('raw-name').getBoundingClientRect().bottom,buttonsTop:document.getElementById('editor-actions').getBoundingClientRect().top})");assert.ok(layout.scroll<=layout.width,JSON.stringify(layout));assert.ok(layout.buttonsTop>=layout.rawBottom,JSON.stringify(layout));
  await evaluate("document.documentElement.style.fontSize=''");await call('Emulation.setDeviceMetricsOverride',{width:1400,height:1000,deviceScaleFactor:1,mobile:false});assert.notEqual(await evaluate("getComputedStyle(document.getElementById('directory-search')).display"),'none','desktop retains directory while editing');assert.ok(await evaluate("document.getElementById('recover-other-original-session').getClientRects().length>0"),'desktop retains recovery control');
 }finally{await evaluate("document.documentElement.style.fontSize=''");await call('Emulation.setDeviceMetricsOverride',{width:1400,height:1000,deviceScaleFactor:1,mobile:false});}
});

test('MOCK host regression: healthy fresh session with no selection/editor shows no transport uncertainty',async()=>{
 const s=fixture();s.selected=null;s.editor=null;await open(s);
 assert.equal(await text('transport-status'),'','valid initial host projection must not manufacture a transport error');assert.match(await text('list-status'),/读取可用/);assert.match(await text('supplier-S1'),/S1/);assert.match(await text('supplier-S2'),/S2/);assert.equal(await text('detail-heading'),'选择供应商');assert.match(await text('selected-identity'),/明确选择 S1 或 S2/);assert.equal(await evaluate("document.getElementById('edit').disabled"),true);assert.equal(await evaluate("document.getElementById('D01.1-NAME-EDITOR').hidden"),true);assert.equal(await evaluate('document.body.dataset.busy'),'false');assert.deepEqual(actions,[]);
});
