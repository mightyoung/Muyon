import 'dart:convert';
import 'dart:io';

import 'north_star_settings.dart';

/// Writes [evidence] to `MUYON_EVIDENCE_OUT` when set (relative paths resolve
/// against [baseDir] when given) and prints it in numbered chunks so it
/// survives device log line limits. Returns the written path, if any.
Future<String?> publishNorthStarEvidence(
  Map<String, Object?> evidence, {
  String? baseDir,
  void Function(String line) log = print,
}) async {
  final text = jsonEncode(evidence);
  const size = 700;
  final chunks = (text.length + size - 1) ~/ size;
  for (var i = 0; i < chunks; i++) {
    final end = (i + 1) * size < text.length ? (i + 1) * size : text.length;
    log(
      'MUYON_NORTH_STAR_EVIDENCE[${i + 1}/$chunks] ${text.substring(i * size, end)}',
    );
  }
  final out = northStarSetting('MUYON_EVIDENCE_OUT');
  if (out == null) return null;
  final path = File(out).isAbsolute || baseDir == null ? out : '$baseDir/$out';
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(evidence),
  );
  log('MUYON_NORTH_STAR_EVIDENCE_FILE $path');
  return path;
}
