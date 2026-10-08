import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:uuid/uuid.dart';

import '../../app/host_ui_grant_authority.dart' show HostUiGrantToken;

enum AssistantAuthorizationMode { standard, readOnly, custom }

enum AssistantAuthorizationCategory { read, model, write, outbound }

/// A host setting can only tighten the baseline. It never supplies a grant.
final class HostPolicySnapshot {
  HostPolicySnapshot._(this.mode, this.enabled, this.revision, this.valid);
  final AssistantAuthorizationMode mode;
  final Set<AssistantAuthorizationCategory> enabled;
  final String revision;
  final bool valid;

  bool allows(AssistantAuthorizationCategory category) =>
      valid &&
      enabled.contains(category) &&
      !(mode == AssistantAuthorizationMode.readOnly &&
          (category == AssistantAuthorizationCategory.write ||
              category == AssistantAuthorizationCategory.outbound));

  bool allowsTool(ToolEffect effect) => allows(switch (effect) {
    ToolEffect.read => AssistantAuthorizationCategory.read,
    ToolEffect.write => AssistantAuthorizationCategory.write,
    ToolEffect.export ||
    ToolEffect.network => AssistantAuthorizationCategory.outbound,
  });
}

class _PolicyChanges {
  final pending = <Object>{};
  bool failed = false;
  final listeners = <void Function()>{};
}

/// Host-owned, absent from module registrars and model tools. Existing corrupt
/// settings fail closed; only an absent setting selects the standard default.
final class HostAuthorizationPolicy {
  HostAuthorizationPolicy(this.database);
  final ManagedDatabase database;
  static const settingKey = 'auth1b:policy';
  static final _changes = Expando<_PolicyChanges>();
  _PolicyChanges get _state => _changes[database] ??= _PolicyChanges();
  void Function() onChange(void Function() listener) {
    _state.listeners.add(listener);
    return () => _state.listeners.remove(listener);
  }

  static String _digest(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  HostPolicySnapshot get current {
    final rows = database.raw.select('SELECT value FROM settings WHERE key=?', [
      settingKey,
    ]);
    final raw = rows.isEmpty ? null : rows.single['value'];
    final revision = _digest(raw == null ? 'absent:standard-v1' : '$raw');
    HostPolicySnapshot closed() => HostPolicySnapshot._(
      AssistantAuthorizationMode.custom,
      const {},
      revision,
      false,
    );
    if (_state.pending.isNotEmpty || _state.failed) return closed();
    if (rows.isEmpty) {
      return HostPolicySnapshot._(
        AssistantAuthorizationMode.standard,
        Set.unmodifiable(AssistantAuthorizationCategory.values),
        revision,
        true,
      );
    }
    try {
      final value = jsonDecode(raw as String);
      if (value is! Map ||
          value['version'] != 1 ||
          value['revision'] is! int ||
          (value['revision'] as int) < 1) {
        return closed();
      }
      final mode = AssistantAuthorizationMode.values.asNameMap()[value['mode']];
      if (mode == null ||
          AssistantAuthorizationCategory.values.any(
            (category) => value[category.name] is! bool,
          )) {
        return closed();
      }
      return HostPolicySnapshot._(
        mode,
        Set.unmodifiable([
          for (final category in AssistantAuthorizationCategory.values)
            if (value[category.name] == true) category,
        ]),
        revision,
        true,
      );
    } catch (_) {
      return closed();
    }
  }

  Future<void> update({
    required HostUiGrantToken token,
    required AssistantAuthorizationMode mode,
    required Set<AssistantAuthorizationCategory> enabled,
  }) async {
    token.checkActive();
    final categories = Set<AssistantAuthorizationCategory>.unmodifiable(
      enabled,
    );
    final operation = Object();
    // Latch before queuing; a failed write cannot reopen queued permissions.
    _state.pending.add(operation);
    for (final listener in _state.listeners.toList()) {
      listener();
    }
    try {
      await database.write((db) {
        token.checkActive();
        var serial = 0;
        try {
          final rows = db.select('SELECT value FROM settings WHERE key=?', [
            settingKey,
          ]);
          if (rows.isNotEmpty) {
            final old = jsonDecode(rows.single['value'] as String);
            if (old is Map && old['revision'] is int && old['revision'] > 0) {
              serial = old['revision'] as int;
            }
          }
        } catch (_) {
          // A confirmed host interaction may replace a corrupt setting.
        }
        db.execute(
          'INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
          [
            settingKey,
            jsonEncode({
              'version': 1,
              'revision': serial + 1,
              // Identity of this real confirmed host mutation, so corrupt
              // serial metadata cannot revive a former policy capability.
              'changeId': const Uuid().v4(),
              'mode': mode.name,
              for (final category in AssistantAuthorizationCategory.values)
                category.name: categories.contains(category),
            }),
          ],
        );
      });
      _state.failed = false;
    } catch (_) {
      _state.failed = true;
      rethrow;
    } finally {
      _state.pending.remove(operation);
    }
  }
}
