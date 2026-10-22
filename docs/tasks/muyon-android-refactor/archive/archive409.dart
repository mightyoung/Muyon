// Uses the exact archive version pinned by the existing research exporter.
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';

void main(List<String> args) {
  final archive = Archive();
  final entries = <String, List<int>>{
    'manifest.json': utf8.encode('{"packageType":"muyon-research","schemaVersion":1}'),
    'project.json': utf8.encode('{"originProjectKey":"p"}'),
    '论文/测试.json': utf8.encode('{"title":"sample"}'),
  };
  entries.forEach((name, bytes) => archive.addFile(ArchiveFile(name, bytes.length, bytes)));
  final encoded = ZipEncoder().encode(archive, modified: DateTime.utc(2026, 1, 1));
  File(args.single).writeAsBytesSync(encoded);
  final decoded = ZipDecoder().decodeBytes(encoded, verify: true);
  for (final file in decoded) {
    if (utf8.decode(file.content) != utf8.decode(entries[file.name]!)) {
      throw StateError('round-trip mismatch');
    }
  }
  print('archive 4.0.9 round-trip: ${decoded.length} entries, ${encoded.length} bytes');
}
