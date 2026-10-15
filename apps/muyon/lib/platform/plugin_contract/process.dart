/// RED-stage process interface. No child, handler, permission or data access
/// occurs until the transport contract is implemented after behavioral RED.
class PluginContractProcess {
  PluginContractProcess({required this.executable,
    this.deadline = const Duration(seconds: 5)});
  final String executable;
  final Duration deadline;
  Future<Map<String, Object?>> request(Map<String, Object?> request) async =>
      const {'ok': false, 'code': 'unsupported'};
  Future<void> start() async => throw UnsupportedError('plugin process not implemented');
  Future<int>? get exitCode => null;
  int? get pid => null;
  int get pendingCount => 0;
  bool get isClosed => false;
  Future<void> close() async {}
}
