"""Version-swap desktop diagnostic; never certifies Android/JNI runtime parity.

Use .npy stage files so both Python-3.9 OpenCV bindings share one Python-3.12
ORT 1.21.1 executor. No inference implementation or model conversion is used.
"""
import argparse
import hashlib
import importlib.metadata
import json
from pathlib import Path
import subprocess
import sys
import types

ROOT = Path(__file__).resolve().parents[2]
SAMPLES = ('english', 'chinese', 'color', 'blank', 'rotated')
SIZES = ('tiny', 'small')

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def reference():
    # The cv2 workers never execute ORT; inference runs separately with 1.21.1.
    try:
        import onnxruntime
    except ImportError:
        sys.modules['onnxruntime'] = types.ModuleType('onnxruntime')
    sys.path.insert(0, str(ROOT / 'checks'))
    import cpu_reference
    return cpu_reference

def worker(phase, work, assets):
    import numpy as np
    import cv2
    ref = reference()
    if phase == 'fixtures':
        work.mkdir(parents=True, exist_ok=True)
        images, font = ref.samples()
        for name, pixels in images.items():
            np.save(work / (name + '.npy'), pixels)
        (work / 'fixtures.json').write_text(json.dumps(dict(font=font, files={p.name: sha(p) for p in work.glob('*.npy')}), indent=2))
        return
    for size in SIZES:
        for sample in SAMPLES:
            case = work / size / sample
            case.mkdir(parents=True, exist_ok=True)
            image = np.load(work.parent / 'fixtures' / (sample + '.npy'))
            if phase == 'det-input':
                for stale in list(case.glob('*.npy')) + list(case.glob('*.json')):
                    stale.unlink()
                np.save(case / 'det-input.npy', ref.preprocess_det(image))
            elif phase == 'post-det':
                h, w = image.shape[:2]
                pred = np.load(case / 'det-output.npy')
                post = ref.DBPostProcess(thresh=.3, box_thresh=.6, max_candidates=3000, unclip_ratio=1.5)
                boxes = sorted(post({'maps': pred}, [[h,w,1,1]])[0]['points'], key=lambda b:(float(b[0][1]),float(b[0][0])))
                (case / 'boxes.json').write_text(json.dumps([b.tolist() for b in boxes]))
                for i, box in enumerate(boxes):
                    crop = ref.get_rotate_crop_image(image, box.astype('float32'))
                    np.save(case / ('crop-%d.npy' % i), crop)
                    np.save(case / ('rec-input-%d.npy' % i), ref.preprocess_rec(crop))
            elif phase == 'decode':
                import yaml
                cfg = yaml.safe_load((assets / ('PP-OCRv6_%s_rec_onnx' % size) / 'inference.yml').read_text())
                chars = cfg['PostProcess']['character_dict']
                if chars[-1] != ' ': chars = chars + [' ']
                boxes = json.loads((case / 'boxes.json').read_text())
                outputs = [ref.decode(np.load(case / ('rec-output-%d.npy' % i)), chars) for i in range(len(boxes))]
                (case / 'result.json').write_text(json.dumps(dict(boxes=boxes, text=[o[0] for o in outputs], recognitionConfidence=[o[1] for o in outputs]), ensure_ascii=False, indent=2))
    if phase == 'decode':
        build = cv2.getBuildInformation()
        native_files = list(Path(cv2.__file__).parent.glob('*.so'))
        (work / 'runtime.json').write_text(json.dumps(dict(python=sys.version, numpy=np.__version__, opencv=cv2.__version__, opencvBuild=build, nativeBinaries={str(p):sha(p) for p in native_files}, dependencies={n:importlib.metadata.version(n) for n in ('opencv-python-headless','Pillow','PyYAML','shapely','pyclipper')}, numpyMetadataOverride=cv2.__version__=='4.12.0'), indent=2))

def infer(stage, work, assets):
    import numpy as np
    import onnxruntime as ort
    assert ort.__version__ == '1.21.1', ort.__version__
    for size in SIZES:
        opts = ort.SessionOptions()
        opts.intra_op_num_threads = 2
        opts.inter_op_num_threads = 1
        session = ort.InferenceSession(str(assets / ('PP-OCRv6_%s_%s_onnx' % (size, stage)) / 'inference.onnx'), opts, providers=['CPUExecutionProvider'])
        for sample in SAMPLES:
            for path in sorted((work / size / sample).glob(stage + '-input*.npy')):
                output = session.run(None, {'x':np.load(path)})[0]
                assert np.isfinite(output).all()
                np.save(path.with_name(path.name.replace('-input', '-output')), output)
    (work / 'inference-runtime.json').write_text(json.dumps(dict(python=sys.version, onnxruntime=ort.__version__, numpy=np.__version__, provider='CPUExecutionProvider', intraOpThreads=2, interOpThreads=1), indent=2))

