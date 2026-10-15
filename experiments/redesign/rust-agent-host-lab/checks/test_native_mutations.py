"""Synthetic classifier/real watchdog controls only; never Rust DUT evidence."""
import copy
import ctypes
from pathlib import Path
import sys
import tempfile
import unittest
from native_mutations import FILTERED, MUTANTS, oracle, run


def transcript(contract, mutant):
    status = 'FAILED' if mutant else 'ok'
    raw = 'Finished `test` profile [unoptimized]\nRunning tests/native_inverse.rs (target/debug/deps/test)\n'
    if contract.get('reach'):
        raw += contract['reach'] + '\n'
    if mutant:
        raw += (f"thread '{contract['test']}' panicked at tests/native_read.rs:1:1:\n"
                f"assertion `left == right` failed: {contract['marker']}\n"
                f"  left: {contract['left']}\n right: {contract['right']}\n")
    return (raw + f"test {contract['test']} ... {status}\n"
            f"test result: {status}. {0 if mutant else 1} passed; {1 if mutant else 0} failed; 0 ignored; 0 measured; {FILTERED} filtered out;\n")


def result(mutant):
    return dict(returncode=101 if mutant else 0, timeout=False,
                cleanup=dict(all_reaped=True, natural=True, forced=False))


class NativeMutationTests(unittest.TestCase):
    def test_exact_target_assertions_and_baseline(self):
        for contract in MUTANTS:
            for mutant in [False, True]:
                self.assertTrue(oracle(transcript(contract, mutant), result(mutant), contract, mutant))

    def test_numeric_thread_id_matches_actual_new_rust_panic_format(self):
        for contract in MUTANTS:
            raw = transcript(contract, True)
            actual = raw.replace("' panicked at", "' (323) panicked at")
            self.assertTrue(oracle(actual, result(True), contract, True))
            for bad in [actual.replace('(323)', '(abc)'),
                        actual.replace('(323)', '(-323)'),
                        actual.replace(contract['marker'], 'different assertion'),
                        actual.replace(f"left: {contract['left']}", 'left: 999')]:
                self.assertFalse(oracle(bad, result(True), contract, True))

    def test_compile_timeout_signal_setup_wrong_assertion_and_count_invalid(self):
        for contract in MUTANTS:
            raw = transcript(contract, True)
            for code in [0, 1, 124, -9]:
                bad = result(True); bad['returncode'] = code
                self.assertFalse(oracle(raw, bad, contract, True))
            for bad in [raw.replace('Finished', 'Compiling'), raw.replace(contract['marker'], 'wrong failure'),
                        raw.replace(f'{FILTERED} filtered out', f'{FILTERED - 1} filtered out'), raw + raw,
                        raw.replace('Running tests/native_inverse.rs', 'Running tests/other.rs'), raw + 'signal: 6 SIGABRT\n']:
                self.assertFalse(oracle(bad, result(True), contract, True))
            bad = result(True); bad['timeout'] = True
            self.assertFalse(oracle(raw, bad, contract, True))

    def test_cleanup_cannot_be_hidden_by_target_marker(self):
        for contract in MUTANTS:
            bad = result(True); bad['cleanup']['all_reaped'] = False
            self.assertFalse(oracle(transcript(contract, True), bad, contract, True))
            bad = result(False); bad['cleanup'].update(natural=False, forced=True)
            self.assertFalse(oracle(transcript(contract, False), bad, contract, False))
            forced = result(True); forced['cleanup'].update(natural=False, forced=True)
            self.assertTrue(oracle(transcript(contract, True), forced, contract, True))

    def test_final_send_reach_cannot_be_missing_or_after_panic(self):
        contract = MUTANTS[-1]; raw = transcript(contract, True)
        self.assertFalse(oracle(raw.replace(contract['reach'], ''), result(True), contract, True))
        self.assertFalse(oracle(raw.replace(contract['reach'] + '\n', '') + contract['reach'], result(True), contract, True))

    def test_scope_boundary_is_early_facts_not_masked_zero_physical_handler(self):
        contract = MUTANTS[1]
        self.assertEqual(FILTERED, 26)
        self.assertEqual(contract['test'], 'selected_scope_denies_before_dispatch_facts')
        raw = transcript(contract, True)
        self.assertFalse(oracle(raw.replace(contract['marker'], 'empty current refs must deny before physical handler reads'), result(True), contract, True))
        self.assertFalse(oracle(raw.replace(contract['reach'], ''), result(True), contract, True))
        self.assertFalse(oracle(raw.replace('26 filtered out', '25 filtered out'), result(True), contract, True))
        survived = transcript(contract, False)
        self.assertFalse(oracle(survived, result(False), contract, True))

    def test_real_owned_watchdog_reaps_child_and_marks_timeout_invalid(self):
        self.assertEqual(ctypes.CDLL(None).prctl(36, 1, 0, 0, 0), 0)
        with tempfile.TemporaryDirectory(prefix='native-watchdog-control-') as tmp:
            script = 'import subprocess,sys,time; subprocess.Popen([sys.executable,"-c","import time; time.sleep(20)"]); time.sleep(20)'
            observed = run([sys.executable, '-c', script], Path(tmp), None, Path(tmp)/'watchdog.log', timeout=0.2)
            self.assertTrue(observed['timeout'])
            self.assertTrue(observed['cleanup']['forced'])
            self.assertTrue(observed['cleanup']['all_reaped'])
            self.assertGreaterEqual(len(observed['cleanup']['known_pids']), 2)
            self.assertEqual(observed['cleanup']['remaining_pids'], {})


if __name__ == '__main__':
    unittest.main(verbosity=2)
