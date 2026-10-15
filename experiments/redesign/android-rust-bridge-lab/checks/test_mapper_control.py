"""Mapper classifier controls; synthetic logs are never actual JVM RED."""
import copy
import hashlib
from pathlib import Path
import tempfile
import unittest
from mapper_control import CONTRACT, inventory, classify
from test_workflow_selection import select

SOURCE='a'*40
LIBRARY='b'*64


def transcript():
    return ('AGENT_MAPPER_JVM_MAPPED source='+SOURCE+' sha256='+LIBRARY+'\n'
        +'\n'.join('PASS B generated projection '+name for name in CONTRACT['case_names'][:5])+'\n'
        +'Exception in thread "main" java.lang.IllegalStateException: '+CONTRACT['assertion']+'\n'
        +'\tat com.mightyoung.muyon.androidlab.agentipc.AgentNativeProjectionChecksKt.main(AgentNativeProjectionChecks.kt:27)\n')


class MapperControlTests(unittest.TestCase):
    def test_five_actual_passes_then_unique_primary_failure_required(self):
        raw=transcript();self.assertTrue(classify(raw,1,SOURCE,LIBRARY)['accepted'])
        for bad in [raw+raw,raw.replace(CONTRACT['case_names'][0],'unknown'),
                    raw.replace('AGENT_MAPPER_JVM_MAPPED','WRONG_MAPPED'),
                    raw.replace(SOURCE,'c'*40),raw.replace(LIBRARY,'c'*64),
                    raw.replace(CONTRACT['assertion'],'unrelated schema failure'),
                    raw.replace('java.lang.IllegalStateException','java.lang.NoSuchMethodError'),
                    raw+'Exception in thread "main" java.lang.NoSuchMethodError: setup failure\n',
                    'Exception in thread "worker" java.lang.AssertionError: setup failure\n'+raw,
                    raw+'thread \'worker\' (15) panicked at tests/setup.rs:1:1:\n\n',
                    raw+'6/6 B generated projection checks passed; metadata only, Android runtime NOT_RUN\n']:
            self.assertFalse(classify(bad,1,SOURCE,LIBRARY)['accepted'])
        lines=raw.splitlines()
        for a,b in [(0,1),(1,2),(4,5),(5,6)]:
            wrong=lines.copy();wrong[a],wrong[b]=wrong[b],wrong[a]
            self.assertFalse(classify('\n'.join(wrong),1,SOURCE,LIBRARY)['accepted'])
        for status in [0,101,124,-6,-9]:
            self.assertFalse(classify(raw,status,SOURCE,LIBRARY)['accepted'])

    def test_inventory_freezes_all_inputs_and_six_case_source(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);c=copy.deepcopy(CONTRACT)
            for path,g in c['sources'].items():
                body=('\n'.join('cases["'+name+'"]={}' for name in c['case_names']) if path.endswith('Checks.kt') else '// source control').encode()
                p=root/path;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(body)
                g['sha256']=hashlib.sha256(body).hexdigest()
                g['blob_sha']=hashlib.sha1(b'blob '+str(len(body)).encode()+b'\0'+body).hexdigest()
            self.assertEqual(inventory(root,c),c)
            path=next(root/path for path in c['sources'] if path.endswith('AgentNativeProjection.kt'))
            path.write_bytes(path.read_bytes()+b'\n')
            with self.assertRaisesRegex(RuntimeError,'mapper_control_inventory_invalid'):
                inventory(root,c)
        result,output=select('mapper-control-red','ignored')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(output,{'mode':'red','red':'["mapper-control-red"]'})
        result,output=select('','lab/android-rust-bridge-mapper-control-red-20261015')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(output,{'mode':'red','red':'["mapper-control-red"]'})


if __name__=='__main__':
    unittest.main()
