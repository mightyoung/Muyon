import 'dart:convert';

import '../platform/foundation_repository.dart';
import '../workspace/workspace_repository.dart';

enum UiPresentationMode {
  automatic('automatic', '自动'),
  few('few', '少用'),
  textOnly('text_only', '只用文字');

  const UiPresentationMode(this.storageValue, this.label);
  final String storageValue, label;
}

/// Created by a host user entry point, never decoded from model output.
/// Create and freeze a new instance synchronously at each host user entry point.
final class UiPresentationRequest {
  UiPresentationRequest.ordinary() : _explicit = false;
  UiPresentationRequest.explicitControl() : _explicit = true;
  final bool _explicit;
  UiPresentationPreference? _owner;
  int? _generation;
}

/// Gates optional content presentation only, never confirmation or authorization.
final class UiPresentationPolicy {
  UiPresentationPolicy._(this.mode, this._request, this._isCurrent);
  final UiPresentationMode mode;
  final UiPresentationRequest _request;
  final bool Function() _isCurrent;

  bool allowsPlanningFor(UiPresentationRequest current) => _allows(current);
  bool allowsContentFor(UiPresentationRequest current) => _allows(current);

  bool _allows(UiPresentationRequest current) {
    if (!_isCurrent() || !identical(current, _request)) return false;
    return switch (mode) {
      UiPresentationMode.automatic => true,
      UiPresentationMode.few => _request._explicit,
      UiPresentationMode.textOnly => false,
    };
  }
}

/// Serialized persist-first state. The host closes this before its database.
final class UiPresentationPreference {
  UiPresentationPreference(FoundationRepository repository, {
    UiPresentationMode missingDefault = UiPresentationMode.textOnly,
  }) : _settings = WorkspaceRepository(repository.database) {
    _mode = _read(missingDefault);
  }

  static const key = 'assistant.uiPresentation.mode.v1';
  static const legacyKey = 'assistant.uiPlanning.enabled.v1';
  final WorkspaceRepository _settings;
  late UiPresentationMode _mode;
  int _generation = 0;
  bool _closing = false;
  Future<void> _tail = Future<void>.value();
  Future<void>? _closeFuture;

  UiPresentationMode get mode => _mode;

  UiPresentationMode _read(UiPresentationMode missingDefault) {
    try {
      final rows = _settings.database.raw.select(
        'SELECT value FROM settings WHERE key=?', [key]);
      if (rows.isNotEmpty) {
        final value = jsonDecode(rows.single['value'] as String);
        for (final mode in UiPresentationMode.values) {
          if (value == mode.storageValue) return mode;
        }
        return UiPresentationMode.textOnly;
      }
      // A legacy choice, even true, does not select a new three-tier policy.
      final legacy = _settings.database.raw.select(
        'SELECT 1 FROM settings WHERE key=?', [legacyKey]);
      return legacy.isEmpty ? missingDefault : UiPresentationMode.textOnly;
    } catch (_) {
      return UiPresentationMode.textOnly;
    }
  }

  UiPresentationPolicy freezeFor(UiPresentationRequest request) {
    final generation = _generation;
    // The first freeze binds this host flag permanently. Mode changes, restart
    // or another preference owner cannot turn an old flag into a fresh request.
    if (request._owner == null) {
      request._owner = this;
      request._generation = generation;
    }
    return UiPresentationPolicy._(_mode, request,
      () => !_closing && generation == _generation &&
        identical(request._owner, this) && request._generation == generation);
  }

  Future<void> save(UiPresentationMode mode) {
    if (_closing) return Future.error(StateError('Presentation settings are closing'));
    final operation = _tail.then<void>((_) async {
      await _settings.setSetting(key, mode.storageValue);
      _mode = mode;
      _generation++;
    });
    // A failed save reaches its caller while subsequent saves remain usable.
    _tail = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  Future<void> close() {
    _closing = true;
    return _closeFuture ??= _tail;
  }
}
