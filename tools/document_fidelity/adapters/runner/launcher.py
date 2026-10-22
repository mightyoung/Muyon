"""Complete control flow over an authenticated OS interface; fake OS in tests only."""
from dataclasses import asdict,dataclass
import hashlib
import math
import secrets
from . import model
from .authority import Authority
from .. import runtime,xlsx
from ..protocol import parse_request,IDENTITY_FIELDS


@dataclass(frozen=True)
class TrustedRuntimeBinding:
    authority:Authority
    executor:model.HostOSBackend
    def __post_init__(self):
        if type(self.authority) is not Authority or self.authority.assurance!='host_verified' or not isinstance(self.executor,model.HostOSBackend):
            raise TypeError('trusted_host_bootstrap_required')


class Stop(Exception):
    def __init__(self,status,reason):self.status,self.reason=status,reason


def held(reason='environment_hold'):
    return model.Result(dict(receipt_version=3,status='held',reasons=[reason],assurance='unqualified',
                             engine_execution='not_run',real_roundtrip='not_run',txn_eligible=False,
                             lifecycle=[],fidelity='unknown',safety='unknown'))


def run_production(source,raw,binding=None,executor=None,cancel=None):
    # Normal JSON, old fake receipts and even a mislabeled fake backend cannot
    # create a production binding. Only trusted service bootstrap supplies it.
    if type(binding) is not TrustedRuntimeBinding:return held()
    if executor is not None and executor is not binding.executor:return held('executor_binding_conflict')
    return _run(source,raw,binding.executor,binding.authority,cancel)


def run_simulation(source,raw,executor,authority,cancel=None):
    if type(authority) is not Authority or authority.assurance!='simulation' or getattr(executor,'assurance',None)!='simulation':return held('simulation_binding_required')
    return _run(source,raw,executor,authority,cancel)


