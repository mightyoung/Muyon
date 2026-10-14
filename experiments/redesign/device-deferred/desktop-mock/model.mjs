// PROVISIONAL RustCorePort-shaped seam, not M03 wire/schema or native IPC.
export class SupplierEditor {
  constructor(port) { this.port=port; this.epoch=0; this.sequence=0; this.receiptLedger=new Map(); this.pending=new Map(); this.state={phase:'loading',supplier:null,raw:'',plan:null,receipt:null,intent:null,validation:null}; }
  async load() {
    const epoch=++this.epoch; this.state.phase='loading';
    const supplier=await this.port.read();
    if(epoch===this.epoch) this.state={...this.state,phase:'ready',supplier,plan:null,receipt:null};
  }
  edit() {
    if(['unknown','submitting','loading'].includes(this.state.phase)) return;
    ++this.epoch;
    this.state={...this.state,phase:'draft',raw:this.state.supplier.name,intent:`mock-intent-${++this.sequence}`,plan:null,receipt:null,validation:null};
  }
  draft(raw) {
    if(!['draft','conflict'].includes(this.state.phase)) return;
    ++this.epoch; this.state={...this.state,phase:'draft',raw,plan:null,validation:null};
  }
  async preview() {
    if(this.state.phase!=='draft') return;
    const epoch=this.epoch;
    const result=await this.port.preview({raw:this.state.raw,intent:this.state.intent,supplierId:this.state.supplier.id,expectedRevision:this.state.supplier.revision});
    if(epoch!==this.epoch) return;
    this.state={...this.state,plan:result.kind==='plan'?result:null,validation:result.kind==='plan'?'valid':'invalid'};
  }
  async save() {
    const {intent,plan}=this.state;
    if(this.pending.has(intent)) return this.pending.get(intent);
    if(this.state.phase==='ready' && this.state.receipt) return this.state.receipt;
    if(this.state.phase!=='draft'||!plan) return;
    const epoch=this.epoch; const supplierId=this.state.supplier.id; this.state.phase='submitting';
    const work=(async()=>{
      let result;
      try { result=await this.port.commit(plan); } catch { result={kind:'unknown'}; }
      result=this.account(result,intent,supplierId);
      if(epoch===this.epoch) this.apply(result);
      return result;
    })();
    this.pending.set(intent,work);
    try { return await work; } finally { this.pending.delete(intent); }
  }
  account(result,intent,supplierId) {
    if(result.kind!=='receipt') return result;
    if(result.intent!==intent||result.supplierId!==supplierId||typeof result.id!=='string'||!Number.isSafeInteger(result.revision)||typeof result.name!=='string') return {kind:'unknown'};
    this.receiptLedger.set(result.id,result);return result;
  }
  apply(result) {
    if(result.kind==='receipt') this.state={...this.state,phase:'ready',receipt:result,plan:null,supplier:{...this.state.supplier,name:result.name,revision:result.revision}};
    else this.state={...this.state,phase:result.kind==='conflict'?'conflict':'unknown',current:result.current,receipt:null};
  }
  async lookup() {
    if(this.state.phase!=='unknown') return;
    const epoch=this.epoch;const {intent,supplier}=this.state;
    let result; try {result=await this.port.lookup(this.state.intent);} catch {result={kind:'unreadable'};}
    result=this.account(result,intent,supplier.id);
    if(epoch===this.epoch && result.kind==='receipt') this.apply(result);
  }
}
export class MemoryRustCorePort {
  constructor() { this.record={id:'mock-supplier-0001',name:'示例供应商',revision:1};this.dispatches=0;this.receipts=new Map();this.plans=new Map();this.loseResponse=false; }
  async read(){return {...this.record};}
  async preview(input){
    this.lastRaw=input.raw;
    const raw=input.raw;
    // Mock-only approximation. Exact Rust Unicode/version and authority are unfrozen.
    if(typeof raw!=='string'||raw.length>2000||/[\u0000-\u0008\u000b\u000c\u000e-\u001f\ufffe\uffff]/u.test(raw)||!raw.isWellFormed()) return {kind:'invalid'};
    const normalized=raw.trim().normalize('NFC');
    if(!normalized||[...normalized].length>200) return {kind:'invalid'};
    const plan={...input,normalized,kind:'plan',id:`mock-plan-${input.intent}`};
    this.plans.set(plan.id,plan);return plan;
  }
  async commit(plan){
    if(this.receipts.has(plan.intent)) return this.receipts.get(plan.intent);
    if(this.plans.get(plan.id)!==plan||plan.supplierId!==this.record.id) return {kind:'unknown'};
    this.dispatches++;
    if(plan.expectedRevision!==this.record.revision) return {kind:'conflict',current:{...this.record}};
    this.record={...this.record,name:plan.normalized,revision:this.record.revision+1};
    const receipt={kind:'receipt',id:`mock-receipt-${plan.intent}`,intent:plan.intent,supplierId:this.record.id,name:this.record.name,revision:this.record.revision};
    this.receipts.set(plan.intent,receipt);
    if(this.loseResponse){this.loseResponse=false;throw new Error('synthetic response loss');}
    return receipt;
  }
  async lookup(intent){return this.receipts.get(intent)??{kind:'notFound'};}
}
