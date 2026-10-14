import {SupplierEditor,MemoryRustCorePort} from './model.mjs';
const port=new MemoryRustCorePort();const editor=new SupplierEditor(port);
const $=id=>document.getElementById(id);
function render(){
 const s=editor.state;
 $('saved').textContent=s.supplier?.name??'读取中';$('row').textContent=`${s.supplier?.name??'读取中'} · 0001`;
 $('row').hidden=!s.supplier?.name.includes($('search').value);
 $('revision').textContent=`revision ${s.supplier?.revision??'—'}`;
 $('raw').value=s.raw;$('raw').disabled=!['draft','conflict'].includes(s.phase);
 $('status').textContent=`${s.phase}${s.receipt?' · mock 已保存（依据回执）':''}`;
 $('diff').textContent=s.plan?`mock 预览规范值：${s.plan.normalized} / expected revision ${s.plan.expectedRevision}`:s.validation==='invalid'?'mock 校验拒绝；raw 未被 UI 加工':'';
 $('conflict').textContent=s.phase==='conflict'?`版本冲突；保留我的输入，当前 mock 值 ${s.current?.name} / revision ${s.current?.revision}`:s.phase==='unknown'?'结果未知；先查原回执，禁止自动重派':'';
 $('receipt').textContent=s.receipt?JSON.stringify(s.receipt,null,2):'暂无回执；点击不代表成功';
 $('edit').disabled=['submitting','unknown','loading'].includes(s.phase);
 $('preview').disabled=s.phase!=='draft';$('save').disabled=s.phase!=='draft'||!s.plan;$('lookup').disabled=s.phase!=='unknown';
}
for(const [id,action] of [['edit',()=>editor.edit()],['preview',()=>editor.preview()],['save',()=>editor.save()],['lookup',()=>editor.lookup()],['loss',()=>{port.loseResponse=true;}],['race',()=>{port.record.revision++;}]]) $(id).addEventListener('click',async()=>{const pending=action();render();await pending;render();});
$('raw').addEventListener('input',()=>{editor.draft($('raw').value);render();});$('search').addEventListener('input',render);
await editor.load();render();
// Browser smoke only, uses real DOM events and the same public buttons.
if(new URL(location.href).searchParams.has('smoke')){
 try{
  $('edit').click();$('raw').value='  桌面测试  ';$('raw').dispatchEvent(new Event('input'));$('preview').click();await new Promise(r=>setTimeout(r,0));$('save').click();await new Promise(r=>setTimeout(r,0));
  if(!$('receipt').textContent.includes('mock-receipt-')||!$('status').textContent.includes('ready')||$('saved').textContent!=='桌面测试') throw new Error('receipt-driven DOM failed');
  document.body.dataset.smoke='passed';
 }catch(e){document.body.dataset.smoke='failed';$('status').textContent=e.message;}
}
