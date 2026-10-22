# Independent Core Agent inputs

Synthetic provider event files and independent policy/physical-effect assertions
were authored before reading Rust implementation. Only public CONTRACT/CLI
interface requirements informed this pack. The TSV scripts contain input events,
never expected results, case IDs or authority fields. The JSON fixture manifest
is consumed by the independent checker after actual process output is obtained;
it is never supplied to the Rust provider or kernel.

Fourteen scripts cover a real tool request then answer, duplicate/changed provider
call correlation, unknown tools, forged approval fields and text, explicit failure,
malformed hex/UTF8, context roles, and multiple invocations. All values are opaque
synthetic text. `context-roles.tsv` uses the documented `{{tool_result}}` provider
substitution; the checker compares its actual answer to the independently read
physical receipt/value, never to a fabricated result table.

`independent-cases.json` describes sixteen independent semantic expectations;
additional restart/cancel/budget/fault cases live in checks/process.py. Mode names
in this manifest are checker labels translated to documented trusted CLI flags.
Provider arguments never set mode/scope/risk/confirmation or process flags.

Initial and final pre-DUT fixture checksums are retained outside Git. No old
supplier, classification, recovery, P08, real-model or native evidence is modified
or counted as this laboratory's execution proof.
