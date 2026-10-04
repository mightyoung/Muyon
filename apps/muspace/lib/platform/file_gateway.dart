import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:muspace_module_api/muspace_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class FileGateway implements ModuleFiles {
  FileGateway(this.rootPath);
  @override
  final String rootPath;
  static const maxBytes = 512 * 1024 * 1024;
  static const maxFiles = 10000;

  Future<String?> pickResearch({bool folder = false}) async {
    if (folder) return FilePicker.getDirectoryPath(dialogTitle: '选择研究目录');
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    return result.isEmpty ? null : result.single.path;
  }

  /// Snapshot an input without retaining a mutable external path or links.
  @override
  Future<SelectedInput> freeze(SelectedInput input) async {
    final type = FileSystemEntity.typeSync(input.path, followLinks: false);
    if (type != FileSystemEntityType.file &&
        type != FileSystemEntityType.directory) {
      throw ArgumentError('Input must be a regular file or directory');
    }
    final destination = Directory(
      p.join(rootPath, 'staging', const Uuid().v4()),
    );
    destination.createSync(recursive: true);
    var bytes = 0;
    var count = 0;
    try {
      Future<void> copy(File file, String target) async {
        if (++count > maxFiles) throw StateError('Too many input files');
        if (bytes + await file.length() > maxBytes) {
          throw StateError('Input exceeds byte limit');
        }
        final output = File(target);
        await output.parent.create(recursive: true);
        final sink = output.openWrite();
        try {
          await for (final chunk in file.openRead()) {
            bytes += chunk.length;
            if (bytes > maxBytes) {
              throw StateError('Input changed beyond byte limit');
            }
            sink.add(chunk);
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
      }

      if (type == FileSystemEntityType.file) {
        final target = p.join(destination.path, p.basename(input.path));
        await copy(File(input.path), target);
        return SelectedInput(path: target, displayName: input.displayName);
      }
      await for (final entry in Directory(
        input.path,
      ).list(recursive: true, followLinks: false)) {
        if (entry is Link) {
          throw StateError('Symbolic links are not importable');
        }
        if (entry is File) {
          await copy(
            entry,
            p.join(destination.path, p.relative(entry.path, from: input.path)),
          );
        }
      }
      return SelectedInput(
        path: destination.path,
        displayName: input.displayName,
      );
    } catch (_) {
      await destination.delete(recursive: true);
      rethrow;
    }
  }
}
