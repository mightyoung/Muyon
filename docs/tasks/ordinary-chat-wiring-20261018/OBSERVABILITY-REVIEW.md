# Independent observability review

Reviewer: independent_review subagent. Base: 09d151a9192660c3e629028803fc626b618044a2.
Reviewed files: ordinary-chat-offline.yml, ordinary_chat_device.sh and
test_ordinary_chat_device_evidence.py, with the existing task restrictions.

Approved with no blocking findings. Original device commands, parameters, order,
two-class selection and result checks are retained. The six phase records bind
the full source SHA, START/PASS/FAIL and exit code; the EXIT trap preserves the
failed command/pipeline status. Preparation failure leaves instrumentation
NOT_RUN; after command invocation failure is NOT_VERIFIED without claiming that
Android started a test. No prohibited old evidence path, I04, real provider or
additional suite is introduced.

Reviewer independently ran only the disposable fake-tool probe: 1 test with
7 subscenarios passed. This approval establishes evidence semantics, not actual
device success. Old CI failure cause and individual test results remain unknown.
