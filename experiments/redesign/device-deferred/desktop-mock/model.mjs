// PROVISIONAL RustCorePort-shaped seam, not M03 wire/schema or native IPC.
export class SupplierEditor {
  constructor(port) {
    this.port=port;this.epoch=0;this.sequence=0;
    this.receiptLedger=new Map();this.pending=new Map();this.commands=new Map();
    this.unresolved=null;this.isolated=false;
    this.state={phase:'loading',supplier:null,raw:'',plan:null,receipt:null,intent:null,validation:null,unresolvedIntent:null};
  }
  async load() {
    const epoch=++this.epoch;this.state.phase='loading';
    const supplier=await this.port.read();
    if(epoch!==this.epoch) return;
    // Reading a snapshot cannot resolve an already dispatched command.
    const phase=this.unresolved?(this.isolated?'draft':this.pending.has(this.unresolved.intent)?'submitting':'unknown'):'ready';
    this.state={...this.state,phase,supplier,plan:null,receipt:null,unresolvedIntent:this.unresolved?.intent??null};
  }
  beginDraft() {
    ++this.epoch;
    this.state={...this.state,phase:'draft',raw:this.state.supplier.name,intent:`mock-intent-${++this.sequence}`,plan:null,receipt:null,validation:null};
  }
  edit() {
    if(this.unresolved||['unknown','submitting','loading'].includes(this.state.phase)) return;
    this.isolated=false;this.beginDraft();
  }
  isolateUnresolved() {
    if(!this.unresolved||this.state.phase==='loading') return;
    // Explicit projection-only isolation. The original command remains owned;
    // editing a new draft grants no right to dispatch before reconciliation.
    this.isolated=true;this.beginDraft();
  }
  draft(raw) {
    if(!['draft','conflict'].includes(this.state.phase)) return;
    ++this.epoch;this.state={...this.state,phase:'draft',raw,plan:null,validation:null};
  }
  async preview() {
    if(this.state.phase!=='draft') return;
    const epoch=this.epoch;
    const input={raw:this.state.raw,intent:this.state.intent,supplierId:this.state.supplier.id,expectedRevision:this.state.supplier.revision};
    const result=await this.port.preview(input);
    if(epoch!==this.epoch) return;
    const valid=result?.kind==='plan'&&typeof result.id==='string'&&result.id.trim()!==''&&typeof result.normalized==='string'
      &&result.intent===input.intent&&result.supplierId===input.supplierId&&result.raw===input.raw
      &&result.expectedRevision===input.expectedRevision&&Number.isSafeInteger(input.expectedRevision)&&input.expectedRevision>0&&input.expectedRevision<Number.MAX_SAFE_INTEGER;
    this.state={...this.state,plan:valid?Object.freeze({...result}):null,validation:valid?'valid':'invalid'};
  }
  async save() {
    const {intent,plan}=this.state;
    if(this.pending.has(intent)) return this.pending.get(intent);
    if(this.state.phase==='ready'&&this.state.receipt) return this.state.receipt;
    if(this.unresolved||this.commands.has(intent)||this.state.phase!=='draft'||!plan) return;
    const epoch=this.epoch;
    const command=Object.freeze({intent,supplierId:plan.supplierId,planId:plan.id,expectedRevision:plan.expectedRevision,normalized:plan.normalized});
    this.commands.set(intent,command);this.unresolved=command;
    this.state={...this.state,phase:'submitting',unresolvedIntent:intent};
    const work=(async()=>{
      let result;
      try {result=await this.port.commit(plan);} catch {result={kind:'unknown'};}
      result=this.account(result,command);
      if(result.kind==='receipt'||result.kind==='conflict') this.resolve(command);
      if(epoch===this.epoch) this.apply(result);
      else if(!this.isolated) this.state={...this.state,phase:result.kind==='receipt'?'ready':'unknown'};
      return result;
    })();
    this.pending.set(intent,work);
    try {return await work;} finally {this.pending.delete(intent);}
  }
  resolve(command) {
    if(this.unresolved!==command) return;
    this.unresolved=null;this.state={...this.state,unresolvedIntent:null};
  }
  account(result,command) {
    if(!result||typeof result!=='object') return {kind:'unknown'};
    if(result.kind==='conflict') {
      return result.current?.id===command.supplierId&&Number.isSafeInteger(result.current.revision)&&result.current.revision>0?result:{kind:'unknown'};
    }
    if(result.kind!=='receipt') return {kind:'unknown'};
    const prior=this.receiptLedger.get(result.id);
    if(this.commands.get(command.intent)!==command
      ||result.intent!==command.intent||result.supplierId!==command.supplierId||result.planId!==command.planId
      ||result.expectedRevision!==command.expectedRevision||typeof result.id!=='string'||result.id.trim()===''
      ||!Number.isSafeInteger(result.revision)||result.revision!==command.expectedRevision+1||result.name!==command.normalized
      ||(prior&&(prior.intent!==command.intent||prior.planId!==command.planId))) return {kind:'unknown'};
    const receipt=Object.freeze({...result});this.receiptLedger.set(receipt.id,receipt);return receipt;
  }
  apply(result) {
    if(result.kind==='receipt') this.state={...this.state,phase:'ready',receipt:result,plan:null,supplier:{...this.state.supplier,name:result.name,revision:result.revision}};
    else this.state={...this.state,phase:result.kind==='conflict'?'conflict':'unknown',current:result.current,receipt:null};
  }
  async lookup() {
    const command=this.unresolved;
    if(!command||this.pending.has(command.intent)) return;
    const epoch=this.epoch;
    let result;try {result=await this.port.lookup(command.intent);} catch {result={kind:'unknown'};}
    result=this.account(result,command);
    if(result.kind==='receipt') {
      this.resolve(command);
      if(epoch===this.epoch&&!this.isolated) this.apply(result);
    }
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
    const plan=Object.freeze({...input,normalized,kind:'plan',id:`mock-plan-${input.intent}`});
    this.plans.set(plan.id,plan);return plan;
  }
  async commit(plan){
    if(this.receipts.has(plan.intent)) return this.receipts.get(plan.intent);
    const original=this.plans.get(plan.id);
    if(!original||Object.keys(original).some(key=>original[key]!==plan[key])||plan.supplierId!==this.record.id) return {kind:'unknown'};
    this.dispatches++;
    if(plan.expectedRevision!==this.record.revision) return {kind:'conflict',current:{...this.record}};
    this.record={...this.record,name:plan.normalized,revision:this.record.revision+1};
    const receipt={kind:'receipt',id:`mock-receipt-${plan.intent}`,intent:plan.intent,planId:plan.id,expectedRevision:plan.expectedRevision,supplierId:this.record.id,name:this.record.name,revision:this.record.revision};
    this.receipts.set(plan.intent,receipt);
    if(this.loseResponse){this.loseResponse=false;throw new Error('synthetic response loss');}
    return receipt;
  }
  async lookup(intent){return this.receipts.get(intent)??{kind:'notFound'};}
}
