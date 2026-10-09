import 'dart:js_interop';

import 'package:web/web.dart' as web;
import 'package:muyon_module_api/ui_contract.dart';

import 'workspace_store.dart';

/// Web Locks serialize same-origin writers across tabs. localStorage.setItem
/// is the single durable replacement: quota/permission errors retain old data.
class BrowserWorkspaceStore extends FixtureWorkspaceStore {
  BrowserWorkspaceStore()
    : super(
        read: (key) => web.window.localStorage.getItem(key),
        write: (key, value) => web.window.localStorage.setItem(key, value),
      );
  @override
  Future<bool> save(
    StoredUiWorkspace value, {
    required int expectedRevision,
  }) async {
    final result = await web.window.navigator.locks
        .request(
          key(value.surfaceId),
          ((web.Lock lock) {
            return super
                .save(value, expectedRevision: expectedRevision)
                .then((ok) => ok.toJS)
                .toJS;
          }).toJS,
        )
        .toDart;
    return (result as JSBoolean).toDart;
  }
}

UiWorkspaceStore createBrowserWorkspaceStore() => BrowserWorkspaceStore();
