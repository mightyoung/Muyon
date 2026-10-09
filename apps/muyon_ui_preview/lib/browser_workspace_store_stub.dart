import 'workspace_store.dart';

FixtureWorkspaceStore createBrowserWorkspaceStore() {
  final memory = <String, String>{};
  return FixtureWorkspaceStore(
    read: (key) => memory[key],
    write: (key, value) {
      memory[key] = value;
    },
  );
}
