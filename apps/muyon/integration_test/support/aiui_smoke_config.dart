import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/model_provider.dart';

/// Only reviewed stable codes may enter evidence or a formal test failure.
enum SmokeFailureCode {
  realModelConfigurationMissing('real_model_configuration_missing'),
  streamingModelRequired('streaming_model_required'),
  candidateIdentityMissing('candidate_identity_missing'),
  candidateIdentityMismatch('candidate_identity_mismatch'),
  productionStreamWiringMissing('production_stream_wiring_missing'),
  conversationFactCardMissing('conversation_fact_card_missing'),
  presentationPolicyMissing('presentation_policy_missing'),
  productionFallbackMissing('production_fallback_missing'),
  failureDiagnosticsMissing('failure_diagnostics_missing'),
  requestObservabilityMissing('request_observability_missing'),
  faultIoBoundaryMissing('fault_io_boundary_missing'),
  faultPreconditionUnmet('fault_precondition_unmet'),
  latencySamplesInsufficient('latency_samples_insufficient'),
  manualCheckpointUnavailable('manual_checkpoint_unavailable'),
  acceptanceCoverageIncomplete('acceptance_coverage_incomplete'),
  evidenceWriteFailed('evidence_write_failed'),
  unexpectedFailure('unexpected_failure');

  const SmokeFailureCode(this.code);
  final String code;
}

final class SmokeFailure extends StateError {
  SmokeFailure(this.code) : super(code.code);
  final SmokeFailureCode code;
}

/// Device configuration has no process-environment fallback and no fixture mode.
/// Never serialize this object, profiles, or their endpoint/credential values.
final class AiuiSmokeConfiguration {
  AiuiSmokeConfiguration._(this.profile, this.secret, this.candidateSha);
  final ModelProfile profile;
  final String? secret;
  final String candidateSha;

  static AiuiSmokeConfiguration fromDartDefines() => parse({
    'real': const String.fromEnvironment('MUYON_EVAL_REAL'),
    'endpoint': const String.fromEnvironment('MUYON_EVAL_MODEL_ENDPOINT'),
    'model': const String.fromEnvironment('MUYON_EVAL_MODEL_ID'),
    'key': const String.fromEnvironment('MUYON_EVAL_MODEL_KEY'),
    'location': const String.fromEnvironment('MUYON_EVAL_MODEL_LOCATION'),
    'streaming': const String.fromEnvironment('MUYON_EVAL_MODEL_STREAMING'),
    'candidate': const String.fromEnvironment('MUYON_EVAL_COMMIT'),
    'build': const String.fromEnvironment('MUYON_BUILD_COMMIT'),
  });

  /// Explicit values let offline tests verify parsing without setting real-run
  /// process variables or sending any request. A build identity is mandatory;
  /// equality checks a build provenance declaration, not a cryptographic proof.
  static AiuiSmokeConfiguration parse(Map<String, String> values) {
    String read(String key) => (values[key] ?? '').trim();
    if (read('real') != '1' ||
        read('endpoint').isEmpty ||
        read('model').isEmpty) {
      throw SmokeFailure(SmokeFailureCode.realModelConfigurationMissing);
    }
    final uri = Uri.tryParse(read('endpoint'));
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw SmokeFailure(SmokeFailureCode.realModelConfigurationMissing);
    }
    final local = ['localhost', '127.0.0.1', '::1'].contains(uri.host);
    final location = read('location').isEmpty
        ? (local ? ModelLocation.local : ModelLocation.remote)
        : ModelLocation.values
              .where((value) => value.name == read('location'))
              .firstOrNull;
    if (location == null ||
        (location == ModelLocation.local && !local) ||
        (location == ModelLocation.remote && uri.scheme != 'https') ||
        (location != ModelLocation.local && read('key').isEmpty)) {
      throw SmokeFailure(SmokeFailureCode.realModelConfigurationMissing);
    }
    if (read('streaming') != '1') {
      throw SmokeFailure(SmokeFailureCode.streamingModelRequired);
    }
    final sha = RegExp(r'^[0-9a-f]{40}$');
    if (!sha.hasMatch(read('candidate')) || !sha.hasMatch(read('build'))) {
      throw SmokeFailure(SmokeFailureCode.candidateIdentityMissing);
    }
    if (read('candidate') != read('build')) {
      throw SmokeFailure(SmokeFailureCode.candidateIdentityMismatch);
    }
    return AiuiSmokeConfiguration._(
      ModelProfile(
        id: 'aiui-smoke-real',
        endpoint: uri,
        location: location,
        modelId: read('model'),
        endpointIdentity: 'aiui-smoke-configured',
        credentialRef: read('key').isEmpty ? null : credentialReference,
        capabilities: const ModelCapabilities(
          streaming: true,
          source: CapabilitySource.userDeclared,
        ),
      ),
      read('key').isEmpty ? null : read('key'),
      read('candidate'),
    );
  }

  static const credentialReference = 'aiui-smoke-transient-key';
}
