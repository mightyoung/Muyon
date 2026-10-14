#!/usr/bin/env python3
"""Execute three real processes, compare observations, then assert effect properties.

Input fixtures contain commands only. No response table drives any process.
Native/JVM outputs are external artifacts supplied by the trusted test harness.
"""
import argparse
import json
import pathlib
import subprocess


def rust_observe(binary, lab, fixture):
    scenario = json.loads(fixture.read_text())
    seed = lab / 'fixtures' / {'baseline': 'seed.json', 'lost-reply': 'seed-lost-reply.json'}[scenario['seed']]
    seed_data = json.loads(seed.read_text())
    replies = []
    process = subprocess.Popen([str(binary), '--seed', str(seed)], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        for index, step in enumerate(scenario['steps']):
            request = dict(protocol=0, request_id=f'step-{index}', domain=seed_data['domain'],
                           display_epoch=seed_data['display_epoch'])
            request.update(step['request'])
            if 'plan_id_from' in step:
                assert 'plan_id' not in request
                reference = step['plan_id_from']
                assert isinstance(reference, int) and not isinstance(reference, bool) and 0 <= reference < index
                request['plan_id'] = replies[reference]['plan']['id']
            process.stdin.write(json.dumps(request) + '\n')
            process.stdin.flush()
            frame = process.stdout.readline(32770)
            assert frame.endswith('\n') and len(frame.encode('utf-8')) <= 32768
            reply = json.loads(frame)
            assert reply['protocol'] == 0 and reply['request_id'] == request['request_id']
            replies.append(reply)
    finally:
        process.stdin.close()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
            raise
        stderr = process.stderr.read()
        process.stdout.close()
        process.stderr.close()
    assert process.returncode == 0, stderr
    return dict(scenario_id=scenario['scenario_id'], replies=replies)


def properties(observation):
    """Oracle is applied after actual execution; never used by the drivers."""
    r = observation['replies']
    scenario = observation['scenario_id']
    if scenario == 'actual-baseline':
        assert r[2]['kind'] == 'prepared' and r[2]['receipt'] is None
        assert r[3]['kind'] == r[4]['kind'] == 'committed'
        assert r[3]['receipt'] == r[4]['receipt']
        assert r[4]['snapshot']['cursor']['seq'] == '1'
        assert r[5]['kind'] == 'conflict' and r[5]['receipt'] is None
        assert r[7]['receipt']['result_revision'] == '3'
        assert r[8]['receipt'] == r[3]['receipt']
        assert r[9]['snapshot']['cursor']['seq'] == '2'
        assert r[9]['snapshot']['suppliers'][1]['revision'] == '1'
        assert r[10]['kind'] == 'rejected' and r[10]['receipt'] is None
        assert r[11]['snapshot'] == r[9]['snapshot']
        assert r[12]['kind'] == 'rejected' and r[12]['reason'] == 'domain_mismatch'
    elif scenario == 'actual-lost-reply':
        assert r[2]['kind'] == r[3]['kind'] == 'unknown'
        assert r[3]['receipt'] is None and r[3]['snapshot'] is None
        assert r[4]['snapshot']['cursor']['seq'] == '1'
        assert r[5]['kind'] == 'committed' and r[5]['receipt'] == r[6]['receipt']
        assert r[7]['snapshot'] == r[4]['snapshot']
    elif scenario == 'actual-stale-receipt':
        assert r[5]['snapshot']['suppliers'][0]['revision'] == '3'
        assert r[6]['display_admission'] == 'stale'
        assert r[6]['receipt'] == r[2]['receipt']
        assert r[6]['snapshot'] == r[5]['snapshot'] == r[7]['snapshot']
    else:
        raise AssertionError('unrecognized scenario')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--binary', type=pathlib.Path, required=True)
    parser.add_argument('--jvm-jar', type=pathlib.Path, required=True)
    parser.add_argument('--java', default='java')
    parser.add_argument('--node', default='node')
    parser.add_argument('--desktop-driver', type=pathlib.Path)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    args = parser.parse_args()
    lab = pathlib.Path(__file__).resolve().parents[1]
    args.output.mkdir(parents=True, exist_ok=True)
    results = []
    for name in ['baseline', 'lost-reply', 'stale-receipt']:
        fixture = lab / 'fixtures' / f'scenario-{name}.json'
        actual = rust_observe(args.binary, lab, fixture)
        (args.output / f'{name}-rust.json').write_text(json.dumps(actual, ensure_ascii=True, indent=2) + '\n')
        desktop_driver = args.desktop_driver or lab / 'desktop-adapter' / 'driver.mjs'
        for client, command in [('node', [args.node, str(desktop_driver)]),
                                ('jvm', [args.java, '-jar', str(args.jvm_jar)])]:
            output = args.output / f'{name}-{client}.json'
            result = subprocess.run(command + ['--input', str(fixture), '--output', str(output)],
                                    capture_output=True, text=True, timeout=30)
            (args.output / f'{name}-{client}.log').write_text(result.stdout + result.stderr)
            assert result.returncode == 0, (client, result.stdout, result.stderr)
            observed = json.loads(output.read_text())
            assert observed == actual, f'{name}/{client}: actual process observations differ'
            properties(observed)
        properties(actual)
        results.append(dict(scenario=name, replies=len(actual['replies']), actual_equal=True, properties=True))
    (args.output / 'summary.json').write_text(json.dumps(results, indent=2) + '\n')
    print(json.dumps(results))


if __name__ == '__main__':
    main()
