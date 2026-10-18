"""Owned shipping Service JVM semantic inverses, separate from Android runtime."""
import re

VARIANTS = ['EQUIPMENT', 'RESEARCH', 'INQUIRY', 'SEEDED_EQUIPMENT']


def classify(text, record, marker=None):
    clean = (record['timed_out'] is False and record['forced_owned_group_cleanup'] is False
             and record['live_after_cleanup'] == [])
    if marker is None:
        return (clean and record['exit_code'] == 0
                and re.findall(r'^SERVICE_SHIPPING_PASS variant=(\w+)', text, re.M) == VARIANTS
                and text.count('SERVICE_SHIPPING_ALL_PASS variants=4 Android_ART_Binder_UID_fsync_kill_rebind=NOT_RUN') == 1)
    return (clean and record['exit_code'] == 1
            and re.findall(r'^Exception in thread "main" java.lang.IllegalStateException: SERVICE_SHIPPING_ASSERT:(\w+)$', text, re.M) == [marker]
            and 'could not compile' not in text and 'SERVICE_SHIPPING_ALL_PASS' not in text)


def main():
    import argparse
    import io
    import json
    import os
    from pathlib import Path
    import shutil
    import subprocess
    import tarfile
    from linux_gate import run, sha
    parser = argparse.ArgumentParser()
    for name in ('source-root', 'evidence-dir', 'work-dir', 'probe-jar', 'baseline-lib', 'java', 'jna'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    source = '2fbdc13efd84cabf04623775f87e762cd0d08c11'
    evidence, work = args.evidence_dir.resolve(), args.work_dir.resolve()
    evidence.mkdir(parents=True); work.mkdir(parents=True)
    if sha(args.probe_jar) != 'd65fba134461a44be8d35652cf8c12d346deb8c129e1373415eadc4165afcfb9':
        raise RuntimeError('frozen_probe_jar')
    if sha(args.baseline_lib) != '15d520efc06323709e2bbdcb6b8bf82bf214ac90520b5c936cc0ca8b4ebac8c1':
        raise RuntimeError('exact_2f_shipping_library')
    roots = ['experiments/redesign/' + name for name in (
        'core-agent-lab', 'plugin-contract-lab', 'rust-agent-host-lab', 'android-rust-bridge-lab')]
    archive = subprocess.check_output(['git', 'archive', source, *roots], cwd=args.source_root)
    copy = work / 'source'; copy.mkdir()
    with tarfile.open(fileobj=io.BytesIO(archive)) as bundle:
        bundle.extractall(copy, filter='data')
    relative = Path('experiments/redesign/rust-agent-host-lab/core/src/service_controller.rs')
    original = (copy / relative).read_text()
    mutants = [
        ('dedup', '.find(|s| intent_of(s).request_id == req.request_id)', '.find(|s| false && intent_of(s).request_id == req.request_id)', 'duplicate_is_existing'),
        ('epoch', 'if r.expected_service_epoch != self.meta.service_epoch {', 'if false && r.expected_service_epoch != self.meta.service_epoch {', 'stale_epoch_rejected'),
        ('join_slot', 'if PROCESS_OCCUPIED\n            .compare_exchange', 'if false && PROCESS_OCCUPIED\n            .compare_exchange', 'slot_held_until_join'),
    ]
    env = dict(os.environ, MUYON_BRIDGE_BUILD_ID=source, CARGO_TARGET_DIR=str(work / 'target'), CARGO_INCREMENTAL='0')
    crate = copy / roots[-1] / 'core'
    rows = []
    for name, before, after, marker in mutants:
        item = evidence / name; item.mkdir()
        def probe(library, label):
            fixture = item / (label + '-fixture'); fixture.mkdir()
            log = item / (label + '.log')
            run([args.java, '-cp', str(args.probe_jar) + ':' + str(args.jna),
                 'muyon.shippingverification.ShippingServiceProbe', source, library, fixture],
                log, env, cwd=copy, timeout=120, required=False)
            record = json.loads(log.with_suffix('.log.json').read_text())
            return classify(log.read_text(), record, marker if label == 'mutant' else None), record
        baseline, baseline_record = probe(args.baseline_lib, 'baseline')
        if not baseline:
            raise RuntimeError('baseline_invalid:' + name)
        if original.count(before) != 1:
            raise RuntimeError('mutation_anchor:' + name)
        (copy / relative).write_text(original.replace(before, after))
        run(['cargo', 'build', '--offline', '--locked', '--release', '--lib'], item / 'build.log', env, cwd=crate, timeout=600)
        library = item / 'libmuyon_android_contract_bridge.so'
        shutil.copyfile(work / 'target/release' / library.name, library)
        killed, mutant_record = probe(library, 'mutant')
        rows.append(dict(name=name, marker=marker, baseline_green=baseline, compiled=True,
                         mutation_killed=killed, mutation_source_sha256=sha(copy / relative),
                         mutant_library_sha256=sha(library), baseline=baseline_record, mutant=mutant_record))
        (evidence / 'summary.json').write_text(json.dumps(dict(source_sha=source, rows=rows,
            Android_runtime='NOT_RUN', accepted=len(rows) == 3 and all(r['mutation_killed'] for r in rows)), indent=2) + '\n')
        if not killed:
            raise RuntimeError('semantic_inverse_invalid:' + name)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
