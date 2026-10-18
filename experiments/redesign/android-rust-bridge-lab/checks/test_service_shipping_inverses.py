import unittest
from service_shipping_inverses import classify


class ShippingInverseTests(unittest.TestCase):
    def test_baseline_requires_four_variants_and_clean_exit(self):
        text = '\n'.join('SERVICE_SHIPPING_PASS variant=' + x for x in ('EQUIPMENT', 'RESEARCH', 'INQUIRY', 'SEEDED_EQUIPMENT'))
        text += '\nSERVICE_SHIPPING_ALL_PASS variants=4 Android_ART_Binder_UID_fsync_kill_rebind=NOT_RUN\n'
        good = dict(exit_code=0, timed_out=False, forced_owned_group_cleanup=False, live_after_cleanup=[])
        self.assertTrue(classify(text, good))
        for bad in (text.replace('variant=RESEARCH', 'variant=EQUIPMENT'), text + text, text.replace('variants=4', 'variants=3')):
            self.assertFalse(classify(bad, good))
        self.assertFalse(classify(text, dict(good, exit_code=1)))

    def test_inverse_requires_exact_assertion_and_natural_completion(self):
        text = 'Exception in thread "main" java.lang.IllegalStateException: SERVICE_SHIPPING_ASSERT:duplicate_is_existing\n'
        good = dict(exit_code=1, timed_out=False, forced_owned_group_cleanup=False, live_after_cleanup=[])
        self.assertTrue(classify(text, good, 'duplicate_is_existing'))
        self.assertFalse(classify(text, good, 'stale_epoch_rejected'))
        for key, value in [('exit_code', 124), ('timed_out', True), ('forced_owned_group_cleanup', True), ('live_after_cleanup', [10])]:
            self.assertFalse(classify(text, dict(good, **{key:value}), 'duplicate_is_existing'))
        self.assertFalse(classify('could not compile\n' + text, good, 'duplicate_is_existing'))
