import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

/// Capability ids the host registers (`bootstrap.dart`). A v2 manifest asking
/// for any other id is rejected by the registry before activation.
const hostCapabilityIds = {'knowledge', 'models', 'ocr', 'transfer', 'tools'};

/// One recorded decision on one requested capability (ADR-0004 §6.2).
class GrantDecision {
  const GrantDecision({
    required this.moduleId,
    required this.capability,
    required this.required,
    required this.reason,
    required this.granted,
    required this.policy,
  });
  final String moduleId, capability, reason, policy;

  /// The module declared it cannot work without it.
  final bool required;
  final bool granted;
}

/// The static grant policy. No user interface in the second phase; the table
/// is code. The policy only ever narrows: a request it does not know is
/// denied.
abstract final class GrantPolicy {
  /// Why a capability that needs a scoped facade is refused for v2 modules.
  static const facadePending =
      'facade-pending: needs a facade scoped to the module (ADR-0004 §6.2)';

  /// Decisions for a v2 manifest. [revoked] capabilities stay denied.
  static List<GrantDecision> decide(
    ModuleManifest manifest, {
    Set<String> revoked = const {},
  }) => [
    for (final request in manifest.capabilities)
      _decide(manifest, request, revoked.contains(request.id)),
  ];

  static GrantDecision _decide(
    ModuleManifest manifest,
    CapabilityRequest request,
    bool revoked,
  ) {
    final (granted, policy) = revoked
        ? (false, 'revoked')
        : switch (request.id) {
            'ocr' => (true, 'auto'),
            'transfer' =>
              manifest.features.contains(ModuleFeature.exchange)
                  ? (true, 'feature-exchange')
                  : (false, 'needs-feature-exchange'),
            // The registered providers are the whole KnowledgeService and
            // the raw model gateway. Handing those to a v2 module would undo
            // D2, and the scoped facades are not built yet, so deny.
            'knowledge' || 'models' => (false, facadePending),
            // v2 modules declare tools through ToolRegistrar instead.
            'tools' => (false, 'v2-uses-tool-registrar'),
            _ => (false, 'unknown-capability'),
          };
    return GrantDecision(
      moduleId: manifest.id,
      capability: request.id,
      required: request.required,
      reason: request.reason,
      granted: granted,
      policy: policy,
    );
  }

  /// v1 modules have no request step: the host's fixed set is recorded as
  /// granted unless persistently revoked. v1 has no revocation exemption.
  static List<GrantDecision> legacy(
    String moduleId,
    Set<String> granted, {
    Set<String> revoked = const {},
  }) => [
    for (final capability in granted)
      GrantDecision(
        moduleId: moduleId,
        capability: capability,
        required: true,
        reason: 'v1 module: fixed host grant (LegacyModuleBridge)',
        granted: !revoked.contains(capability),
        policy: revoked.contains(capability) ? 'revoked' : 'legacy',
      ),
  ];
}

/// The `module_grants` table: what each module asked for and what it got.
class ModuleGrants {
  ModuleGrants(this.database);
  final ManagedDatabase database;

  static void migrate(Database db) => db.execute('''
CREATE TABLE module_grants(
  module_id TEXT NOT NULL,
  capability TEXT NOT NULL,
  requested TEXT NOT NULL CHECK(requested IN ('required','optional')),
  reason TEXT NOT NULL,
  decision TEXT NOT NULL CHECK(decision IN ('granted','denied')),
  policy TEXT NOT NULL,
  decided_at TEXT NOT NULL,
  PRIMARY KEY(module_id, capability)
);
''');

  /// Replaces the module's rows with this activation's decisions.
  Future<void> record(String moduleId, List<GrantDecision> decisions) {
    final now = DateTime.now().toUtc().toIso8601String();
    return database.write((db) {
      db.execute('DELETE FROM module_grants WHERE module_id=?', [moduleId]);
      for (final d in decisions) {
        db.execute('INSERT INTO module_grants VALUES(?,?,?,?,?,?,?)', [
          d.moduleId,
          d.capability,
          d.required ? 'required' : 'optional',
          d.reason,
          d.granted ? 'granted' : 'denied',
          d.policy,
          now,
        ]);
      }
    });
  }

  List<GrantDecision> forModule(String moduleId) => [
    for (final row in database.raw.select(
      'SELECT * FROM module_grants WHERE module_id=? ORDER BY capability',
      [moduleId],
    ))
      GrantDecision(
        moduleId: moduleId,
        capability: row['capability'] as String,
        required: row['requested'] == 'required',
        reason: row['reason'] as String,
        granted: row['decision'] == 'granted',
        policy: row['policy'] as String,
      ),
  ];

  Set<String> revoked(String moduleId) => {
    for (final row in database.raw.select(
      "SELECT capability FROM module_grants WHERE module_id=? AND policy='revoked'",
      [moduleId],
    ))
      row['capability'] as String,
  };

  /// The host withdraws a grant. The row stays, as `denied` / `revoked`, and
  /// the next activation keeps it denied.
  Future<void> revoke(String moduleId, String capability) =>
      database.write((db) {
        db.execute(
          "UPDATE module_grants SET decision='denied', policy='revoked', decided_at=? "
          'WHERE module_id=? AND capability=?',
          [DateTime.now().toUtc().toIso8601String(), moduleId, capability],
        );
        if (db.updatedRows == 0) {
          throw StateError('No grant of $capability to $moduleId');
        }
      });
}
