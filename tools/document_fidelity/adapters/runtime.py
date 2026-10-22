"""Inert real boundary plus explicitly fake-only protocol/oracle simulation."""
import json
import math
import os
from pathlib import Path
import stat
import tempfile
import time

from .protocol import IDENTITY_FIELDS, LIMITS, parse_request
from . import xlsx,docx,pptx


def base_report():
    return dict(schema_version=1, status='held', reasons=[], engine_execution='not_run',
                real_roundtrip='not_run', fake_executor_used=False, fidelity='unknown', safety='unknown',
                dimensions={key:'not_run' for key in ('render','recalc','visual','annotation')})


def adapter(raw):
    request=parse_request(raw)
    return {'set_numeric_cell':('xlsx',xlsx,'openpyxl','3.1.5','openpyxl_worker.py'),
            'replace_docx_run_text':('docx',docx,'python-docx','1.2.0','docx_worker.py'),
            'replace_pptx_shape_text':('pptx',pptx,'python-pptx','1.0.2','pptx_worker.py')}[request['operation']['kind']]


def preview_target(source,raw):
    try:return adapter(raw)[1].preview(source,raw)
    except (ValueError,KeyError,TypeError):return dict(status='unsupported',reasons=['invalid_request'])


def build_launch_spec(raw):
    format,module,engine,version,worker=adapter(raw)
    return dict(argv=['/runtime/python3','-I','/adapter/'+worker,'--request','/job/request.json'],
                engine_id=engine,engine_version=version,format=format,input='/input/source.'+format,
                candidate='/output/candidate.'+format,input_read_only=True,network=False,
                sanitized_environment=True,limits=dict(LIMITS),actual_launcher_available=False,
                artifact_and_worker_hash_verification='required_by_future_host',current_environment='hold')


def run_real(source, raw, admission=None):
    """Cannot launch, even with caller-forged pass flags; admission is diagnostic only."""
    result = base_report()
    result['reasons'] = ['environment_hold', 'real_executor_not_implemented']
    if type(admission) is not dict or not admission or any(admission.get(key) != 'pass' for key in ('license','provenance','isolation','resources')):
        result['reasons'].append('admission_missing')
    try:
        request = parse_request(raw)
        result['schema_version'] = request['schema_version']
        result['identity'] = {key:request[key] for key in IDENTITY_FIELDS}
    except ValueError:
        result['reasons'].append('invalid_request')
    return result


def read_regular(path, limit):
    # Reject symlinks/FIFOs before read, and do not follow any final-component link.
    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
    with os.fdopen(fd, 'rb') as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_size > limit:
            raise ValueError('non_regular_linked_or_oversize_output')
        data = stream.read(limit+1)
        if len(data) > limit or len(data) != info.st_size:
            raise ValueError('output_size_changed')
        return data


def simulate_for_tests(source, raw, fake_executor):
    """Runs caller-supplied *test code* against temporary synthetic copies only.

    This is not a sandbox for arbitrary executors and cannot be called by model tools.
    Real runtime never dispatches to this function. Time limits are protocol checks,
    not hard cancellation of a Python callback. No candidate is published or retained.
    """
    result = base_report()
    result['fake_executor_used'] = True
    result['status'] = 'rejected'
    if getattr(fake_executor, 'kind', None) != 'fake_executor':
        result['reasons'] = ['explicit_fake_executor_required']
        return result
    try:
        format,module,engine,version,worker = adapter(raw)
        result['preview'] = module.preview(source,raw)
        plan = module.prepare(source, raw)
    except (ValueError, KeyError, TypeError):
        result['reasons'] = ['request_or_preflight_or_precondition_rejected']
        return result
    request = plan['request']
    result['schema_version'] = request['schema_version']
    result['identity'] = {key:request[key] for key in IDENTITY_FIELDS}
    result['source_sha256'] = xlsx.sha(source)
    result['source_manifest'] = plan['source_report']['parts']
    result['status'] = 'simulation_failed'
    try:
        with tempfile.TemporaryDirectory(prefix='document-adapter-FAKE-ONLY-') as tmp:
            root = Path(tmp)
            (root/'input').mkdir(mode=0o700)
            (root/'output').mkdir(mode=0o700)
            original, candidate, job = root/('input/source.'+format), root/('output/candidate.'+format), root/'request.json'
            with original.open('xb') as stream:
                stream.write(source)
            original.chmod(0o400)
            job_bytes = json.dumps(request, sort_keys=True).encode('utf-8')
            job.write_bytes(job_bytes)
            job.chmod(0o400)
            started = time.monotonic()
            outcome = fake_executor.execute(build_launch_spec(request), original, candidate, job)
            observed_ms = (time.monotonic()-started)*1000
            if read_regular(job, LIMITS['max_log_bytes']) != job_bytes:
                raise ValueError('readonly_job_changed')
            if read_regular(original, LIMITS['max_input_bytes']) != source:
                raise ValueError('readonly_source_snapshot_changed')
            if (type(outcome) is not dict or set(outcome) != {'status','exit_code','elapsed_ms','stdout','stderr'}
                    or type(outcome['elapsed_ms']) not in (int,float)
                    or not math.isfinite(outcome['elapsed_ms']) or outcome['elapsed_ms'] < 0):
                raise ValueError('invalid_fake_outcome')
            if (outcome['status'] == 'timeout' or outcome['elapsed_ms'] > LIMITS['timeout_ms']
                    or observed_ms > LIMITS['timeout_ms']):
                raise ValueError('timeout')
            if outcome['status'] != 'exited' or type(outcome['exit_code']) is not int or outcome['exit_code'] != 0:
                raise ValueError('nonzero_or_unknown_exit')
            for key in ('stdout','stderr'):
                if type(outcome[key]) is not bytes or len(outcome[key]) > LIMITS['max_log_bytes']:
                    raise ValueError('log_limit')
            if list((root/'output').iterdir()) != [candidate]:
                raise ValueError('missing_or_extra_output')
            payload = read_regular(candidate, LIMITS['max_candidate_bytes'])
            result['validation'] = xlsx.validate_candidate(plan, payload)
            result['candidate_sha256'] = xlsx.sha(payload)
            if result['validation']['status'] == 'pass':
                result['status'] = 'simulated_validated'
            else:
                result['reasons'] = ['output_validation_failed']
    except Exception as exc:
        result['reasons'] = [str(exc) if isinstance(exc, ValueError) else type(exc).__name__]
    result['temporary_candidate_cleaned'] = True
    result['hard_timeout_enforced'] = False
    return result
