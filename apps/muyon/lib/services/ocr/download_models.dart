import 'dart:io';

import 'ocr_models.dart';

/// Reproducible development installer; uses the same verified runtime store.
Future<void> main(List<String> args) async {
  if (args.length != 1) throw ArgumentError('Pass the model cache directory');
  final models = OcrModels(args.single);
  await models.install();
  if (!await models.ready()) throw StateError('Model verification failed');
  for (final asset in OcrModels.assets) {
    stdout.writeln('${asset.name} ${asset.bytes} ${asset.sha256Digest}');
  }
}
