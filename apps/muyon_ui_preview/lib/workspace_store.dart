import 'dart:convert';

import 'package:muyon_module_api/ui_contract.dart';

/// Public synthetic projection only. The browser adapter uses this same
/// contract and codec; it does not open or migrate any product database.
class FixtureWorkspaceStore implements UiWorkspaceStore {
  FixtureWorkspaceStore({required this.read, required this.write});
  final String? Function(String) read;
  final void Function(String, String) write;
  String key(String surface) => 'muyon-public-workspace:${jsonEncode(surface)}';
  @override
  Future<StoredUiWorkspace?> load(String surfaceId) async {
    final raw = read(key(surfaceId));
    return raw == null
        ? null
        : StoredUiWorkspace.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<bool> save(
    StoredUiWorkspace value, {
    required int expectedRevision,
  }) async {
    final raw = read(key(value.surfaceId));
    final old = raw == null
        ? null
        : StoredUiWorkspace.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    if ((old?.revision ?? 0) != expectedRevision ||
        value.revision != expectedRevision + 1 ||
        (old != null &&
            (old.taskId != value.taskId || old.scopeKey != value.scopeKey))) {
      return false;
    }
    write(key(value.surfaceId), jsonEncode(value.toJson()));
    return true;
  }
}
