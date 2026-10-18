"""Separate source-fixed mapper GREEN; original RED and mixed-fault rules stay intact."""
import hashlib
import json
from pathlib import Path
import re
from mapper_control import inventory as red_inventory

HERE = Path(__file__).resolve().parent
CONTRACT = json.loads((HERE / 'mapper_control_green_cases.json').read_text())
SUMMARY = '6/6 B generated projection checks passed; metadata only, Android runtime NOT_RUN'


def inventory(root):
    return red_inventory(root, CONTRACT)


def classify(raw, status, source, library_sha):
    mapped = f'AGENT_MAPPER_JVM_MAPPED source={source} sha256={library_sha}'
    stages = [mapped] + ['PASS B generated projection ' + name for name in CONTRACT['case_names']] + [SUMMARY]
    valid = (status == 0 and source == CONTRACT['author_commit']
        and bool(re.fullmatch('[0-9a-f]{64}', library_sha))
        and raw.splitlines() == stages)
    return dict(accepted=valid, classification='mapper_metadata_green' if valid else 'INVALID',
        mode='mapper-control-green', command_exit_code=status, source_commit=source,
        mapper_passed=6 if valid else None, shipping_or_service_green=False,
        scope='real shipping native handshake plus fresh generated records and pure metadata mapper; Android Service runtime NOT_RUN')


def main():
    import argparse
    import os
    import subprocess
    parser=argparse.ArgumentParser()
    parser.add_argument('--source-root', type=Path, required=True)
    parser.add_argument('--library', type=Path, required=True)
    parser.add_argument('--bindgen', type=Path, required=True)
    parser.add_argument('--kotlinc', type=Path, required=True)
    parser.add_argument('--jna', type=Path, required=True)
    parser.add_argument('--evidence-dir', type=Path, required=True)
    args=parser.parse_args()
    root=args.source_root.resolve();evidence=args.evidence_dir.resolve();evidence.mkdir(parents=True,exist_ok=False)
    source=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
    if source!=CONTRACT['author_commit']:
        raise RuntimeError('mapper_green_source_invalid')
    inventory(root)
    def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
    library=args.library.resolve();jna=args.jna.resolve();bindgen=args.bindgen.resolve();kotlinc=args.kotlinc.resolve()
    original=sha(library)
    if sha(jna)!='4fb141dd8ef6b0585ffceea4bc49602fbc6312fa977e2c488794ea3e6aafecae':
        raise RuntimeError('mapper_green_jna_pin_invalid')
    commands=[]
    def run(command,name,timeout=300):
        command=[str(x) for x in command];commands.append(dict(command=command,log=name))
        with (evidence/name).open('w') as log:
            try:return subprocess.run(command,cwd=root,stdout=log,stderr=subprocess.STDOUT,timeout=timeout).returncode
            except subprocess.TimeoutExpired:return 124
    config=root/'experiments/redesign/android-rust-bridge-lab/core/uniffi.jvm.toml'
    provenance=dict(source_commit=source,library_path=str(library),library_sha256=original,
        descriptor_sha256=sha(HERE/'mapper_control_green_cases.json'),bindgen_sha256=sha(bindgen),
        jna_sha256=sha(jna),jvm_config_sha256=sha(config),commands=commands)
    result=dict(accepted=False,classification='INVALID',mode='mapper-control-green',shipping_or_service_green=False)
    try:
        if run(['java','-version'],'java-version.log')!=0 or not re.search(r'version "17\.',(evidence/'java-version.log').read_text()):
            raise RuntimeError('mapper_green_jdk17_missing')
        if run([kotlinc,'-version'],'kotlin-version.log')!=0 or 'kotlinc-jvm 2.2.20' not in (evidence/'kotlin-version.log').read_text():
            raise RuntimeError('mapper_green_kotlin_pin_invalid')
        if run([bindgen,'generate',library,'--crate','muyon_android_contract_bridge','--language','kotlin','--config',config,'--no-format','--out-dir',evidence/'fresh-jvm'],'generate-jvm.log')!=0:
            raise RuntimeError('mapper_green_generation_failed')
        binding=evidence/'fresh-jvm/com/mightyoung/muyon/androidbridge/muyon_android_contract_bridge.kt'
        if 'ffiTestPanicProbe' in binding.read_text():
            raise RuntimeError('mapper_green_shipping_feature_invalid')
        provenance['jvm_binding_sha256']=sha(binding)
        jar=evidence/'mapper-probe.jar'
        command=[kotlinc,binding,HERE/'BridgeProbe.kt',HERE/'MapperProbe.kt',*[root/p for p in CONTRACT['sources']],'-jvm-target','17','-classpath',jna,'-include-runtime','-d',jar]
        if run(command,'kotlin-compile.log')!=0:
            raise RuntimeError('mapper_green_kotlin_compile_failed')
        provenance['jar_sha256']=sha(jar)
        status=run(['java','-cp',str(jar)+os.pathsep+str(jna),'muyon.bridgechecks.MapperProbe',source,library],'behavior.log',timeout=60)
        result.update(classify((evidence/'behavior.log').read_text(errors='replace'),status,source,original))
        if sha(library)!=original:
            result.update(accepted=False,classification='INVALID',error='mapper_green_library_changed')
        inventory(root)
    except (OSError,ValueError,RuntimeError) as error:
        result.update(accepted=False,classification='INVALID',error=str(error))
    finally:
        (evidence/'provenance.json').write_text(json.dumps(provenance,indent=2)+'\n')
        (evidence/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))
    raise SystemExit(0 if result['accepted'] else 1)


if __name__=='__main__':
    main()
