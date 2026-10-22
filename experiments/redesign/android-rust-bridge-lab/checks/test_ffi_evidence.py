"""Synthetic evidence controls only, not compiled/native results."""
import unittest
from ffi_evidence import RUST_TEST, RUST_REACH, RUST_ASSERT, JVM_REACH, JVM_ASSERT, classify

SOURCE = 'a' * 40
LIBRARY = 'b' * 64


def rust():
    return (f"Finished `release` profile\nRunning tests/bridge_contract.rs (target/release/deps/test)\n{RUST_REACH}\n"
            f"thread '{RUST_TEST}' (123) panicked at tests/bridge_contract.rs:1:1:\n{RUST_ASSERT}\n"
            f"test {RUST_TEST} ... FAILED\ntest result: FAILED. 0 passed; 1 failed; 0 ignored; 0 measured; 5 filtered out;\n")


def jvm():
    return (f'ANDROID_BRIDGE_JVM_MAPPED source={SOURCE} sha256={LIBRARY}\n{RUST_REACH}\n{JVM_REACH}\n'
            f'Exception in thread "main" java.lang.IllegalStateException: {JVM_ASSERT}\n')


class FfiEvidenceTests(unittest.TestCase):
    def test_real_format_exact_target_guards_are_recognized(self):
        self.assertTrue(classify('rust-red', rust(), 101, SOURCE, LIBRARY)['accepted'])
        self.assertTrue(classify('rust-red', rust().replace(' (123)', ''), 101, SOURCE, LIBRARY)['accepted'])
        self.assertTrue(classify('jvm-red', jvm(), 1, SOURCE, LIBRARY)['accepted'])

    def test_compile_load_wrong_assertion_identity_and_wrong_exit_invalid(self):
        for mode, raw, status in [('rust-red', rust(), 101), ('jvm-red', jvm(), 1)]:
            for code in [0, 124, -6, -9]:
                self.assertFalse(classify(mode, raw, code, SOURCE, LIBRARY)['accepted'])
            for bad in [raw.replace(RUST_REACH, ''), raw + raw, raw + 'SIGABRT\n', raw + 'UnsatisfiedLinkError\n']:
                self.assertFalse(classify(mode, bad, status, SOURCE, LIBRARY)['accepted'])
        self.assertFalse(classify('rust-red', rust().replace(RUST_ASSERT, 'wrong failure'), 101, SOURCE, LIBRARY)['accepted'])
        self.assertFalse(classify('rust-red', rust().replace('5 filtered out', '4 filtered out'), 101, SOURCE, LIBRARY)['accepted'])
        self.assertFalse(classify('rust-red', rust().replace('Finished', 'Compiling'), 101, SOURCE, LIBRARY)['accepted'])
        self.assertFalse(classify('jvm-red', jvm(), 1, 'c' * 40, LIBRARY)['accepted'])
        self.assertFalse(classify('jvm-red', jvm().replace(JVM_ASSERT, 'wrong failure'), 1, SOURCE, LIBRARY)['accepted'])

    def test_late_native_guards_and_pass_cannot_replace_reached_red(self):
        self.assertFalse(classify('rust-red', rust().replace(RUST_REACH+'\n', '') + RUST_REACH, 101, SOURCE, LIBRARY)['accepted'])
        self.assertFalse(classify('jvm-red', jvm().replace(JVM_REACH+'\n', '') + JVM_REACH, 1, SOURCE, LIBRARY)['accepted'])
        self.assertFalse(classify('jvm-red', jvm()+'ANDROID_BRIDGE_JVM_PASS extra\n', 1, SOURCE, LIBRARY)['accepted'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
