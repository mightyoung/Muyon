/// App lifecycle bridge to the currently mounted conversation presentation.
/// It neither stores UIPlans nor dispatches model or business actions.
class ConversationShellController {
  Object? _owner;
  Future<void> Function()? _checkpoint;
  void Function()? _detach;
  Future<void> Function()? _referencesSettled;
  void Function()? _stopReferenceAdmission;
  void Function()? _resumeReferenceAdmission;

  void attach(Object owner, Future<void> Function() checkpoint, void Function() detach,
      {Future<void> Function()? referencesSettled, void Function()? stopReferenceAdmission, void Function()? resumeReferenceAdmission}) {
    _owner = owner;
    _checkpoint = checkpoint;
    _detach = detach;
    _referencesSettled = referencesSettled;
    _stopReferenceAdmission = stopReferenceAdmission;
    _resumeReferenceAdmission = resumeReferenceAdmission;
  }

  void release(Object owner) {
    if (!identical(owner, _owner)) return;
    _owner = null;
    _checkpoint = null;
    _detach = null;
    _referencesSettled = null;
    _stopReferenceAdmission = null;
    _resumeReferenceAdmission = null;
  }

  Future<void> checkpoint() => _checkpoint?.call() ?? Future.value();
  void stopReferenceAdmission() => _stopReferenceAdmission?.call();
  void resumeReferenceAdmission() => _resumeReferenceAdmission?.call();
  Future<void> referencesSettled() => _referencesSettled?.call() ?? Future.value();
  void detach() => _detach?.call();
}
