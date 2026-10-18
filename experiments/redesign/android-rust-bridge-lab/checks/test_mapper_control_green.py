"""Synthetic classifier controls, never actual mapper execution evidence."""
import unittest
from mapper_control_green import CONTRACT, SUMMARY, classify
from test_mapper_control import transcript as old_red

SOURCE = CONTRACT['author_commit']
LIBRARY = 'b' * 64


def transcript():
    return '\n'.join([f'AGENT_MAPPER_JVM_MAPPED source={SOURCE} sha256={LIBRARY}'] +
        ['PASS B generated projection ' + name for name in CONTRACT['case_names']] + [SUMMARY]) + '\n'


class MapperGreenControls(unittest.TestCase):
    def test_all_six_named_passes_exact_header_summary_exit_zero(self):
        raw = transcript()
        self.assertTrue(classify(raw, 0, SOURCE, LIBRARY)['accepted'])
        for bad in [raw+raw, raw.replace(SUMMARY, ''), raw.replace(CONTRACT['case_names'][5], 'unknown'), old_red(), raw.replace(SOURCE, 'a'*40)]:
            self.assertFalse(classify(bad, 0, SOURCE, LIBRARY)['accepted'])
        for name in CONTRACT['case_names']:
            self.assertFalse(classify(raw.replace('PASS B generated projection '+name+'\n', ''), 0, SOURCE, LIBRARY)['accepted'])
        lines=raw.splitlines();lines[1],lines[2]=lines[2],lines[1]
        self.assertFalse(classify('\n'.join(lines), 0, SOURCE, LIBRARY)['accepted'])
        for status in [1,101,124,-6,-9]:
            self.assertFalse(classify(raw, status, SOURCE, LIBRARY)['accepted'])

    def test_wrong_source_or_library_pin_cannot_accept_a_matching_transcript(self):
        for source in ['a'*40, '', SOURCE+'0']:
            self.assertFalse(classify(transcript().replace(SOURCE, source), 0, source, LIBRARY)['accepted'])
        for library in ['', 'b'*63, 'B'*64]:
            self.assertFalse(classify(transcript().replace(LIBRARY, library), 0, SOURCE, library)['accepted'])

    def test_any_mixed_load_fault_or_extra_mapping_header_remains_invalid(self):
        raw=transcript()
        for extra in ['UnsatisfiedLinkError: missing native library', 'NoClassDefFoundError: generated record class',
            'NoSuchMethodError: incompatible generated type', 'checksum mismatch: generated contract',
            'ClassNotFoundException: generated record class', 'ExceptionInInitializerError: incompatible binding',
            'LinkageError: incompatible native component', 'UnsupportedClassVersionError: incompatible compiler',
            'AGENT_MAPPER_JVM_MAPPED malformed extra header', 'Exception in thread "main" java.lang.IllegalStateException: other',
            "thread 'worker' panicked at setup.rs:1:1:"]:
            for bad in [extra+'\n'+raw, raw+extra+'\n']:
                self.assertFalse(classify(bad, 0, SOURCE, LIBRARY)['accepted'])


if __name__=='__main__':
    unittest.main()
