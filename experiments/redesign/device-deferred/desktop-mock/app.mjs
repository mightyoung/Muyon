import {SupplierEditor,MemoryRustCorePort} from './model.mjs';
const port=new MemoryRustCorePort();const editor=new SupplierEditor(port);
const $=id=>document.getElementById(id);
function render(){
 const s=editor.state;
 $('saved').textContent=s.supplier?.name??'读取中';$('row').textContent=`${s.supplier?.name??'读取中'} · 0001`;
 $('row').hidden=!s.supplier?.name.includes($('search').value);
 $('revision').textContent=`revision ${s.supplier?.revision??'—'}`;
 $('raw').value=s.raw;$('raw').disabled=!['draft','conflict'].includes(s.phase);
 $('status').textContent=`${s.phase}${s.unresolvedIntent?' · 原意图待核；新草稿不能派发':''}${s.receipt?' · mock 已保存（依据回执）':''}`;
 $('diff').textContent=s.plan?`mock 预览规范值：${s.plan.normalized} / expected revision ${s.plan.expectedRevision}`:s.validation==='invalid'?'mock 校验拒绝；raw 未被 UI 加工':'';
 $('conflict').textContent=s.phase==='conflict'?`版本冲突；保留我的输入，当前 mock 值 ${s.current?.name} / revision ${s.current?.revision}`:s.phase==='unknown'?'结果未知；先查原回执，禁止自动重派':'';
 $('receipt').textContent=s.receipt?JSON.stringify(s.receipt,null,2):'暂无回执；点击不代表成功';
 $('edit').disabled=Boolean(s.unresolvedIntent)||['submitting','unknown','loading'].includes(s.phase);$('isolate').disabled=!s.unresolvedIntent||s.phase==='loading';
 $('preview').disabled=s.phase!=='draft';$('save').disabled=Boolean(s.unresolvedIntent)||s.phase!=='draft'||!s.plan;$('lookup').disabled=!s.unresolvedIntent||s.phase==='submitting'||s.phase==='loading';
}
for(const [id,action] of [['edit',()=>editor.edit()],['reload',()=>editor.load()],['isolate',()=>editor.isolateUnresolved()],['preview',()=>editor.preview()],['save',()=>editor.save()],['lookup',()=>editor.lookup()],['loss',()=>{port.loseResponse=true;}],['race',()=>{port.record.revision++;}]]) $(id).addEventListener('click',async()=>{const pending=action();render();await pending;render();});
$('raw').addEventListener('input',()=>{editor.draft($('raw').value);render();});$('search').addEventListener('input',render);
await editor.load();render();
// Browser smoke only, uses real DOM events and the same public buttons.
if(new URL(location.href).searchParams.has('smoke')){
 try{
  $('edit').click();$('raw').value='  桌面测试  ';$('raw').dispatchEvent(new Event('input'));$('preview').click();await new Promise(r=>setTimeout(r,0));$('save').click();await new Promise(r=>setTimeout(r,0));
  if(!$('receipt').textContent.includes('mock-receipt-')||!$('status').textContent.includes('ready')||$('saved').textContent!=='桌面测试') throw new Error('receipt-driven DOM failed');
  $('edit').click();$('loss').click();$('preview').click();await new Promise(r=>setTimeout(r,0));$('save').click();await new Promise(r=>setTimeout(r,0));
  const original=editor.state.intent;$('reload').click();await new Promise(r=>setTimeout(r,0));$('edit').click();
  if(editor.state.phase!=='unknown'||editor.state.intent!==original||port.dispatches!==2||!$('save').disabled) throw new Error('unknown reload DOM failed');
  $('lookup').click();await new Promise(r=>setTimeout(r,0));
  if(editor.state.phase!=='ready'||editor.state.receipt.intent!==original||port.dispatches!==2) throw new Error('original receipt DOM failed');
  document.body.dataset.smoke='passed';
 }catch(e){document.body.dataset.smoke='failed';$('status').textContent=e.message;}
}
