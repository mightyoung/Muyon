"""Independent host46 classifier controls; source execution is recorded separately."""
import unittest
from service_host_46_green import CONTRACT, classify


class Host46Controls(unittest.TestCase):
    def test_source_first_46_exact_inventory_and_no_partial_green(self):
        self.assertEqual({k:len(v['names']) for k,v in CONTRACT['targets'].items()}, dict(native_read=25, contract_transport=8, service_runtime=2, service_root=2, service_controller=4, service_oracle=1, service_lifecycle=4))
        for target, group in CONTRACT['targets'].items():
            raw = 'Finished `release` profile [optimized]\nRunning tests/' + target + '.rs (target/release/deps/test-abc)\n'
            raw += '\n'.join('test ' + name + ' ... ok' for name in group['names']) + '\n'
            raw += f"test result: ok. {len(group['names'])} passed; 0 failed; 0 ignored; 0 measured; 0 filtered out;\n"
            self.assertTrue(classify(target, raw, 0)['accepted'])
            for bad in [raw+raw, raw.replace(' ... ok', ' ... FAILED', 1), raw.replace('0 filtered out','1 filtered out'), raw+'thread panic panicked at x\n', raw.replace('Finished','Compiling')]:
                self.assertFalse(classify(target, bad, 0)['accepted'])
            self.assertFalse(classify(target, raw, 101)['accepted'])


if __name__ == '__main__':
    unittest.main()