def _run(source,raw,executor,authority,cancel):
    policy=authority.policy
    receipt=held().public
    receipt.update(status='received',assurance=authority.assurance,reasons=[],engine=asdict(authority.engine),
                   policy_digest=policy.digest(),txn_eligible=False,dimensions={k:'not_run' for k in ('render','recalc','visual','annotation')})
    attempt='attempt_'+secrets.token_hex(16)
    receipt['attempt_id']=attempt
    workspace=process=lease=plan=terminal=None
    os_touched=spawn_attempted=drained=False
    candidate=None
    last_time=None
    log_counts={'stdout':0,'stderr':0}
    log_hashes={k:hashlib.sha256() for k in log_counts}
    def record(state):receipt['lifecycle'].append(state)
    def clock():
        nonlocal last_time
        value=executor.now_ms()
        if type(value) not in (int,float) or not math.isfinite(value) or value<0 or (last_time is not None and value<last_time):raise Stop('failed','invalid_monotonic_clock')
        last_time=value;return value
    def cancelled():
        if cancel is None:return False
        if not callable(cancel):raise Stop('failed','invalid_cancel_signal')
        value=cancel()
        if type(value) is not bool:raise Stop('failed','invalid_cancel_signal')
        return value
    def drain():
        # True means the backend proves both root reaped and the entire
        # attempt-bound process tree empty, not merely root poll() success.
        nonlocal drained
        try:
            executor.terminate_tree(process);record('terminate_tree')
            if executor.reap_tree(process,policy.grace_ms) is True:
                drained=True;record('reaped');return
        except Exception:
            record('terminate_or_grace_failed')
        executor.kill_tree(process);record('kill_tree')
        if executor.reap_tree(process,policy.grace_ms) is True:
            drained=True;record('reaped');return
        raise Stop('outcome_unknown','process_tree_not_reaped')
    try:
        request=parse_request(raw)
        if type(source) is not bytes or len(source)>policy.max_input_bytes:raise Stop('rejected','input_limit_or_type')
        receipt['request_digest']=model.digest(request)
        receipt['identity']={k:request[k] for k in IDENTITY_FIELDS}
        receipt['source_sha256']=model.sha(source)
        receipt['request_schema_version']=request['schema_version']
        format,module,engine,version,worker=runtime.adapter(request)
        if authority.engine.engine_id!=engine or authority.engine.version!=version:raise Stop('held','engine_binding_conflict')
        start=clock()
        lease=authority.admit(request,receipt['source_sha256'],executor,attempt,start)
        if lease is None or not authority.claim(lease,request,executor,start):raise Stop('held','admission_denied')
        binding=authority.binding(lease)
        receipt['binding_digest']=model.digest(asdict(binding));record('admitted')
        if cancelled():raise Stop('cancelled','cancelled_before_prepare')
        plan=module.prepare(source,request)
        receipt['preview']=plan['preview'];receipt['source_manifest']=plan['source_report']['parts']
        job=model_json(request)
        spec=dict(argv=['/runtime/python3','-I','-B','-m','tools.document_fidelity.adapters.runner.worker_entry','--format',format],
                  format=format,source='/input/source.'+format,candidate='/output/candidate.'+format,
                  job='/job/request.json',input_read_only=True,job_read_only=True,no_network=True,
                  private_output=True,sanitized_environment=True,limits=asdict(policy),
                  engine=asdict(authority.engine),policy_digest=policy.digest(),attempt_id=attempt)
        os_touched=True
        workspace=executor.reserve(attempt,spec,source,job);record('prepared')
        ready=executor.ready(workspace,binding,authority.engine,policy)
        if not authority.approve_ready(lease,ready,executor):raise Stop('failed','sandbox_ready_not_verified')
        record('sandbox_ready_verified')
        if cancelled():raise Stop('cancelled','cancelled_before_spawn')
        now=clock()
        if now>=start+policy.timeout_ms:raise Stop('timed_out','deadline_before_spawn')
        if not authority.check_lease(lease,request,executor,now):raise Stop('held','lease_expired_before_spawn')
        spawn_attempted=True
        process=executor.spawn(workspace,spec,lease)
        if process is None:raise Stop('outcome_unknown','spawn_handle_missing')
        record('spawned')
        if authority.assurance=='host_verified':receipt['engine_execution']='executed';receipt['real_roundtrip']='unknown'
        deadline=start+policy.timeout_ms
        exited=False
        # Finite polls also prevent a broken/nonadvancing fake or OS clock from
        # producing an unbounded busy loop. Real backend must honor poll wait.
        for _ in range(policy.timeout_ms//policy.poll_ms+4):
            now=clock()
            if cancelled():raise Stop('cancelled','cancelled_running')
            if now>=deadline:raise Stop('timed_out','deadline_exceeded')
            output=executor.measure(workspace)
            if type(output) is not model.OutputState or type(output.candidate_bytes) is not int or output.candidate_bytes<0 or output.candidate_bytes>policy.max_candidate_bytes or output.extra_files is not False:raise Stop('failed','running_output_limit_or_shape')
            event=executor.poll(process,min(policy.poll_ms,max(1,int(deadline-now))))
            if clock()>deadline:raise Stop('timed_out','deadline_exceeded')
            if type(event) is not model.Event:raise Stop('failed','invalid_process_event')
            if event.kind in log_counts:
                cap=policy.max_stdout_bytes if event.kind=='stdout' else policy.max_stderr_bytes
                if type(event.data) is not bytes or len(event.data)>policy.max_chunk_bytes or log_counts[event.kind]+len(event.data)>cap:raise Stop('failed','log_limit_exceeded')
                log_counts[event.kind]+=len(event.data);log_hashes[event.kind].update(event.data)
            elif event.kind=='running':
                if event.data!=b'' or event.exit_code is not None:raise Stop('failed','invalid_process_event')
            elif event.kind=='exit':
                if event.data!=b'' or type(event.exit_code) is not int:raise Stop('failed','invalid_exit_event')
                receipt['exit_code']=event.exit_code;record('exited')
                if event.exit_code!=0:raise Stop('failed','nonzero_exit')
                if executor.reap_tree(process,policy.grace_ms) is not True:raise Stop('failed','unexpected_descendants')
                drained=True;record('reaped');exited=True;break
            else:raise Stop('failed','invalid_process_event')
        if not exited:raise Stop('timed_out','poll_budget_exceeded')
        if cancelled():raise Stop('cancelled','cancelled_before_snapshot')
        snapshot=executor.snapshot(workspace,policy)
        if (type(snapshot) is not model.Snapshot or type(snapshot.candidate) is not bytes or not 0<len(snapshot.candidate)<=policy.max_candidate_bytes
                or snapshot.source!=source or type(snapshot.source) is not bytes or snapshot.job!=job or type(snapshot.job) is not bytes
                or snapshot.regular is not True or type(snapshot.link_count) is not int or snapshot.link_count!=1 or snapshot.extra_files is not False):raise Stop('failed','snapshot_invariant_failed')
        if cancelled():raise Stop('cancelled','cancelled_after_snapshot')
        record('snapshot_checked')
        receipt['validation']=xlsx.validate_candidate(plan,snapshot.candidate)
        receipt['candidate_sha256']=model.sha(snapshot.candidate)
        if receipt['validation']['status']!='pass':raise Stop('failed','output_validation_failed')
        if cancelled():raise Stop('cancelled','cancelled_after_validation')
        if clock()>=deadline:raise Stop('timed_out','validation_deadline_exceeded')
        record('validated');candidate=snapshot.candidate
        if authority.assurance=='host_verified':terminal=executor.terminal_proof(process,workspace)
        receipt['status']='simulated_validated' if authority.assurance=='simulation' else 'candidate_validated'
    except Stop as error:
        receipt['status']=error.status;receipt['reasons'].append(error.reason)
    except Exception as error:
        receipt['status']='failed';receipt['reasons'].append('executor_or_validation_error:'+type(error).__name__)
    # Resolve uncertain stage/spawn ownership by attempt identity, never retry.
    if os_touched and (workspace is None or (spawn_attempted and process is None)):
        try:
            state=executor.reconcile(attempt);record('reconciled')
            if type(state) is not model.Reconciliation or state.known is not True:raise Stop('outcome_unknown','reconciliation_unknown')
            workspace,process=state.workspace,state.process
        except Exception:
            receipt['status']='outcome_unknown';receipt['reasons'].append('reconciliation_unknown')
    if process is not None and not drained:
        try:drain()
        except Exception:
            receipt['status']='outcome_unknown';receipt['reasons'].append('process_tree_not_reaped')
    if receipt['status']=='outcome_unknown':
        try:executor.quarantine(attempt,workspace);record('quarantined')
        except Exception:receipt['reasons'].append('quarantine_failed')
        candidate=None
    elif workspace is not None:
        try:executor.cleanup(workspace);record('cleaned')
        except Exception:
            receipt['status']='outcome_unknown';receipt['reasons'].append('cleanup_unknown');candidate=None
            try:executor.quarantine(attempt,workspace);record('quarantined')
            except Exception:receipt['reasons'].append('quarantine_failed')
    receipt['log_bytes']=log_counts
    receipt['log_sha256']={k:v.hexdigest() for k,v in log_hashes.items()}
    receipt['reaped']=drained
    credential=None
    if candidate is not None:
        try:
            if cancelled():raise Stop('cancelled','cancelled_before_release')
            if clock()>=deadline:raise Stop('timed_out','deadline_before_release')
        except Stop as error:
            receipt['status']=error.status;receipt['reasons'].append(error.reason);candidate=None
        except Exception:
            receipt['status']='failed';receipt['reasons'].append('cancel_signal_failed');candidate=None
    if receipt['status']=='candidate_validated':
        prospective={**receipt,'txn_eligible':True}
        try:credential=authority.issue_credential(lease,request,executor,clock(),prospective,receipt['candidate_sha256'],terminal)
        except Exception:credential=None
        if credential is None:
            receipt['status']='failed';receipt['reasons'].append('host_validator_credential_not_issued');candidate=None
        else:
            try:
                if cancelled():raise Stop('cancelled','cancelled_during_terminal_proof')
                if clock()>=deadline:raise Stop('timed_out','deadline_during_terminal_proof')
            except Stop as error:
                receipt['status']=error.status;receipt['reasons'].append(error.reason);candidate=credential=None
            except Exception:
                receipt['status']='failed';receipt['reasons'].append('terminal_release_check_failed');candidate=credential=None
            else:receipt=prospective
    if receipt['status'] not in ('candidate_validated','simulated_validated'):candidate=None
    if lease is not None:authority.finish(lease,keep_credential=credential)
    return model.Result(receipt,credential,candidate)


def model_json(request):
    import json
    return json.dumps(request,sort_keys=True,separators=(',',':'),ensure_ascii=True).encode()
