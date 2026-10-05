// Model, key and evidence settings for the North Star chain: `--dart-define`
// first (the only channel that reaches an app on a device), then the process
// environment.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/services/models/model_gateway.dart';

const _defineEndpoint = String.fromEnvironment('MUYON_EVAL_MODEL_ENDPOINT');
const _defineModel = String.fromEnvironment('MUYON_EVAL_MODEL_ID');
const _defineKey = String.fromEnvironment('MUYON_EVAL_MODEL_KEY');
const _defineLocation = String.fromEnvironment('MUYON_EVAL_MODEL_LOCATION');
const _defineEvidence = String.fromEnvironment('MUYON_EVIDENCE_OUT');
const _defineDevice = String.fromEnvironment('MUYON_EVAL_DEVICE_LABEL');
const _defineCommit = String.fromEnvironment('MUYON_EVAL_COMMIT');

/// `--dart-define` wins (it is the only channel that reaches an app on a
/// device); the process environment is the fallback for desktop and headless.
String? northStarSetting(String name) {
  final defined = switch (name) {
    'MUYON_EVAL_MODEL_ENDPOINT' => _defineEndpoint,
    'MUYON_EVAL_MODEL_ID' => _defineModel,
    'MUYON_EVAL_MODEL_KEY' => _defineKey,
    'MUYON_EVAL_MODEL_LOCATION' => _defineLocation,
    'MUYON_EVIDENCE_OUT' => _defineEvidence,
    'MUYON_EVAL_DEVICE_LABEL' => _defineDevice,
    'MUYON_EVAL_COMMIT' => _defineCommit,
    _ => '',
  };
  if (defined.trim().isNotEmpty) return defined.trim();
  final env = Platform.environment[name];
  return env == null || env.trim().isEmpty ? null : env.trim();
}

/// Real model settings, or null for the fixture.
class NorthStarModelSettings {
  NorthStarModelSettings._(
    this.endpoint,
    this.modelId,
    this.key,
    this.location,
    this.source,
  );
  final Uri endpoint;
  final String modelId;
  final String? key;
  final ModelLocation location;
  final String source;

  static NorthStarModelSettings? fromEnvironment() {
    final endpoint = northStarSetting('MUYON_EVAL_MODEL_ENDPOINT');
    final model = northStarSetting('MUYON_EVAL_MODEL_ID');
    if (endpoint == null && model == null) return null;
    if (endpoint == null || model == null) {
      throw StateError(
        'Set both MUYON_EVAL_MODEL_ENDPOINT and MUYON_EVAL_MODEL_ID, or neither',
      );
    }
    final uri = Uri.parse(endpoint);
    final named = northStarSetting('MUYON_EVAL_MODEL_LOCATION');
    final location = named != null
        ? ModelLocation.values.byName(named)
        : ['localhost', '127.0.0.1', '::1'].contains(uri.host)
        ? ModelLocation.local
        : ModelLocation.remote;
    return NorthStarModelSettings._(
      uri,
      model,
      northStarSetting('MUYON_EVAL_MODEL_KEY'),
      location,
      _defineEndpoint.trim().isNotEmpty ? 'dart-define' : 'environment',
    );
  }
}

/// Reads the eval key from settings only; it never reaches the platform
/// keychain, the database, the evidence or the log.
class EnvSecretStore implements SecretStore {
  EnvSecretStore(this.reference, this.value);
  final String reference;
  final String? value;
  @override
  Future<String?> read(String reference) async =>
      reference == this.reference ? value : null;
}

const northStarCredentialRef = 'north-star-eval-key';

/// The host reads credentials through `MethodChannelSecretStore`
/// (`com.mightyoung.muyon/secrets`). For the test run that channel is answered
/// by [EnvSecretStore], so the key is used for this run only. Windows keeps
/// credentials through FFI and is not covered by this binding.
void bindEnvSecretStore(EnvSecretStore store) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('com.mightyoung.muyon/secrets'),
        (call) async => call.method == 'read'
            ? store.read((call.arguments as Map)['reference'] as String)
            : null,
      );
}

void unbindEnvSecretStore() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('com.mightyoung.muyon/secrets'),
        null,
      );
}
