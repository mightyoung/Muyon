import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/model_gateway.dart';

class OcrModelAsset {
  const OcrModelAsset(
    this.name,
    this.model,
    this.revision,
    this.remoteName,
    this.bytes,
    this.sha256Digest,
  );
  final String name, model, revision, remoteName, sha256Digest;
  final int bytes;
  Uri get uri => Uri.parse(
    'https://huggingface.co/PaddlePaddle/$model/resolve/$revision/$remoteName',
  );
}

class OcrModels {
  OcrModels(this.rootPath);
  final String rootPath;
  static const version = 'PP-OCRv5_mobile-det-e6f4fa85-rec-ed152b8b';
  static const assets = [
    OcrModelAsset(
      'det.onnx',
      'PP-OCRv5_mobile_det_onnx',
      'e6f4fa85f00e168c862bc462aebca69eef9b3d3d',
      'inference.onnx',
      4826518,
      'a431985659dc921974177a95adcfbb90fd9e51989a5e04d70d0b75f597b6e61d',
    ),
    OcrModelAsset(
      'det.yml',
      'PP-OCRv5_mobile_det_onnx',
      'e6f4fa85f00e168c862bc462aebca69eef9b3d3d',
      'inference.yml',
      903,
      '98069072e1b6b37d727fd9d9f11725faa46d6ea0de012f2ed26caea011c37699',
    ),
    OcrModelAsset(
      'rec.onnx',
      'PP-OCRv5_mobile_rec_onnx',
      'ed152b8b495f84de93cda5709d768548a9127622',
      'inference.onnx',
      16534782,
      'da72dc72ca4dc220df0dfde68c1dedc31c58d3e76a25871122e5056227d50092',
    ),
    OcrModelAsset(
      'rec.yml',
      'PP-OCRv5_mobile_rec_onnx',
      'ed152b8b495f84de93cda5709d768548a9127622',
      'inference.yml',
      148345,
      '5dfeb2777f6d0db8177d8128a8acfcf6e6276dc4ac73ea3bf0dc06d6a5e85d8e',
    ),
  ];
  String path(String name) => p.join(rootPath, name);
  Future<bool> ready() async {
    for (final asset in assets) {
      final file = File(path(asset.name));
      if (!await file.exists() ||
          await file.length() != asset.bytes ||
          (await sha256.bind(file.openRead()).first).toString() !=
              asset.sha256Digest) {
        return false;
      }
    }
    return true;
  }

  Future<void> install({ModelCancellation? cancellation}) async {
    final token = cancellation ?? ModelCancellation();
    await Directory(rootPath).create(recursive: true);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    void abort() => client.close(force: true);
    token.add(abort);
    try {
      for (final asset in assets) {
        token.check();
        final target = File(path(asset.name));
        if (await target.exists() &&
            await target.length() == asset.bytes &&
            (await sha256.bind(target.openRead()).first).toString() ==
                asset.sha256Digest) {
          continue;
        }
        final response = await (await client.getUrl(asset.uri))
            .close()
            .timeout(const Duration(minutes: 3));
        if (response.statusCode != 200) {
          throw HttpException('OCR model download ${response.statusCode}');
        }
        final part = File('${target.path}.part');
        final sink = part.openWrite();
        var count = 0;
        try {
          await for (final bytes in response.timeout(
            const Duration(seconds: 45),
          )) {
            token.check();
            count += bytes.length;
            if (count > asset.bytes) {
              throw const FormatException('OCR model size mismatch');
            }
            sink.add(bytes);
          }
          await sink.flush();
          await sink.close();
          token.check();
          if (count != asset.bytes ||
              (await sha256.bind(part.openRead()).first).toString() !=
                  asset.sha256Digest) {
            throw const FormatException('OCR model checksum mismatch');
          }
          await part.rename(target.path);
        } catch (_) {
          await sink.close();
          if (await part.exists()) await part.delete();
          rethrow;
        }
      }
    } finally {
      token.remove(abort);
      abort();
    }
  }
}
