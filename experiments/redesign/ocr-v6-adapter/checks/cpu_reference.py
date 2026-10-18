"""Real desktop det/rec diagnostic, not Android parity or a production Python backend.

Detection normalization and recognition RGB normalization follow the pinned Android
SDK. DB polygon processing and perspective crop reuse pinned upstream functions.
This reference differs from Android's PolygonUnclip and must not certify parity.
"""
import hashlib
import json
import math
from pathlib import Path
import time
import numpy as np
import cv2
import onnxruntime as ort
import yaml
from PIL import Image, ImageDraw, ImageFont
from asset_cache import fetch
from vendor_db_postprocess import DBPostProcess
from vendor_crop import get_rotate_crop_image


def samples():
    font_path=Path('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc')
    font=ImageFont.truetype(str(font_path),48)
    images={}
    for name,text,color in [('english','Total 123.45',(0,0,0)),('chinese','材料采购 金额 678.90',(0,0,0)),('color','材料 Total 678.90',(10,40,180)),('blank','',(0,0,0))]:
        image=Image.new('RGB',(900,220),'white')
        ImageDraw.Draw(image).text((45,60),text,font=font,fill=color)
        images[name]=cv2.cvtColor(np.array(image),cv2.COLOR_RGB2BGR)
    images['rotated']=cv2.warpAffine(images['english'],cv2.getRotationMatrix2D((450,110),12,1),(900,220),borderValue=(255,255,255))
    return images,dict(path=str(font_path),sha256=hashlib.sha256(font_path.read_bytes()).hexdigest())


def preprocess_det(bgr):
    h,w=bgr.shape[:2]
    ratio=max(1.,64/min(h,w))
    new_h,new_w=int(h*ratio),int(w*ratio)
    if max(new_h,new_w)>4000:
        ratio=4000/max(new_h,new_w);new_h=int(new_h*ratio);new_w=int(new_w*ratio)
    new_h=max(round(new_h/32)*32,32);new_w=max(round(new_w/32)*32,32)
    image=cv2.resize(bgr,(new_w,new_h)).astype('float32')
    image=(image/255-np.array([.485,.456,.406],dtype='float32'))/np.array([.229,.224,.225],dtype='float32')
    return np.ascontiguousarray(image.transpose(2,0,1)[None])


def preprocess_rec(bgr):
    h,w=bgr.shape[:2];new_w=min(math.ceil(48*w/h),3200)
    rgb=cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB)
    image=cv2.resize(rgb,(new_w,48)).astype('float32')/127.5-1
    return np.ascontiguousarray(image.transpose(2,0,1)[None])


def decode(output,characters):
    assert output.ndim==3 and output.shape[0]==1 and output.shape[2]==len(characters)+1
    ids=output[0].argmax(axis=-1);scores=output[0].max(axis=-1)
    kept=[i for i,c in enumerate(ids) if c and (i==0 or c!=ids[i-1])]
    return ''.join(characters[ids[i]-1] for i in kept),float(scores[kept].mean()) if kept else 0.


def infer(det,rec,characters,image):
    hashes=hashlib.sha256();h,w=image.shape[:2]
    prediction=det.run(None,{'x':preprocess_det(image)})[0];hashes.update(prediction.tobytes())
    assert np.isfinite(prediction).all()
    post=DBPostProcess(thresh=.3,box_thresh=.6,max_candidates=3000,unclip_ratio=1.5)
    boxes=post({'maps':prediction},[[h,w,1,1]])[0]['points']
    boxes=sorted(boxes,key=lambda b:(float(b[0][1]),float(b[0][0])))
    texts=[];confidences=[]
    for box in boxes:
        crop=get_rotate_crop_image(image,box.astype('float32'))
        output=rec.run(None,{'x':preprocess_rec(crop)})[0];hashes.update(output.tobytes())
        assert np.isfinite(output).all()
        text,score=decode(output,characters);texts.append(text);confidences.append(score)
    return dict(text=texts,boxes=[b.tolist() for b in boxes],recognitionConfidence=confidences,tensorSha256=hashes.hexdigest())


def evaluate(cache):
    fetch(cache)
    images,font=samples()
    report=dict(runtime=ort.__version__,opencv=cv2.__version__,provider='CPUExecutionProvider',
        reference='desktop NumPy/OpenCV diagnostic, not Android runtime parity',font=font,models={})
    for size in ['tiny','small']:
        opts=ort.SessionOptions();opts.intra_op_num_threads=2;opts.inter_op_num_threads=1
        det=ort.InferenceSession(str(cache/f'PP-OCRv6_{size}_det_onnx/inference.onnx'),opts,providers=['CPUExecutionProvider'])
        rec=ort.InferenceSession(str(cache/f'PP-OCRv6_{size}_rec_onnx/inference.onnx'),opts,providers=['CPUExecutionProvider'])
        cfg=yaml.safe_load((cache/f'PP-OCRv6_{size}_rec_onnx/inference.yml').read_text())
        characters=cfg['PostProcess']['character_dict']
        if characters[-1]!=' ':characters=characters+[' ']
        pages={}
        for name,image in images.items():
            started=time.perf_counter();first=infer(det,rec,characters,image)
            elapsed=(time.perf_counter()-started)*1000
            second=infer(det,rec,characters,image)
            first['deterministic']=first==second;first['desktopElapsedMs']=elapsed
            first['inputPixelsSha256']=hashlib.sha256(image.tobytes()).hexdigest()
            pages[name]=first
        report['models'][size]=pages
    return report

if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser();parser.add_argument('cache',type=Path)
    print(json.dumps(evaluate(parser.parse_args().cache),ensure_ascii=False,indent=2))
