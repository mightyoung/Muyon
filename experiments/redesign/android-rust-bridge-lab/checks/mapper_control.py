"""Frozen metadata mapper CONTROL_TARGET_RED; never Service runtime evidence."""
import hashlib
import json
from pathlib import Path
import re

CONTRACT=json.loads(Path(__file__).with_name('mapper_control_cases.json').read_text())


def inventory(root,contract=None):
    contract=CONTRACT if contract is None else contract
    try:
        if (set(contract)!={'version','author_commit','entrypoint','sources','case_names','assertion'}
                or type(contract['version']) is not int or contract['version']!=1
                or not re.fullmatch('[0-9a-f]{40}',contract['author_commit'])
                or contract['entrypoint']!=CONTRACT['entrypoint']
                or contract['case_names']!=CONTRACT['case_names'] or len(contract['case_names'])!=6
                or contract['assertion']!=CONTRACT['assertion']
                or set(contract['sources'])!=set(CONTRACT['sources'])):
            raise ValueError('shape')
        for path,group in contract['sources'].items():
            if (set(group)!={'blob_sha','sha256'} or not re.fullmatch('[0-9a-f]{40}',group['blob_sha'])
                    or not re.fullmatch('[0-9a-f]{64}',group['sha256'])):
                raise ValueError('source shape')
            data=(root/path).read_bytes()
            blob=hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
            if hashlib.sha256(data).hexdigest()!=group['sha256'] or blob!=group['blob_sha']:
                raise ValueError('source bytes')
            if path.endswith('AgentNativeProjectionChecks.kt'):
                if re.findall(r'cases\["([^"]+)"\]',data.decode('utf-8'))!=contract['case_names']:
                    raise ValueError('case names')
        return contract
    except (OSError,ValueError,TypeError,KeyError,AttributeError) as failure:
        raise RuntimeError('mapper_control_inventory_invalid') from failure


def classify(raw,status,source,library_sha):
    mapped=f'AGENT_MAPPER_JVM_MAPPED source={source} sha256={library_sha}'
    primary='Exception in thread "main" java.lang.IllegalStateException: '+CONTRACT['assertion']
    mappings=re.findall(r'^AGENT_MAPPER_JVM_MAPPED[^\n]*',raw,re.M)
    passes=['PASS B generated projection '+name for name in CONTRACT['case_names'][:5]]
    stages=[mapped]+passes+[primary]
    exceptions=re.findall(r'^Exception in thread "([^"]*)"([^\n]*)',raw,re.M)
    valid=bool(status==1 and re.fullmatch('[0-9a-f]{40}',source) and re.fullmatch('[0-9a-f]{64}',library_sha)
        and mappings==[mapped]
        and exceptions==[('main',' java.lang.IllegalStateException: '+CONTRACT['assertion'])]
        and re.findall(r'^PASS B generated projection ([^\n]+)',raw,re.M)==CONTRACT['case_names'][:5]
        and all(raw.splitlines().count(stage)==1 for stage in stages)
        and all(raw.index(a)<raw.index(b) for a,b in zip(stages,stages[1:]))
        and raw.count(CONTRACT['assertion'])==1
        and not re.search(r'checks passed; metadata only|panicked at|timed out|Timeout|signal:|SIGABRT|SIGKILL|UnsatisfiedLinkError|NoClassDefFoundError|NoSuchMethodError|NoSuchFieldError|ClassNotFoundException|ExceptionInInitializerError|LinkageError|UnsupportedClassVersionError|IncompatibleClassChangeError|VerifyError|checksum mismatch|\ufffd',raw))
    return dict(accepted=valid,classification='semantic_red' if valid else 'INVALID',
        mode='mapper-control-red',command_exit_code=status,mapper_passed=5 if valid else None,
        mapper_expected_failed=CONTRACT['case_names'][5],
        scope='actual fresh generated records and pure metadata mapper; controller/Android runtime NOT_RUN')
