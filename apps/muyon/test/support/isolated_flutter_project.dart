import 'dart:convert';
import 'dart:io';

/// A child Flutter invocation must never rebuild the running parent's assets.
/// Sources and pub packages are reused; generated output and native hook download
/// snapshots belong to this disposable project only. No pub get is run here.
final class IsolatedFlutterProject {
  IsolatedFlutterProject._(this.directory);

  final Directory directory;

  static IsolatedFlutterProject create() {
    final source = Directory.current.absolute;
    var owner = source;
    while (!File('${owner.path}/.dart_tool/package_config.json').existsSync()) {
      final parent = owner.parent;
      if (parent.path == owner.path) {
        throw StateError('No resolved workspace package_config.json');
      }
      owner = parent;
    }
    final originalConfig = File('${owner.path}/.dart_tool/package_config.json');
    final config =
        jsonDecode(originalConfig.readAsStringSync()) as Map<String, dynamic>;
    final directory = Directory.systemTemp.createTempSync(
      'le06-flutter-project-',
    );
    try {
      File('${directory.path}/pubspec.yaml').writeAsStringSync(
        File('${source.path}/pubspec.yaml')
            .readAsStringSync()
            .replaceFirst('resolution: workspace\n', ''),
      );
      for (final name in ['lib', 'test', 'assets']) {
        Link('${directory.path}/$name').createSync('${source.path}/$name');
      }
      for (final raw in config['packages'] as List<dynamic>) {
        final package = raw as Map<String, dynamic>;
        package['rootUri'] = package['name'] == 'muyon'
            ? directory.uri.toString()
            : originalConfig.uri
                  .resolve(package['rootUri'] as String)
                  .toString();
      }
      final tool = Directory('${directory.path}/.dart_tool')..createSync();
      File('${tool.path}/package_config.json')
          .writeAsStringSync(jsonEncode(config));
      File('${owner.path}/.dart_tool/package_graph.json')
          .copySync('${tool.path}/package_graph.json');
      // Hooks may need their already-downloaded libraries with proxies cleared.
      // Copy bytes, never symlink hook outputs back into the active workspace.
      final shared = Directory('${owner.path}/.dart_tool/hooks_runner/shared');
      if (shared.existsSync()) {
        _copyDirectory(shared, Directory('${tool.path}/hooks_runner/shared'));
      }
      return IsolatedFlutterProject._(directory);
    } catch (_) {
      directory.deleteSync(recursive: true);
      rethrow;
    }
  }

  static void _copyDirectory(Directory source, Directory target) {
    target.createSync(recursive: true);
    for (final entry in source.listSync(followLinks: false)) {
      final name = entry.uri.pathSegments.where((part) => part.isNotEmpty).last;
      if (entry is Directory) {
        _copyDirectory(entry, Directory('${target.path}/$name'));
      } else if (entry is File) {
        entry.copySync('${target.path}/$name');
      } else {
        throw StateError(
          'Unexpected link in hook download snapshot: ${entry.path}',
        );
      }
    }
  }

  void dispose() => directory.deleteSync(recursive: true);
}
