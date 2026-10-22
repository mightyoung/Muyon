"""Fixed reviewed image layout; no PYTHONPATH/site/.pth bootstrap authority."""
PACKAGE_ROOT='/runtime/python-packages'
HOST_CODE="import sys;sys.path.insert(0,sys.argv.pop(1));from tools.document_fidelity.adapters.runner.linux.host_stage import main;main()"
SANDBOX_CODE="import sys;sys.path.insert(0,'/runtime/python-packages');from tools.document_fidelity.adapters.runner.linux.bootstrap import main;raise SystemExit(main())"
