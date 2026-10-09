/// App lifecycle bridge to the currently mounted conversation presentation.
/// It neither stores UIPlans nor dispatches model or business actions.
class ConversationShellController {
  Object? _owner;
  Future<void> Function()? _checkpoint;
  void Function()? _detach;
  Future<void> Function()? _referencesSettled;

  void attach(Object owner, Future<void> Function() checkpoint, void Function() detach,
      {Future<void> Function()? referencesSettled}) {
    _owner = owner;
    _checkpoint = checkpoint;
    _detach = detach;
    _referencesSettled = referencesSettled;
  }

  void release(Object owner) {
    if (!identical(owner, _owner)) return;
    _owner = null;
    _checkpoint = null;
    _detach = null;
    _referencesSettled = null;
  }

  Future<void> checkpoint() => _checkpoint?.call() ?? Future.value();
  Future<void> referencesSettled() => _referencesSettled?.call() ?? Future.value();
  void detach() => _detach?.call();
}
