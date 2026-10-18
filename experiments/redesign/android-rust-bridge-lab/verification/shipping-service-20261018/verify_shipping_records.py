import json
from pathlib import Path

def load_record(row):
    directory = Path(row[1]) / 'native-agent-service-v1' / row[2]
    record = {name: json.loads((directory / (name + '.db')).read_text()) for name in ['source', 'summary', 'native', 'outbound']}
    record['index'] = json.loads((directory.parent / 'index.db').read_text())
    lines = (directory / 'task.db').read_text().splitlines()
    if lines[0] != 'CORE_TASK_V1': raise ValueError('task_format')
    record['task'] = dict(line.split('\t', 1) for line in lines[1:])
    return record


def require(value, code):
    if not value:
        raise ValueError(code)

# Frozen public fixture mapping, independent of the observed output.
MAPPINGS = {
    'EQUIPMENT': ('equipment_loan', 'equipment', 'e1'),
    'RESEARCH': ('research', 'project', 'p1'),
    'INQUIRY': ('inquiry', 'supplier', 's1'),
    'SEEDED_EQUIPMENT': ('module_f65579dc', 'asset', 'e1'),
}

def verify_record(row, record, source):
    variant, root, run_id, epoch, task_id, attempt_id, receipt_id = row
    summary, native, task, outbound, index = (record[k] for k in ['summary', 'native', 'task', 'outbound', 'index'])
    require(len(index['runs']) == 1, 'one_durable_run')
    run = summary['run']
    require(run == index['runs'][0] and run == dict(actual_task=dict(task_id=task_id, attempt_id=attempt_id),
        admitted_service_epoch=epoch, request_id='read_1', run_id=run_id,
        source_build_identity=source, variant=variant.lower()), 'durable_identity_binding')
    require(summary['terminal'] == 'completed' and summary['reason'] == 'none', 'completed_summary')
    require(summary['receipt'] == dict(opaque_id=receipt_id, outcome='recorded_success'), 'summary_receipt')
    require(all(task.get(k) == v for k, v in dict(task=task_id, attempt=attempt_id, calls='2', steps='2',
        max_calls='2', max_steps='2', status='completed', provider_inflight='false').items()), 'task_identity_budget')
    require(len(native['receipts']) == 1, 'one_original_receipt')
    receipt = native['receipts'][0]
    require(receipt['identity']['identity'] == receipt_id, 'original_receipt_identity')
    require(receipt['binding']['task'] == task_id and receipt['binding']['attempt'] == attempt_id
        and receipt['binding']['scope'] == 'selected-record' and receipt['binding']['turn'] == 1
        and receipt['status'] == 'succeeded', 'original_receipt_binding')
    require(native['facts'] == dict(external_read=True, unknown_source=True), 'physical_read_facts')
    require(receipt['raw'] == record['source'] and record['source']['private_value'] == 'BORROWER_PRIVATE', 'raw_source_preserved')
    require(outbound['status'] == 'sent', 'final_payload_sent')
    body_text = outbound['bytes']
    require('BORROWER_PRIVATE' not in body_text, 'canary_in_payload')
    body = json.loads(body_text)
    require(body['tools'] == [] and body['model'] == 'offline-fixture' and body['stream'] is True, 'second_payload_no_tools')
    messages = body['messages']
    require([m['role'] for m in messages] == ['user', 'assistant', 'tool'] and
        messages[0]['content'] == 'read selected synthetic record', 'second_payload_exact_messages')
    tool = messages[2]
    require(tool['tool_call_id'] == 'service_call1', 'second_payload_call_binding')
    projected = json.loads(tool['content'])
    require(projected['receipt_ref'] == receipt['identity'], 'outbound_original_receipt')
    projection = {k: v for k, v in record['source'].items() if k != 'private_value'}
    require(projected == dict(projection=projection, receipt_ref=receipt['identity']), 'exact_safe_projection')
    module, typ, key = MAPPINGS[variant]
    reference = dict(module_id=module, type=typ, key=key, revision='1', schema_version=1)
    require(receipt['binding']['scope_refs'] == [reference], 'fixture_reference_mapping')
    expected_projection = (dict(objects={typ: [reference]}) if variant in ['RESEARCH', 'INQUIRY']
                           else {typ: reference, 'label': 'synthetic mapped value', 'loans': []})
    require(projection == expected_projection, 'fixture_projection_mapping')

if __name__ == '__main__':
    import argparse, hashlib
    parser = argparse.ArgumentParser(description='Read-only private durable oracle for shipping JVM runs; first payload/counts remain separate Rust-observer scope.')
    parser.add_argument('--runs', type=Path, required=True)
    parser.add_argument('--source', required=True)
    args = parser.parse_args()
    rows = [line.split('\t') for line in args.runs.read_text().splitlines()]
    require(len(rows) == 4 and {row[0] for row in rows} == set(MAPPINGS), 'four_variant_inventory')
    for row in rows:
        verify_record(row, load_record(row), args.source)
        print('SERVICE_DURABLE_ORACLE_PASS variant=' + row[0] + ' run=' + row[2] + ' original_receipt=' + row[6])
    print('SERVICE_DURABLE_ORACLE_ALL_PASS variants=4 actual_first_payload_and_exact_handler_count=NOT_OBSERVED_BY_THIS_ORACLE Android_runtime=NOT_RUN')
