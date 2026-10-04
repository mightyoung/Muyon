import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'package:yaml/yaml.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models/model_gateway.dart';
import 'ocr_geometry.dart';
import 'ocr_models.dart';

class OcrLine {
  const OcrLine({
    required this.text,
    required this.confidence,
    required this.detectionConfidence,
    required this.points,
  });
  final String text;
  final double confidence, detectionConfidence;
  final List<OcrPoint> points;
}

class OcrResult {
  const OcrResult({
    required this.lines,
    required this.sourceDigest,
    required this.width,
    required this.height,
    required this.pageIndex,
    required this.exifOrientation,
  });
  final List<OcrLine> lines;
  final String sourceDigest;
  final int width, height, pageIndex, exifOrientation;
  String get text => lines.map((l) => l.text).join('\n');
  String get modelVersion => OcrModels.version;
  String get algorithmVersion => 'db-hull-minrect-unclip-homography-ctc-v1';

  /// Coordinates are in the EXIF-oriented image; orientation is retained for
  /// consumers mapping back to the original encoded pixel plane.
  String get coordinateSpace => 'exif-oriented-image';
}

class OcrPdfPage {
  const OcrPdfPage(this.pageIndex, this.text, this.ocr);
  final int pageIndex;
  final String text;
  final OcrResult? ocr;
}

class PaddleOcrService {
  PaddleOcrService(this.models, {this.referenceInference});

  /// Optional numerical validation backend. Shipping callers use native ORT.
  final Future<(List<int>, List<double>)> Function(
    String modelPath,
    Float32List input,
    List<int> shape,
  )?
  referenceInference;
  final OcrModels models;
  OrtSession? _det, _rec;
  List<String>? _dictionary;
  Future<void> _tail = Future.value();
  bool _closed = false;
  Future<bool> available() => models.ready();
  Future<void> installModels({ModelCancellation? cancellation}) =>
      models.install(cancellation: cancellation);

  /// Native text is retained; only pages without text are rasterized for OCR.
  Future<List<OcrPdfPage>> recognizePdf(
    String path, {
    ModelCancellation? cancellation,
  }) async {
    final token = cancellation ?? ModelCancellation();
    token.check();
    if (await File(path).length() > 128 * 1024 * 1024) {
      throw StateError('PDF exceeds 128 MiB');
    }
    await pdfrxFlutterInitialize();
    final pdf = await PdfDocument.openFile(path);
    final scratch = await Directory.systemTemp.createTemp('miyono-ocr-pages-');
    try {
      if (pdf.pages.length > 200) {
        throw StateError('PDF OCR limited to 200 pages');
      }
      final pages = <OcrPdfPage>[];
      for (var i = 0; i < pdf.pages.length; i++) {
        token.check();
        final page = pdf.pages[i],
            text = (await page.loadText())?.fullText ?? '';
        if (text.trim().isNotEmpty) {
          pages.add(OcrPdfPage(i, text, null));
          continue;
        }
        final scale = math.min(2.0, 2048 / math.max(page.width, page.height));
        final width = (page.width * scale).round(),
            height = (page.height * scale).round();
        final image = await page.render(
          width: width,
          height: height,
          fullWidth: width.toDouble(),
          fullHeight: height.toDouble(),
          backgroundColor: 0xffffffff,
        );
        if (image == null) throw StateError('PDF page rendering failed');
        final frame = File('${scratch.path}/page-$i.png');
        try {
          final decoded = img.Image.fromBytes(
            width: image.width,
            height: image.height,
            bytes: image.pixels.buffer,
            bytesOffset: image.pixels.offsetInBytes,
            order: img.ChannelOrder.bgra,
            numChannels: 4,
          );
          await frame.writeAsBytes(img.encodePng(decoded));
        } finally {
          image.dispose();
        }
        token.check();
        final result = await recognize(
          frame.path,
          pageIndex: i,
          cancellation: token,
        );
        await frame.delete();
        pages.add(OcrPdfPage(i, result.text, result));
      }
      token.check();
      return pages;
    } finally {
      await pdf.dispose();
      await scratch.delete(recursive: true);
    }
  }

  Future<void> _open() async {
    if (_closed) throw StateError('OCR service closed');
    if (_dictionary != null &&
        (referenceInference != null || (_det != null && _rec != null))) {
      return;
    }
    if (!await models.ready()) {
      throw StateError(
        'OCR models missing or checksum invalid; install verified models',
      );
    }
    final config =
        loadYaml(await File(models.path('rec.yml')).readAsString()) as YamlMap;
    final post = config['PostProcess'] as YamlMap;
    final raw = post['character_dict'] as YamlList;
    final dictionary = ['', ...raw.cast<String>(), ' '];
    if (dictionary.length != 18385) {
      throw StateError('OCR dictionary does not match 18385 model classes');
    }
    _dictionary = List.unmodifiable(dictionary);
    if (referenceInference != null) return;
    final ort = OnnxRuntime();
    _det = await ort.createSession(models.path('det.onnx'));
    try {
      _rec = await ort.createSession(models.path('rec.onnx'));
    } catch (_) {
      await _det?.close();
      _det = null;
      rethrow;
    }
  }

  Future<OcrResult> recognize(
    String path, {
    int pageIndex = 0,
    ModelCancellation? cancellation,
  }) {
    final token = cancellation ?? ModelCancellation();
    final completer = Completer<OcrResult>();
    _tail = _tail.then((_) async {
      try {
        token.check();
        completer.complete(await _recognize(path, pageIndex, token));
      } catch (e, s) {
        completer.completeError(e, s);
      }
    });
    return completer.future;
  }

