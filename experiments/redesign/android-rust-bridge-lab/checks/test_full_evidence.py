import unittest
from full_evidence import JVM_NAMES, jvm_full, panic_full, rust_full
from linux_gate import UNIT, INTEGRATION


class FullControls(unittest.TestCase):
    def test_rust_requires_all_exact_names_three_summaries_and_no_skip(self):
        rows = '\n'.join('test ' + name + ' ... ok' for name in sorted({'tests::'+name for name in UNIT} | INTEGRATION))
        summaries = '\n'.join(f'test result: ok. {n} passed; 0 failed; 0 ignored; 0 measured; 0 filtered out;' for n in [3, 6, 0])
        raw = rows + '\n' + summaries
        self.assertTrue(rust_full(raw, UNIT, INTEGRATION))
        for bad in [raw.replace('3 passed', '2 passed'), raw.replace('0 filtered', '1 filtered'), raw.replace(' ... ok', ' ... ignored', 1), raw + '\ntest extra ... ok', raw.replace('bundled_contract_reaches_rust_catalog', 'unrelated')]:
            self.assertFalse(rust_full(bad, UNIT, INTEGRATION))

    def test_jvm_exact_closed_names_and_identity(self):
        raw = '\n'.join(['ANDROID_BRIDGE_JVM_MAPPED source=s sha256=h'] + ['ANDROID_BRIDGE_JVM_PASS '+name for name in JVM_NAMES])+'\n'
        self.assertTrue(jvm_full(raw, 's', 'h'))
        for bad in [raw+'Exception in thread main\n', raw.replace('source=s', 'source=t'), raw.replace(JVM_NAMES[0], 'extra'), raw+raw]:
            self.assertFalse(jvm_full(bad, 's', 'h'))

    def test_panic_must_enter_action_then_recover_after_unique_real_panic(self):
        raw = "ANDROID_BRIDGE_PANIC_MAPPED source=s sha256=h\nANDROID_BRIDGE_PANIC_ACTION_ENTERED\nthread '<unnamed>' (123) panicked at src/lib.rs:1:1:\nANDROID_BRIDGE_TEST_PANIC\nANDROID_BRIDGE_JVM_PASS panic_is_typed_and_valid_sibling_recovers\n"
        self.assertTrue(panic_full(raw, 's', 'h'))
        for bad in [raw.replace('ANDROID_BRIDGE_PANIC_ACTION_ENTERED', 'absent'), raw.replace('ANDROID_BRIDGE_TEST_PANIC', 'other'), raw+'Exception in thread main\n', raw+raw, raw.replace('source=s','source=t')]:
            self.assertFalse(panic_full(bad, 's', 'h'))


if __name__ == '__main__':
    unittest.main()