def compare(base, out, assets):
    import numpy as np
    lock_path = ROOT / 'models.lock.json'
    lock = json.loads(lock_path.read_text())
    verified = {}
    for model in lock['models']:
        for entry in model['files']:
            p = assets / model['repository'].split('/')[-1] / entry['file']
            assert p.stat().st_size == entry['bytes'] and sha(p) == entry['sha256'], str(p)
            verified[str(p)] = sha(p)
    report = dict(scope='desktop Python OpenCV 4.5.3 to 4.12.0 diagnostic only; NOT Quickbird Android versus official Android JNI parity', androidInference='NOT_RUN', modelLockSha256=sha(lock_path), default=lock['default'], comparison=lock['comparison'], modelFiles=verified, fixtures=json.loads((base / 'fixtures/fixtures.json').read_text()), runtimes={}, cases={}, tolerances=dict(tensorAtol=1e-5,tensorRtol=1e-5,boxesExact=True,textExact=True,confidenceAtol=1e-5))
    for version in ('4.5.3','4.12.0'):
        report['runtimes'][version] = dict(opencv=json.loads((base/version/'runtime.json').read_text()), inference=json.loads((base/version/'inference-runtime.json').read_text()))
    passed = True
    for size in SIZES:
        for sample in SAMPLES:
            a, b = (base/v/size/sample for v in ('4.5.3','4.12.0'))
            ra, rb = (json.loads((p/'result.json').read_text()) for p in (a,b))
            shapes_same = {p.name for p in a.glob('*.npy')} == {p.name for p in b.glob('*.npy')}
            stages = {}
            for p in sorted(a.glob('*.npy')):
                if not (b/p.name).exists():
                    stages[p.name] = dict(withinTolerance=False, finite=False, missingInNew=True)
                    continue
                x, y = np.load(p), np.load(b/p.name)
                same_shape = x.shape == y.shape
                delta = np.abs(x.astype('float64') - y.astype('float64')) if same_shape else None
                stages[p.name] = dict(shapeA=list(x.shape),shapeB=list(y.shape), dtype=str(x.dtype), sha256A=sha(p),sha256B=sha(b/p.name),finite=bool(np.isfinite(x).all() and np.isfinite(y).all()), exact=bool(same_shape and np.array_equal(x,y)), maxAbs=float(delta.max()) if delta is not None and delta.size else None, meanAbs=float(delta.mean()) if delta is not None and delta.size else None, changedElements=int(np.count_nonzero(delta)) if delta is not None else None, withinTolerance=bool(same_shape and np.allclose(x,y,atol=1e-5,rtol=1e-5)))
            conf_same = len(ra['recognitionConfidence']) == len(rb['recognitionConfidence'])
            conf_delta = max([abs(x-y) for x,y in zip(ra['recognitionConfidence'],rb['recognitionConfidence'])] or [0.]) if conf_same else None
            ok = shapes_same and ra['text']==rb['text'] and ra['boxes']==rb['boxes'] and conf_same and conf_delta <= 1e-5 and all(s['withinTolerance'] and s['finite'] for s in stages.values())
            report['cases'][size+'/'+sample] = dict(passed=ok, old=ra,new=rb, confidenceMaxAbs=conf_delta,stages=stages)
            passed = passed and ok
    report['desktopDiagnosticPassed'] = passed
    report['rawTensorDirectory'] = str(base.resolve())
    report['stageCount'] = sum(len(c['stages']) for c in report['cases'].values())
    report['allStagesBitwiseIdentical'] = all(s.get('exact',False) for c in report['cases'].values() for s in c['stages'].values())
    report['limitations'] = ['Desktop cv2 wheels are not Quickbird or org.opencv Android binaries.', 'Existing cpu_reference uses NumPy normalization and upstream Python DB polygon/crop; this is not the Kotlin Android pipeline.', 'OpenCV 4.12 wheel NumPy>=2 metadata was overridden to keep NumPy1.26.4 identical to 4.5.3; actual imports and pipeline execute.', 'Synthetic five-image corpus per model is not a representative accuracy benchmark.', 'Android Bitmap conversion, JNI/ART, ABI packaging and Android ORT providers are untested here.']
    report['sources'] = {str(p.relative_to(ROOT)):sha(p) for p in [Path(__file__),ROOT/'checks/cpu_reference.py',ROOT/'checks/vendor_db_postprocess.py',ROOT/'checks/vendor_crop.py']}
    out.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(dict(desktopDiagnosticPassed=passed,cases=len(report['cases']),androidInference='NOT_RUN',report=str(out))))
    return 0 if passed else 1

def main():
    p=argparse.ArgumentParser()
    p.add_argument('phase', choices=['fixtures','det-input','post-det','decode','infer-det','infer-rec','compare'])
    p.add_argument('--work',type=Path,required=True)
    p.add_argument('--assets',type=Path,default=Path('/workspace/ocr-assets'))
    p.add_argument('--out',type=Path,default=ROOT/'evidence/parity-desktop.json')
    a=p.parse_args()
    if a.phase.startswith('infer-'): infer(a.phase[6:],a.work,a.assets)
    elif a.phase=='compare': return compare(a.work,a.out,a.assets)
    else: worker(a.phase,a.work,a.assets)
    return 0
if __name__=='__main__': sys.exit(main())