  Future<(List<int>, List<double>)> _infer(
    OrtSession? session,
    String model,
    Float32List data,
    List<int> shape,
    ModelCancellation token,
  ) async {
    if (referenceInference != null) {
      token.check();
      final result = await referenceInference!(models.path(model), data, shape);
      token.check();
      return result;
    }
    token.check();
    OrtValue? input;
    Map<String, OrtValue> outputs = {};
    try {
      input = await OrtValue.fromList(data, shape);
      outputs = await session!.run({'x': input});
      token.check();
      final value = outputs['fetch_name_0'];
      if (value == null) throw StateError('OCR output missing');
      final flat = await value.asFlattenedList();
      token.check();
      return (
        List<int>.from(value.shape),
        flat.map((v) => (v as num).toDouble()).toList(),
      );
    } finally {
      for (final value in outputs.values) {
        await value.dispose();
      }
      await input?.dispose();
    }
  }

  static Float32List normalizedBgr(
    img.Image image, {
    required bool detection,
    int? paddedWidth,
  }) {
    final width = paddedWidth ?? image.width, plane = width * image.height;
    final result = Float32List(plane * 3);
    const mean = [.485, .456, .406], std = [.229, .224, .225];
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y),
            bgr = [pixel.b.toDouble(), pixel.g.toDouble(), pixel.r.toDouble()];
        for (var c = 0; c < 3; c++) {
          result[c * plane + y * width + x] = detection
              ? (bgr[c] / 255 - mean[c]) / std[c]
              : bgr[c] / 127.5 - 1;
        }
      }
    }
    return result;
  }

  static (String, double) ctcDecode(
    List<double> probabilities,
    int steps,
    int classes,
    List<String> dictionary,
  ) {
    if (classes != dictionary.length ||
        probabilities.length != steps * classes) {
      throw const FormatException('OCR class shape mismatch');
    }
    var previous = -1, score = 0.0, count = 0;
    final text = StringBuffer();
    for (var t = 0; t < steps; t++) {
      var index = 0, best = double.negativeInfinity;
      for (var c = 0; c < classes; c++) {
        final value = probabilities[t * classes + c];
        if (!value.isFinite) {
          throw const FormatException('Invalid OCR probabilities');
        }
        if (value > best) {
          best = value;
          index = c;
        }
      }
      if (index != 0 && index != previous) {
        text.write(dictionary[index]);
        score += best;
        count++;
      }
      previous = index;
    }
    return (text.toString(), count == 0 ? 0 : score / count);
  }

  Future<OcrResult> _recognize(
    String path,
    int pageIndex,
    ModelCancellation token,
  ) async {
    if (pageIndex < 0) throw ArgumentError('Negative page');
    final file = File(path);
    if (await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.file ||
        await file.length() > 32 * 1024 * 1024) {
      throw StateError('OCR input missing or exceeds 32 MiB');
    }
    final bytes = await file.readAsBytes();
    token.check();
    final decoder = img.findDecoderForData(bytes),
        info = decoder?.startDecode(bytes);
    if (info == null ||
        info.width * info.height > 20000000 ||
        info.width <= 0 ||
        info.height <= 0) {
      throw StateError('OCR image exceeds 20 million pixels or is unsupported');
    }
    final decoded = decoder!.decodeFrame(0);
    if (decoded == null) throw StateError('OCR image decoding failed');
    final orientation = decoded.exif.imageIfd.orientation ?? 1;
    final source = img.bakeOrientation(decoded);
    await _open();
    token.check();
    final ratio = 960 / math.max(source.width, source.height);
    final dw = math.max(32, (source.width * ratio / 32).round() * 32),
        dh = math.max(32, (source.height * ratio / 32).round() * 32);
    final resized = img.copyResize(
      source,
      width: dw,
      height: dh,
      interpolation: img.Interpolation.linear,
    );
    final (shape, map) = await _infer(
      _det,
      'det.onnx',
      normalizedBgr(resized, detection: true),
      [1, 3, dh, dw],
      token,
    );
    if (shape.length != 4 || shape[0] != 1 || shape[1] != 1) {
      throw StateError('OCR detector shape mismatch');
    }
    final boxes = detectBoxes(
      map,
      shape[3],
      shape[2],
      source.width,
      source.height,
    );
    final lines = <OcrLine>[];
    for (final box in boxes) {
      token.check();
      final crop = perspectiveCrop(source, box.points);
      final width = (48 * crop.width / crop.height).ceil().clamp(1, 1920),
          padded = math.max(320, width);
      final input = img.copyResize(
        crop,
        width: width,
        height: 48,
        interpolation: img.Interpolation.linear,
      );
      final (rs, values) = await _infer(
        _rec,
        'rec.onnx',
        normalizedBgr(input, detection: false, paddedWidth: padded),
        [1, 3, 48, padded],
        token,
      );
      if (rs.length != 3 || rs[0] != 1 || rs[2] != 18385) {
        throw StateError('OCR recognizer shape mismatch');
      }
      final (text, confidence) = ctcDecode(values, rs[1], rs[2], _dictionary!);
      if (text.isNotEmpty) {
        lines.add(
          OcrLine(
            text: text,
            confidence: confidence,
            detectionConfidence: box.score,
            points: List.unmodifiable(box.points),
          ),
        );
      }
    }
    token.check();
    return OcrResult(
      lines: List.unmodifiable(lines),
      sourceDigest: sha256.convert(bytes).toString(),
      width: source.width,
      height: source.height,
      pageIndex: pageIndex,
      exifOrientation: orientation,
    );
  }

  Future<void> close() async {
    _closed = true;
    await _tail;
    try {
      await _det?.close();
    } finally {
      await _rec?.close();
      _det = null;
      _rec = null;
    }
  }
}
