"""Real ORT 1.23 numerical backend for Dart OCR pipeline validation only."""
import json
import sys
from pathlib import Path
import numpy as np
import onnxruntime as ort

if sys.argv[1] == 'render':
    from PIL import Image, ImageDraw, ImageFont
    image = Image.new('RGB', (900, 250), 'white')
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(sys.argv[3], 38)
    draw.text((45, 35), 'Miyono invoice 123.45', fill='black', font=font)
    draw.text((45, 110), '材料采购 金额 678.90', fill=(10, 40, 180), font=font)
    image.save(sys.argv[2])
    image.save(sys.argv[2] + '.pdf', resolution=144)
    image.rotate(12, expand=True, fillcolor='white').save(sys.argv[2] + '.rotated.png')
else:
    model, input_path, shape_json, output_path = sys.argv[1:]
    opts = ort.SessionOptions()
    opts.intra_op_num_threads = 2
    session = ort.InferenceSession(model, sess_options=opts, providers=['CPUExecutionProvider'])
    x = np.fromfile(input_path, dtype='<f4').reshape(json.loads(shape_json))
    output = session.run(None, {'x': x})[0].astype('<f4')
    output.tofile(output_path)
    print(json.dumps({'shape': list(output.shape), 'runtime': ort.__version__}))
