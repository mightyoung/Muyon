"""Synthetic service classifier controls, never actual native/JVM RED evidence."""
import copy
import unittest

from ffi_evidence import classify


SOURCE = 'a' * 40
LIBRARY = 'b' * 64
# These sample controls exercise the classifier. Actual descriptor/count/reach
# must come from the immutable author's first test source, not this transcript.
CONTRACT = dict(target='service_controller', test='service_controller_executes_registered_read',
    filtered=2, native_reach='AGENT_SERVICE_STUB_REACHED code=target_unavailable',
    rust_assert='AGENT_SERVICE_RED: admitted run must complete the registered physical read',
    jvm_reach='AGENT_SERVICE_JVM_STUB_REACHED request=service_jvm_primary code=target_unavailable',
    jvm_assert='AGENT_SERVICE_JVM_RED: admitted run must complete the registered physical read')


def rust_raw():
    return ("Finished `release` profile [optimized]\n"
        "Running tests/service_controller.rs (target/release/deps/service_controller-abc)\n"
        + CONTRACT['native_reach'] + "\n"
        + "thread '" + CONTRACT['test'] + "' (323) panicked at tests/service_controller.rs:1:1:\n"
        + CONTRACT['rust_assert'] + "\n"
        + 'test ' + CONTRACT['test'] + ' ... FAILED\n'
        + 'test result: FAILED. 0 passed; 1 failed; 0 ignored; 0 measured; 2 filtered out;\n')


def jvm_raw():
    return (f'AGENT_SERVICE_JVM_MAPPED source={SOURCE} sha256={LIBRARY}\n'
        + CONTRACT['native_reach'] + '\n' + CONTRACT['jvm_reach'] + '\n'
        + 'Exception in thread "main" java.lang.IllegalStateException: ' + CONTRACT['jvm_assert'] + '\n'
        + '\tat muyon.bridgechecks.ServiceProbe.main(ServiceProbe.kt:1)\n')


class ServiceEvidenceControls(unittest.TestCase):
    def accepted(self, mode, text, status, contract=CONTRACT, source=SOURCE, library=LIBRARY):
        try:
            return classify(mode, text, status, source, library, service=contract)['accepted']
        except TypeError as error:
            if "unexpected keyword argument 'service'" in str(error):
                self.fail('service RED classification API is missing')
            raise

    def test_source_defined_exact_rust_and_real_jvm_refusal_shapes(self):
        self.assertTrue(self.accepted('service-rust-red', rust_raw(), 101))
        self.assertTrue(self.accepted('service-rust-red', rust_raw().replace("' (323) panicked", "' panicked"), 101))
        self.assertTrue(self.accepted('service-jvm-red', jvm_raw(), 1))

    def test_rust_missing_reach_wrong_target_summary_panic_and_early_failure_invalid(self):
        raw = rust_raw()
        for bad in [raw.replace(CONTRACT['native_reach'], ''),
                    raw.replace(CONTRACT['rust_assert'], 'unrelated assertion'),
                    raw.replace('Running tests/service_controller.rs', 'Running tests/other.rs'),
                    raw.replace(CONTRACT['test'], 'other_test'), raw + raw,
                    raw.replace('2 filtered out', '1 filtered out'),
                    raw.replace('0 ignored', '1 ignored'),
                    raw.replace('Finished', 'Compiling'),
                    raw.replace('(323)', '(wrong)'),
                    raw.replace(CONTRACT['native_reach'] + '\n', '') + CONTRACT['native_reach'] + '\n']:
            with self.subTest(bad=bad):
                self.assertFalse(self.accepted('service-rust-red', bad, 101))

    def test_jvm_exact_native_load_source_guard_and_single_assertion(self):
        raw = jvm_raw()
        mapped = f'AGENT_SERVICE_JVM_MAPPED source={SOURCE} sha256={LIBRARY}'
        for bad in [raw.replace(mapped, ''), raw.replace(SOURCE, 'c' * 40),
                    raw.replace(LIBRARY, 'd' * 64), raw.replace(CONTRACT['native_reach'], ''),
                    raw.replace(CONTRACT['jvm_reach'], ''),
                    raw.replace(CONTRACT['jvm_assert'], 'unrelated early denial'), raw + raw,
                    raw + 'AGENT_SERVICE_JVM_PASS fake_positive\n',
                    raw.replace(CONTRACT['jvm_reach'] + '\n', '') + CONTRACT['jvm_reach'] + '\n']:
            self.assertFalse(self.accepted('service-jvm-red', bad, 1))

    def test_every_uncaught_main_exception_is_enumerated_not_only_expected_type(self):
        raw = jvm_raw()
        primary = 'Exception in thread "main" java.lang.IllegalStateException: ' + CONTRACT['jvm_assert']
        for header in [
                'Exception in thread "main" java.lang.NoSuchMethodError: setup/load failure',
                'Exception in thread "main" java.lang.RuntimeException: unrelated failure',
                'Exception in thread "main" java.lang.AssertionError: wrong assertion',
                'Exception in thread "main" java.lang.IllegalStateException: wrong primary',
                'Exception in thread "worker" java.lang.NoSuchMethodError: auxiliary setup failure',
                'Exception in thread "main"', primary]:
            for bad in [header + '\n' + raw, raw + header + '\n',
                        raw.replace(primary, header + '\n' + primary)]:
                with self.subTest(header=header, bad=bad):
                    self.assertFalse(self.accepted('service-jvm-red', bad, 1))

    def test_jvm_stage_markers_must_follow_actual_load_native_then_bridge_order(self):
        raw = jvm_raw()
        mapped = f'AGENT_SERVICE_JVM_MAPPED source={SOURCE} sha256={LIBRARY}'
        native, bridge = CONTRACT['native_reach'], CONTRACT['jvm_reach']
        suffix = raw.split(bridge + '\n', 1)[1]
        for markers in [(native, mapped, bridge), (mapped, bridge, native),
                        (bridge, native, mapped), (native, bridge, mapped), (bridge, mapped, native)]:
            self.assertFalse(self.accepted('service-jvm-red', '\n'.join(markers) + '\n' + suffix, 1))

    def test_environment_signal_compile_faults_and_success_are_never_red(self):
        for mode, raw, expected in [('service-rust-red', rust_raw(), 101),
                                    ('service-jvm-red', jvm_raw(), 1)]:
            for status in [0, 124, -6, -9, 2]:
                if status != expected:
                    self.assertFalse(self.accepted(mode, raw, status))
            for fault in ['Timeout', 'SIGABRT', 'signal: 9', 'could not compile',
                          'UnsatisfiedLinkError', 'NoClassDefFoundError', 'checksum mismatch', '\ufffd']:
                self.assertFalse(self.accepted(mode, raw + fault, expected))

    def test_missing_or_invalid_frozen_descriptor_is_failclosed(self):
        for contract in [None, {}, dict(CONTRACT, filtered=-1),
                         dict(CONTRACT, filtered=True), dict(CONTRACT, target='../../other')]:
            self.assertFalse(self.accepted('service-rust-red', rust_raw(), 101, contract))
        for key in CONTRACT:
            bad = copy.deepcopy(CONTRACT); del bad[key]
            self.assertFalse(self.accepted('service-jvm-red', jvm_raw(), 1, bad))
        self.assertFalse(self.accepted('service-jvm-red', jvm_raw(), 1, source='not-a-sha'))
        self.assertFalse(self.accepted('service-jvm-red', jvm_raw(), 1, library='not-a-sha'))


if __name__ == '__main__':
    unittest.main()
