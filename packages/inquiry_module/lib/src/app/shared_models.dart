import 'package:supplier_core/supplier_core.dart';

/// Host bridge for the existing Folio settings and business LlmClient.
/// Credentials remain in the host secure store; settings contain no key.
abstract interface class InquiryModelSettingsBridge {
  String get baseUrl;
  String get model;
  Future<bool> hasCredential();
  Future<void> save({
    required String baseUrl,
    required String model,
    String? apiKey,
  });
}

typedef SharedLlmFactory = Future<LlmClient?> Function({
  AiCancellation? cancellation,
});
