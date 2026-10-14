#!/usr/bin/env python3
"""Actual fixed Dart product oracle versus this Rust synthetic stdin probe.
Only fixed ordinary synthetic M04 inputs; no replicated normalization.
"""
import hashlib, json, os, pathlib, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parents[5]
PRODUCT = '01e56cc2d729dab70e1b1def05c3aa93b28f421a'
FIXTURE = '8c5995515fa14ca3592a1c33c71afb4e4c1e5def'
EVIDENCE = pathlib.Path(sys.argv[1]).resolve()
if EVIDENCE.is_relative_to(ROOT): raise ValueError('raw evidence must be outside repository')
EVIDENCE.mkdir(parents=True, exist_ok=True)
def fixed(sha, path): return subprocess.check_output(['git', '-C', str(ROOT), 'show', sha+':'+path])
def digest(raw): return hashlib.sha256(raw).hexdigest()
sources = {}
for name in ['values', 'entities', 'inquiry']:
    path = 'packages/supplier_core/lib/src/'+name+'.dart'
    data = fixed(PRODUCT, path)
    if (ROOT/path).read_bytes() != data: raise ValueError('changed product source: '+path)
    sources[path] = digest(data)
fixture_bytes = fixed(FIXTURE, 'fixtures/redesign/supplier-name-v1/name-domain-vectors.json')
fixture = json.loads(fixture_bytes)
def decode(recipe):
    if 'literal' in recipe: return recipe['literal']
    if 'repeat' in recipe: return recipe['repeat']['literal']*recipe['repeat']['count']
    if 'concat' in recipe: return ''.join(map(decode, recipe['concat']))
    raise ValueError('unsupported recipe')
def units(recipe):
    if 'utf16_code_units' in recipe: return recipe['utf16_code_units']
    data = decode(recipe).encode('utf-16-le', errors='surrogatepass')
    return [int.from_bytes(data[i:i+2], 'little') for i in range(0, len(data), 2)]
inputs = [{'id': c['case_id'], 'units': units(c['input_recipe'])} for c in fixture['cases']]
invocations = [{'invocation_id': c['case_id'], 'entry_point': 'normalizeText', 'input': c['input_recipe'], 'safe_output': True} for c in fixture['cases']]
(EVIDENCE/'invocations.json').write_text(json.dumps(invocations))
unorm = pathlib.Path('/workspace/pub-cache/hosted/pub.dev/unorm_dart-0.3.1')
dependency_hashes = {str(p.relative_to(unorm)):digest(p.read_bytes()) for p in sorted((unorm/'lib').rglob('*.dart'))}
reference = json.loads((ROOT/'scripts/redesign/supplier-name-reference/reference-observations.json').read_text())
if dependency_hashes != reference['normalization_dependency']['lib_sha256']:
    raise ValueError('cached Dart normalization library differs from M05 fixed observation')
(EVIDENCE/'package_config.json').write_text(json.dumps({'configVersion':2, 'packages':[{'name':'unorm_dart','rootUri':unorm.as_uri()+'/', 'packageUri':'lib/', 'languageVersion':'2.12'}]}))
env = dict(os.environ); env.pop('MUYON_EVAL_REAL', None); env['CI'] = 'true'; env['XDG_CONFIG_HOME']='/workspace/sdk-config'
dart = ['/workspace/flutter-sdk/bin/cache/dart-sdk/bin/dart', '--packages='+str(EVIDENCE/'package_config.json'), str(ROOT/'scripts/redesign/supplier-name-reference/oracle.dart'), str(EVIDENCE/'invocations.json')]
p = subprocess.run(dart, capture_output=True, env=env)
(EVIDENCE/'dart.stdout').write_bytes(p.stdout); (EVIDENCE/'dart.stderr').write_bytes(p.stderr)
if p.returncode: raise RuntimeError('Dart failed')
actual_dart = json.loads(p.stdout)
p = subprocess.run(['/tmp/rd-p01-target/debug/examples/normalize_probe'], input=json.dumps(inputs).encode(), capture_output=True, env=env)
(EVIDENCE/'rust.stdout').write_bytes(p.stdout); (EVIDENCE/'rust.stderr').write_bytes(p.stderr)
if p.returncode: raise RuntimeError('Rust failed')
actual_rust = json.loads(p.stdout)
if len(actual_dart) != 32 or len(actual_rust) != 32: raise ValueError('incomplete corpus')
reasons = {'InvalidXml':'name: invalid XML character or isolated surrogate', 'Required':'name: required', 'NameLimit':'name: exceeds 200 codepoints'}
rows=[]
for i,d,r in zip(inputs, actual_dart, actual_rust):
    if d['invocation_id'] != i['id'] or r['id'] != i['id']: raise ValueError('corpus ordering changed')
    if len(i['units']) > 2000:
        ok = r.get('reason') == 'RawLimit' and d['outcome'] == 'accepted'
        result = 'expected_raw_guard_difference'
    else:
        ok = d['outcome'] == r['outcome'] and (d.get('normalized') == r.get('normalized') if d['outcome']=='accepted' else d['reason']==reasons.get(r['reason']))
        result = 'equal'
    rows.append({'case_id':i['id'], 'comparison':result, 'pass':ok})
summary = {'fixture_sha':FIXTURE, 'product_sha':PRODUCT, 'fixture_sha256':digest(fixture_bytes), 'product_source_sha256':sources, 'dart_dependency_lib_sha256':dependency_hashes, 'oracle_sha256':digest((ROOT/'scripts/redesign/supplier-name-reference/oracle.dart').read_bytes()), 'dart_exit':0, 'rust_exit':0, 'dart_version':subprocess.check_output([dart[0], '--version'],env=env).decode().strip(), 'dart_normalization':'unorm_dart 0.3.1 / Unicode 8.0', 'rust_normalization':'unicode-normalization 0.1.25 / Unicode 17.0.0', 'global_unicode_equivalence':'NOT_PROVEN', 'cases':rows}
(EVIDENCE/'differential-summary.json').write_text(json.dumps(summary,ensure_ascii=True,indent=2)+'\n')
assert all(row['pass'] for row in rows), 'actual oracle mismatch'
print('32 actual paired probes: 30 equal, 2 expected raw-guard differences; no global equivalence claim')
