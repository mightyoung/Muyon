import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'local_export_target.dart';

/// Only host effect adapters construct this value; it has no JSON decoder.
final class HostEffectIntent {
  HostEffectIntent.transport({
    required this.toolId,
    required this.invocationId,
    required Uri endpoint,
    required String endpointIdentity,
    required List<int> content,
    Iterable<ObjectRef> sourceObjects = const [],
  }) : _endpoint = endpoint,
       _endpointIdentity = endpointIdentity,
       _le = null,
       content = List.unmodifiable(content),
       sourceObjects = List.unmodifiable(sourceObjects) {
    final loopback = ['localhost', '127.0.0.1', '::1'].contains(endpoint.host);
    if (toolId.isEmpty ||
        invocationId.isEmpty ||
        endpointIdentity.trim().isEmpty ||
        !endpoint.hasAuthority ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.fragment.isNotEmpty ||
        !(endpoint.scheme == 'https' ||
            (endpoint.scheme == 'http' && loopback)) ||
        this.content.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError('Trusted transport identity and body bytes required');
    }
  }

  /// Exact host validated local operation; no invented transport endpoint.
  HostEffectIntent.localWrite({
    required this.toolId,
    required this.invocationId,
    required List<int> content,
    required Iterable<ObjectRef> sourceObjects,
  }) : _endpoint = null,
       _endpointIdentity = null,
       _le = null,
       content = List.unmodifiable(content),
       sourceObjects = List.unmodifiable(sourceObjects) {
    if (toolId.isEmpty ||
        invocationId.isEmpty ||
        this.sourceObjects.isEmpty ||
        this.content.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError(
        'Actual local operation and resolved targets required',
      );
    }
  }

  /// A local export stage (generate A or save B). The host adapter builds it
  /// from the frozen preparation; the model never supplies any of it. Bound:
  /// stage call identity (exportId + stage-typed invocation), preparationDigest
  /// (not only byte digest), scope, preparation version, file name/format,
  /// content bytes, target capability (save only), overwrite and policy.
  /// Review outcomes belong in [LocalExportPresentation], not here.
  HostEffectIntent.localExport({
    required this.toolId,
    required LocalExportCallIdentity call,
    required LocalExportPhase phase,
    required String scopeDigest,
    required String preparationDigest,
    required int preparationVersion,
    required String fileName,
    required String format,
    required List<int> content,
    required Iterable<ObjectRef> sourceObjects,
    required LocalExportTargetIssuer targetIssuer,
    LocalExportTargetCapability? target,
    required LocalExportOverwrite overwrite,
    required String policyVersion,
  }) : invocationId = call.invocationId,
       _endpoint = null,
       _endpointIdentity = null,
       _le = _LocalExport(
         phase,
         call.exportId,
         scopeDigest,
         preparationDigest,
         preparationVersion,
         fileName,
         format,
         target,
         targetIssuer,
         overwrite,
         policyVersion,
       ),
       content = List.unmodifiable(content),
       sourceObjects = List.unmodifiable(sourceObjects) {
    final hex = RegExp(r'^[0-9a-f]{64}$');
    final saving = phase == LocalExportPhase.save;
    if (toolId.isEmpty ||
        call.invocationId.isEmpty ||
        call.exportId.isEmpty ||
        call.phase != phase ||
        (phase == LocalExportPhase.generate && call is! LocalExportGenerateCall) ||
        (phase == LocalExportPhase.save && call is! LocalExportSaveCall) ||
        this.content.isEmpty ||
        this.content.any((byte) => byte < 0 || byte > 255) ||
        !hex.hasMatch(scopeDigest) ||
        !hex.hasMatch(preparationDigest) ||
        preparationVersion < 1 ||
        format.isEmpty ||
        policyVersion.isEmpty ||
        !_safeFileName.hasMatch(fileName) ||
        fileName.startsWith('.') ||
        fileName.contains('..') ||
        saving != (target != null) ||
        (target != null && !targetIssuer.owns(target)) ||
        (!saving && overwrite != LocalExportOverwrite.createNew)) {
      throw ArgumentError('Trusted local export identity and bytes required');
    }
  }
  static final _safeFileName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');
  final String toolId, invocationId;
  final _LocalExport? _le;
  bool get isLocalExport => _le != null;

  /// Identity binding remains stable, but a cached save loses authority when
  /// its trusted issuer revokes the target. Recheck at each host boundary.
  bool get hasLiveAuthority =>
      _le?.target == null || _le!.targetIssuer.owns(_le.target!);
  LocalExportPhase get phase =>
      _le?.phase ?? (throw StateError('Not a local export'));
  final Uri? _endpoint;
  final String? _endpointIdentity;
  bool get isTransport => _endpoint != null;
  Uri? get reviewEndpoint => _endpoint;
  Uri get endpoint =>
      _endpoint ?? (throw StateError('Local write has no endpoint'));
  String get endpointIdentity =>
      _endpointIdentity ??
      (throw StateError('Local write has no transport identity'));
  final List<int> content;
  final List<ObjectRef> sourceObjects;
  String? get destinationDigest => !isTransport
      ? null
      : _hash(utf8.encode(jsonEncode([endpoint.toString(), endpointIdentity])));
  String get payloadDigest => _hash(content);
  String get digest => isLocalExport
      ? _hash(
          utf8.encode(
            jsonEncode([
              'local_export',
              toolId,
              invocationId,
              _le!.exportId,
              _le.phase.name,
              _le.scopeDigest,
              _le.preparationDigest,
              _le.preparationVersion,
              _le.fileName,
              _le.format,
              payloadDigest,
              _le.target?.identity,
              _le.overwrite.name,
              _le.policyVersion,
              sourceObjects.map((ref) => ref.toJson()).toList(),
            ]),
          ),
        )
      : _plainDigest;
  String get exportId =>
      _le?.exportId ?? (throw StateError('Not a local export'));
  String get preparationDigest =>
      _le?.preparationDigest ?? (throw StateError('Not a local export'));
  String get _plainDigest => _hash(
    utf8.encode(
      jsonEncode([
        isTransport ? 'transport' : 'local_write',
        toolId,
        invocationId,
        destinationDigest,
        payloadDigest,
        sourceObjects.map((ref) => ref.toJson()).toList(),
      ]),
    ),
  );
  String? get displayDestination => !isTransport
      ? null
      : Uri(
          scheme: endpoint.scheme,
          host: endpoint.host,
          port: endpoint.hasPort ? endpoint.port : null,
          path: endpoint.path,
        ).toString();
  static String _hash(List<int> bytes) => sha256.convert(bytes).toString();
}

final class _LocalExport {
  const _LocalExport(
    this.phase,
    this.exportId,
    this.scopeDigest,
    this.preparationDigest,
    this.preparationVersion,
    this.fileName,
    this.format,
    this.target,
    this.targetIssuer,
    this.overwrite,
    this.policyVersion,
  );
  final LocalExportPhase phase;
  final String exportId, scopeDigest, preparationDigest, fileName, format, policyVersion;
  final int preparationVersion;
  final LocalExportTargetCapability? target;
  final LocalExportTargetIssuer targetIssuer;
  final LocalExportOverwrite overwrite;
}
