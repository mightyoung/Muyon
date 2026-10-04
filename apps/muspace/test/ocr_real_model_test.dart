import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:muspace/services/ocr/ocr_models.dart';
import 'package:muspace/services/ocr/paddle_ocr_service.dart';

void main() {
  final modelDir = Platform.environment['MIYONO_OCR_MODEL_DIR'];
  test(
    'real fixed ONNX models with Dart BGR/DB/homography/CTC pipeline',
    () async {
      final root = Directory.systemTemp.createTempSync('miyono-real-ocr-');
      Pdfrx.cacheDirectoryPath = root.path;
      addTearDown(() => root.deleteSync(recursive: true));
      final python = Platform.environment['MIYONO_OCR_PYTHON']!;
      final script = '${Directory.current.path}/test/ocr_reference.py';
      final fixture = '${root.path}/invoice.png';
      final render = await Process.run(python, [
        script,
        'render',
        fixture,
        '${Directory.current.path}/assets/fonts/NotoSansSC-VF.ttf',
      ]);
      expect(render.exitCode, 0, reason: '${render.stderr}');
      var calls = 0;
      final service = PaddleOcrService(
        OcrModels(modelDir!),
        referenceInference: (model, input, shape) async {
          final path = '${root.path}/input-${calls++}';
          await File(path).writeAsBytes(
            input.buffer.asUint8List(input.offsetInBytes, input.lengthInBytes),
          );
          final result = await Process.run(python, [
            script,
            model,
            path,
            jsonEncode(shape),
            '$path.out',
          ]);
          expect(result.exitCode, 0, reason: '${result.stderr}');
          final meta = jsonDecode(result.stdout as String) as Map;
          expect(meta['runtime'], '1.23.0');
          final bytes = await File('$path.out').readAsBytes();
          return (
            (meta['shape'] as List).cast<int>(),
            Float32List.view(
              bytes.buffer,
              bytes.offsetInBytes,
              bytes.lengthInBytes ~/ 4,
            ).map((v) => v.toDouble()).toList(),
          );
        },
      );
      addTearDown(service.close);
      final result = await service.recognize(fixture);
      stdout.writeln(
        jsonEncode({
          'backend': 'Python ORT1.23 reference, Dart production preprocessing/postprocessing',
          'calls': calls,
          'text': result.text,
          'lines': [
            for (final line in result.lines)
              {
                'text': line.text,
                'confidence': line.confidence,
                'points': [
                  for (final point in line.points) [point.x, point.y],
                ],
              },
          ],
        }),
      );
      expect(result.text, contains('123.45'));
      expect(result.text, contains('678.90'));
      expect(result.text, contains('材料'));
      expect(
        result.lines.every(
          (line) =>
              line.points.length == 4 &&
              line.confidence > 0 &&
              line.confidence <= 1,
        ),
        isTrue,
      );
      final rotated = await service.recognize('$fixture.rotated.png');
      expect(rotated.text, contains('123.45'));
      expect(rotated.text, contains('678.90'));
      final scanned = await service.recognizePdf('$fixture.pdf');
      expect(scanned.single.ocr, isNotNull);
      expect(scanned.single.text, contains('123.45'));
      expect(scanned.single.text, contains('678.90'));
    },
    skip: modelDir == null
        ? 'Set MIYONO_OCR_MODEL_DIR and MIYONO_OCR_PYTHON for real CPU validation'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
