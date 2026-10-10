part of 'agent_eval.dart';

// ------------------------------------------------------ real-run settings

/// Reads the eval key from a map (the process environment) only; nothing is
/// stored, printed or written.
class EnvironmentSecretStore implements SecretStore {
  const EnvironmentSecretStore(this._environment);
  final Map<String, String> _environment;
  @override
  Future<String?> read(String reference) async {
    final value = _environment[reference];
    return value == null || value.isEmpty ? null : value;
  }
}

const agentEvalKeyVariable = 'MUYON_EVAL_MODEL_KEY';

/// A key that dart:io can put in a header unchanged; anything else makes
/// header setting throw with the whole `Bearer <key>` in the message.
final _visibleAscii = RegExp(r'^[\x21-\x7E]+$');

/// Why the real run is skipped, or null when it runs. Model variables alone
/// are not enough: `MUYON_EVAL_REAL=1` must be set as well, so an exported
/// configuration never turns a plain `flutter test` into paid requests.
String? agentEvalSkipReason(Map<String, String> environment) {
  final configured =
      (environment['MUYON_EVAL_MODEL_ENDPOINT'] ?? '').trim().isNotEmpty &&
      (environment['MUYON_EVAL_MODEL_ID'] ?? '').trim().isNotEmpty;
  final enabled = environment['MUYON_EVAL_REAL'] == '1';
  if (configured && enabled) return null;
  if (configured) {
    return 'model variables are set but MUYON_EVAL_REAL=1 is not; '
        'set it to run the agent tasks against the real model';
  }
  return 'set MUYON_EVAL_REAL=1, MUYON_EVAL_MODEL_ENDPOINT and '
      'MUYON_EVAL_MODEL_ID to run';
}

/// Loopback endpoints are local; any other endpoint is remote, which
/// [ModelProfile] requires to be HTTPS and authenticated. Errors never quote
/// the endpoint or the key.
ModelProfile agentEvalProfileFromEnvironment(Map<String, String> environment) {
  final endpoint = Uri.parse(environment['MUYON_EVAL_MODEL_ENDPOINT']!.trim());
  final key = environment[agentEvalKeyVariable] ?? '';
  final hasKey = key.isNotEmpty;
  if (hasKey && !_visibleAscii.hasMatch(key)) {
    throw ArgumentError(
      '$agentEvalKeyVariable must be visible ASCII only (value not shown)',
    );
  }
  final local = ['localhost', '127.0.0.1', '::1'].contains(endpoint.host);
  if (!local && !hasKey) {
    throw ArgumentError('A remote endpoint needs $agentEvalKeyVariable');
  }
  return ModelProfile(
    id: 'agent-eval',
    endpoint: endpoint,
    location: local ? ModelLocation.local : ModelLocation.remote,
    modelId: environment['MUYON_EVAL_MODEL_ID']!.trim(),
    endpointIdentity: endpoint.host,
    credentialRef: hasKey ? agentEvalKeyVariable : null,
  );
}

/// `MUYON_EVAL_MODEL_TIMEOUT_SECONDS`, else the gateway default of 45 s.
Duration agentEvalTimeoutFromEnvironment(Map<String, String> environment) {
  final raw = (environment['MUYON_EVAL_MODEL_TIMEOUT_SECONDS'] ?? '').trim();
  if (raw.isEmpty) return const Duration(seconds: 45);
  final seconds = int.tryParse(raw);
  if (seconds == null || seconds <= 0) {
    throw ArgumentError(
      'MUYON_EVAL_MODEL_TIMEOUT_SECONDS must be a positive whole number',
    );
  }
  return Duration(seconds: seconds);
}
