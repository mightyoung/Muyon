// Projection renderer only. Rust/host own normalization, revisions, bindings and receipts.
const $ = id => document.getElementById(id);
const statuses = new Set(['editing','prepared','saving','saved','conflict','unknown','rejected','unavailable']);
const sessionKey = 'rd-p08-session';
let projection = null;
let session = sessionStorage.getItem(sessionKey);
let busy = false;
let busyKind = null;
let uncertain = false;
let raw = null;
let rawVersion = 0;
let persistedVersion = 0;
let draftIntent = null;
let draftDrain = null;
let queue = Promise.resolve();
let inputSnapshot = null;
let pastedRaw = null;
const active = new Set();
const record = r => r && typeof r.supplier === 'string' && typeof r.name === 'string' && typeof r.revision === 'string';
function originalReceipt(r, editor) {
  // Shape checking is defensive rendering, not independent receipt verification.
  return r && ['intent','binding_sha256','source','supplier','old_name','new_name','old_revision','new_revision'].every(k => typeof r[k] === 'string') && r.intent === editor.intent && r.supplier === editor.supplier && r.binding && ['domain','scope','supplier','intent','operation','expected_revision','plan','candidate'].every(k => typeof r.binding[k] === 'string') && Array.isArray(r.binding.raw_utf16);
}
function validProjection(p) {
  if (!p || !Array.isArray(p.suppliers) || !p.suppliers.every(record) || (p.selected !== null && !record(p.selected)) || typeof p.csrf !== 'string' || !p.csrf || typeof p.session !== 'string' || !p.session || typeof p.capability !== 'string' || !['available','partial','unavailable'].includes(p.list_status)) return false;
  const e = p.editor;
  return e === null || (e && statuses.has(e.status) && ['intent','supplier','raw','expected_revision'].every(k => typeof e[k] === 'string') && (e.current === null || record(e.current)) && (e.preview === null || (typeof e.preview?.normalized_name === 'string' && typeof e.preview.candidate_revision === 'string')) && (e.receipt === null || originalReceipt(e.receipt,e)) && (e.status !== 'saved' || originalReceipt(e.receipt,e)));
}
function message(text) { $('transport-status').textContent = text; }
function setBusy(value, kind=null) { busy=value;busyKind=kind;document.body.dataset.busy=String(value);renderControls(); }
function enqueue(work, kind='action') {
  const pending = queue.then(async()=>{setBusy(true,kind);try{return await work();}catch{uncertain=true;message('通信结果未核实或宿主投影无效。保留原输入；刷新读取或核对原结果，不自动重做保存。');}finally{setBusy(false);}});
  queue=pending.catch(()=>{});return pending;
}
async function request(action) {
  const headers={Accept:'application/json'};
  if(session)headers['X-RD-P08-Session']=session;
  if(action){headers['Content-Type']='application/json';headers['X-RD-P08-CSRF']=projection.csrf;}
  const response=await fetch(action?'/api/action':'/api/state',{method:action?'POST':'GET',headers,body:action?JSON.stringify(action):undefined,credentials:'same-origin',cache:'no-store'});
  if(!response.ok)throw Error('host unavailable');
  const next=await response.json();
  if(!validProjection(next) || session && next.session!==session)throw Error('invalid host projection');
  session=next.session;sessionStorage.setItem(sessionKey,session);
  projection=next;uncertain=false;message('');
  const editor=next.editor;
  if(editor?.intent!==draftIntent){draftIntent=editor?.intent??null;raw=editor?.raw??null;rawVersion=0;persistedVersion=0;}
  else if(rawVersion===persistedVersion){raw=editor?.raw??null;}
  render();return next;
}
async function persistDraft() {
  while(rawVersion>persistedVersion){
    const version=rawVersion;const value=raw;
    // Retain the newer buffer while an older host projection is in flight.
    await request({action:'draft',raw:value});persistedVersion=version;
    if(rawVersion===version && projection.editor?.intent===draftIntent)raw=projection.editor.raw;
  }
  render();
}
function drainDraft() {
  if(draftDrain)return draftDrain;
  draftDrain=enqueue(persistDraft,'draft').finally(()=>{draftDrain=null;});return draftDrain;
}
function action(name, fields={}) {
  if(active.has(name))return;
  active.add(name);
  const pending=enqueue(async()=>{
    // A previous transport failure can leave a retained buffer after refresh.
    // This explicit action persists it before asking Rust to preview/save.
    if(name==='preview'||name==='save')await persistDraft();
    if(name==='save')message('保存请求进行中 · 等待宿主核验原结果');
    await request({action:name,...fields});
    if(name==='select'){document.body.dataset.view='detail';$('D01.1-DETAIL').focus({preventScroll:true});}
    if(name==='edit'){document.body.dataset.view='editor';$('raw-name').focus();}
    if(name==='cancel'){$('discard-warning').hidden=true;document.body.dataset.view='detail';$('edit').focus();}
  });
  pending.finally(()=>{active.delete(name);renderControls();});
}
function statusLabel(e) {
  if(e.reason==='binding_conflict')return '意图绑定冲突 · 结果未知，保留原绑定并仅核对原结果';
  if(e.status==='unavailable'&&e.reason==='preview_unavailable')return '预览暂不可用 · 尚未派发；保留输入，可编辑、重新预览或取消';
  if(e.status==='rejected'&&e.reason==='Revision'||e.status==='conflict'&&e.reason==='Revision')return '版本冲突：原输入与原预期版本已保留。请先核对当前值；不会自动覆盖。';
  return ({editing:'编辑中 · 尚未保存',prepared:'Rust 预览校验通过 · 尚未保存',saving:'保存中 · 等待真实提交结果',saved:'已保存 · 宿主已核验原始 P07 提交回执',conflict:'意图绑定冲突 · 原绑定不能替换，请核对原结果',unknown:'结果未知 · 仅核对原结果，不创建新意图',rejected:`未提交 · Rust 拒绝：${e.reason??'未提供原因'}`,unavailable:'当前不可用 · 输入保留，尚未核实结果'})[e.status];
}
function renderControls() {
  const e=projection?.editor;
  const blocked=busy||uncertain;
  const writable=e&&['editing','prepared','rejected','unavailable'].includes(e.status);
  $('edit').disabled=blocked||!projection?.selected||!!e;
  $('raw-name').readOnly=!writable||uncertain||(busy&&busyKind==='action');
  $('preview').disabled=(busy&&busyKind!=='draft')||uncertain||!writable;
  $('save').disabled=blocked||e?.status!=='prepared'||rawVersion!==persistedVersion;
  $('cancel').disabled=blocked||!e||['unknown','saving'].includes(e.status);
  $('lookup').disabled=busy||!e||!['unknown','saving','saved','conflict'].includes(e.status)&&!uncertain;
  $('refresh').disabled=busy;
  $('resume-editor').hidden=!e;$('resume-editor').disabled=busy;
  for(const button of $('recoverable-sessions').querySelectorAll('button'))button.disabled=busy||!!e;
  $('confirm-discard').disabled=busy||uncertain;
  $('draft-status').textContent=rawVersion>persistedVersion?'本机缓冲尚未获宿主持久化确认。':'草稿内容来自宿主投影；输入只修改草稿。';
}
function renderList() {
  const search=$('supplier-search').value.toLocaleLowerCase();
  const shown=(projection?.suppliers??[]).filter(r=>r.name.toLocaleLowerCase().includes(search)||r.supplier.toLocaleLowerCase().includes(search));
  $('supplier-list').replaceChildren();
  for(const r of shown){
    const item=document.createElement('li'),button=document.createElement('button'),name=document.createElement('strong'),meta=document.createElement('span');
    button.type='button';button.id=`supplier-${r.supplier}`;button.className='supplier-row';button.setAttribute('aria-current',String(projection.selected?.supplier===r.supplier));name.textContent=r.name;meta.textContent=`ID ${r.supplier} · revision ${r.revision}`;button.append(name,meta);button.addEventListener('click',()=>action('select',{supplier:r.supplier}));item.append(button);$('supplier-list').append(item);
  }
  if(!shown.length){const li=document.createElement('li');li.textContent='没有可显示的供应商。';$('supplier-list').append(li);}
  $('list-count').textContent=`${shown.length} 项`;
}
function renderRecovery() {
  $('recoverable-sessions').replaceChildren();
  for(const s of projection.recoverable_sessions??[]){
    if(typeof s?.session!=='string'||!s.supplier||s.session===session)continue;
    const button=document.createElement('button');button.type='button';button.id=`recover-${s.session}`;button.textContent=`恢复 ${s.supplier} · ${s.status??'原会话'}`;
    button.addEventListener('click',()=>{if(busy||projection.editor)return;session=s.session;sessionStorage.setItem(sessionKey,session);enqueue(async()=>{await request();document.body.dataset.view=projection.editor?'editor':'detail';});});$('recoverable-sessions').append(button);
  }
  if(!$('recoverable-sessions').children.length)$('recoverable-sessions').textContent='没有其他待恢复会话。';
}
function render() {
  if(!projection)return;
  $('capability').textContent=projection.capability;
  $('list-status').textContent=({available:'当前列表读取可用',partial:'列表部分可用：缺失对象未以示例替代',unavailable:'列表不可用：等待实际读取'})[projection.list_status];renderList();renderRecovery();
  const selected=projection.selected,e=projection.editor;
  $('detail-heading').textContent=selected?'供应商详情':'选择供应商';
  $('selected-identity').textContent=selected?`稳定 ID ${selected.supplier}`:'在列表中明确选择 S1 或 S2';
  const current=e?.supplier===selected?.supplier?e.current:selected;
  $('current-name').textContent=current?.name??'当前保存值未读取';$('current-revision').textContent=current?`revision ${current.revision}`:'当前版本不可用';
  $('D01.1-NAME-EDITOR').hidden=!e;
  if(e){
    $('editor-identity').textContent=`编辑对象 ${e.supplier}${e.supplier!==selected?.supplier?' · 与当前选择不同，原编辑仍保留':''}`;
    const label=statusLabel(e);
    if($('editor-status').textContent!==label)$('editor-status').textContent=label;
    $('editor-status').dataset.state=e.status;
    $('intent').textContent=e.intent;$('expected-revision').textContent=e.expected_revision;
    if($('raw-name').value!==displayRaw(raw))$('raw-name').value=raw;
    $('editor-current').textContent=e.current?`${e.current.name}\nID ${e.current.supplier} · revision ${e.current.revision}`:'当前行读取不可用';
    $('preview-name').textContent=e.preview?.normalized_name??'尚无 Rust 预览';$('preview-revision').textContent=e.preview?`候选 revision ${e.preview.candidate_revision} · 预期 revision ${e.expected_revision}`:'输入变更后须重新预览；不替换原预期版本。';
    $('receipt-status').textContent=e.receipt?'宿主返回的原始历史回执如下。':'尚无已核验原始回执；不能据点击或传输确认声称已保存。';
    $('receipt-details').hidden=!e.receipt;$('receipt-json').textContent=e.receipt?JSON.stringify(e.receipt,null,2):'';
  }
  renderControls();
}
$('supplier-search').addEventListener('input',renderList);
// HTML textarea displays CR and CRLF as LF. Keep a separate exact UTF16
// buffer and map display offsets into it; never apply name normalization here.
function displayRaw(value) { return (value??'').replace(/\r\n?/g,'\n'); }
function rawOffset(value, displayOffset) {
  let i=0;
  for(let displayed=0;displayed<displayOffset&&i<value.length;displayed++){
    i+=value[i]==='\r'&&value[i+1]==='\n'?2:1;
  }
  return i;
}
function inputRaw(nextDisplay) {
  const original=raw??'',previous=displayRaw(original);
  let start=0,end=previous.length,inserted=null;
  const captured=inputSnapshot;
  if(captured?.original===original){
    start=captured.start;end=captured.end;
    if(captured.data!==null&&nextDisplay===previous.slice(0,start)+displayRaw(captured.data)+previous.slice(end))inserted=captured.data;
    else if(captured.type.startsWith('delete')){
      if(start===end){
        const removed=previous.length-nextDisplay.length;
        if(captured.type.endsWith('Backward'))start=Math.max(0,start-removed);
        else end=Math.min(previous.length,end+removed);
      }
      if(nextDisplay===previous.slice(0,start)+previous.slice(end))inserted='';
    }
  }
  if(inserted===null){
    start=0;
    while(start<previous.length&&start<nextDisplay.length&&previous[start]===nextDisplay[start])start++;
    let suffix=0;
    while(suffix<previous.length-start&&suffix<nextDisplay.length-start&&previous[previous.length-1-suffix]===nextDisplay[nextDisplay.length-1-suffix])suffix++;
    end=previous.length-suffix;inserted=nextDisplay.slice(start,nextDisplay.length-suffix);
  }
  inputSnapshot=null;pastedRaw=null;
  return original.slice(0,rawOffset(original,start))+inserted+original.slice(rawOffset(original,end));
}
$('raw-name').addEventListener('paste',event=>{pastedRaw=event.clipboardData?.getData('text/plain')??null;});
$('raw-name').addEventListener('beforeinput',event=>{
  const el=$('raw-name');
  inputSnapshot={original:raw,start:el.selectionStart,end:el.selectionEnd,type:event.inputType,data:event.data??(event.inputType==='insertFromPaste'?pastedRaw:null)};
});
$('raw-name').addEventListener('input',()=>{raw=inputRaw($('raw-name').value);rawVersion++;$('discard-warning').hidden=true;renderControls();drainDraft();});
$('edit').addEventListener('click',()=>action('edit'));
$('preview').addEventListener('click',()=>action('preview'));
$('save').addEventListener('click',()=>action('save'));
$('lookup').addEventListener('click',()=>action('lookup'));
$('refresh').addEventListener('click',()=>enqueue(()=>request()));
$('cancel').addEventListener('click',()=>{if(projection.editor?.status==='saved'){action('cancel');return;}$('discard-warning').hidden=false;$('keep-draft').focus();});
$('keep-draft').addEventListener('click',()=>{$('discard-warning').hidden=true;$('cancel').focus();});
$('confirm-discard').addEventListener('click',()=>action('cancel'));
$('back-list').addEventListener('click',()=>{document.body.dataset.view='list';$(`supplier-${projection?.selected?.supplier}`)?.focus();});
$('back-detail').addEventListener('click',()=>{document.body.dataset.view='detail';$('D01.1-DETAIL').focus();});
// Returning from mobile detail never creates/replaces an existing intent.
$('resume-editor').addEventListener('click',()=>{document.body.dataset.view='editor';$('raw-name').focus();});
enqueue(async()=>{await request();if(projection.editor)document.body.dataset.view='editor';});
