"""Installed worker entry: current default has no trusted bootstrap and stays HOLD.

Future embedding/native IPC must register a reviewed provider before dispatch.
No env/JSON/CLI argument can install that provider; no engine imported by default.
"""
from abc import ABC,abstractmethod
from dataclasses import dataclass
import argparse
import json
from pathlib import Path
from importlib import import_module
from .authority import Capability


@dataclass(frozen=True)
class WorkerInvocation:
    request:dict
    source:Path
    candidate:Path
    permit:Capability


class TrustedWorkerBootstrap(ABC):
    @abstractmethod
    def invocation(self,format):pass

_bootstrap=None


def install_trusted_bootstrap(provider):
    # Trusted application/native bootstrap API, not a model tool or request field.
    global _bootstrap
    if not isinstance(provider,TrustedWorkerBootstrap):raise TypeError('trusted_bootstrap_required')
    if _bootstrap is not None:raise RuntimeError('bootstrap_already_bound')
    _bootstrap=provider


def dispatch(format):
    held=dict(receipt_version=3,status='held',txn_eligible=False,reason='worker_bootstrap_missing')
    if format not in ('xlsx','docx','pptx') or _bootstrap is None:return held
    invocation=_bootstrap.invocation(format)
    if type(invocation) is not WorkerInvocation or type(invocation.permit) is not Capability:return held
    module={'xlsx':'openpyxl_worker','docx':'docx_worker','pptx':'pptx_worker'}[format]
    worker=import_module('tools.document_fidelity.adapters.'+module)
    worker.edit_copy(invocation.request,invocation.source,invocation.candidate,permit=invocation.permit)
    return dict(receipt_version=3,status='output_created',txn_eligible=False,
                reason='independent_terminal_reap_snapshot_validation_still_required')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--format',choices=('xlsx','docx','pptx'),required=True)
    args=parser.parse_args()
    try:result=dispatch(args.format)
    except Exception:result=dict(receipt_version=3,status='failed',txn_eligible=False,reason='worker_gate_or_edit_failed')
    print(json.dumps(result,sort_keys=True))
    return 0 if result['status']=='output_created' else 2

if __name__=='__main__':raise SystemExit(main())
