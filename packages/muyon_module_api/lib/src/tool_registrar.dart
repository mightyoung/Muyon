import 'dart:async';

import 'assistant_scope.dart';
import 'context.dart';
import 'module.dart';
import 'ontology.dart';
import 'tools.dart';

/// Where an external tool may send data. Same shape as `NetworkPolicy`; the
/// host requires a tool's rule to sit inside the manifest's policy, and checks
/// every call's destination against both before any approval is issued.
class DestinationRule {
  const DestinationRule({this.fixedHosts = const {}, this.publicWeb = false});
  final Set<String> fixedHosts;
  final bool publicWeb;
}

class ToolExample {
  ToolExample({
    required this.name,
    Map<String, Object?> parameters = const {},
    this.scope,
  }) : parameters = freezeJsonMap(parameters);
  final String name;
  final Map<String, Object?> parameters;
  final AssistantScopeKind? scope;
}

/// What a module says about one tool. The *effect* is not in here: it follows
/// from the registrar method used, so a module cannot call a write tool a read.
class ToolSpec {
  ToolSpec({
    required this.name,
    required this.description,
    Map<String, Object?> parameterSchema = const {
      'type': 'object',
      'properties': <String, Object?>{},
      'additionalProperties': false,
    },
    Map<String, Object?> resultSchema = const {},
    Set<AssistantScopeKind>? scopes,
    List<String> operations = const [],
    this.supportsCancel = false,
    List<ToolExample> examples = const [],
    Map<String, Sensitivity> resultSensitivity = const {},
  }) : parameterSchema = freezeJsonMap(parameterSchema),
       resultSchema = freezeJsonMap(resultSchema),
       scopes = scopes == null ? null : Set.unmodifiable(scopes),
       operations = List.unmodifiable(operations),
       examples = List.unmodifiable(examples),
       resultSensitivity = Map.unmodifiable(resultSensitivity);

  /// Unique within the module; the host makes the tool id `<moduleId>.<name>`.
  final String name;

  /// For people and the model; never an authorization.
  final String description;
  final Map<String, Object?> parameterSchema, resultSchema;

  /// Null means the effect's default (read: all three kinds; write and
  /// external: selected objects only).
  final Set<AssistantScopeKind>? scopes;

  /// Coverage-manifest operation ids this tool carries.
  final List<String> operations;
  final bool supportsCancel;
  final List<ToolExample> examples;

  /// Result field path -> category, for outbound content review.
  final Map<String, Sensitivity> resultSensitivity;
}

final class WriteToolSpec extends ToolSpec {
  WriteToolSpec({
    required super.name,
    required super.description,
    super.parameterSchema,
    super.resultSchema,
    super.scopes,
    super.operations,
    super.supportsCancel,
    super.examples,
    super.resultSensitivity,
    Set<String> targetTypes = const {},
    Set<String> createsTypes = const {},
    Set<String> deletesTypes = const {},
    Set<String> affectsTypes = const {},
  }) : targetTypes = Set.unmodifiable(targetTypes),
       createsTypes = Set.unmodifiable(createsTypes),
       deletesTypes = Set.unmodifiable(deletesTypes),
       affectsTypes = Set.unmodifiable(affectsTypes);
  final Set<String> targetTypes, createsTypes, deletesTypes, affectsTypes;
}

final class ExternalToolSpec extends ToolSpec {
  ExternalToolSpec({
    required super.name,
    required super.description,
    super.parameterSchema,
    super.resultSchema,
    super.scopes,
    super.operations,
    super.supportsCancel,
    super.examples,
    super.resultSensitivity,
    required this.effect,
    required this.destination,
  }) {
    if (effect != ToolEffect.export && effect != ToolEffect.network) {
      throw ArgumentError('An external tool is export or network');
    }
  }
  final ToolEffect effect;
  final DestinationRule destination;
}

/// A tool handler's view of one call: the host's [ToolCallContext], and the
/// module's activated runtime.
abstract interface class ModuleToolContext {
  ToolCallContext get call;

  /// The module runtime; the host has already made sure the module is active.
  Future<T> runtime<T extends ModuleRuntime>();
}

typedef ModuleToolHandler = Future<ToolCallResult> Function(
  ModuleToolContext ctx,
);

/// Declares tools. Valid only inside `BusinessModuleV2.registerTools`; sealed
/// when that returns. Approval, receipts, the outbound ledger and grant
/// resolution stay in the host: nothing here can write or bypass them.
abstract interface class ToolRegistrar {
  String get moduleId;

  /// effect = read.
  void read(ToolSpec spec, ModuleToolHandler handler);

  /// effect = write.
  void write(WriteToolSpec spec, ModuleToolHandler handler);

  /// effect = export or network.
  void external(ExternalToolSpec spec, ModuleToolHandler handler);

  /// A restricted channel (not selectable by a model) through which module
  /// code performs one host-approved external effect.
  HostChannel channel(ChannelSpec spec);
}

class ChannelSpec {
  ChannelSpec({
    required this.name,
    required this.description,
    required this.effect,
    required this.destination,
    Map<String, Object?> parameterSchema = const {},
    this.supportsCancel = true,
  }) : parameterSchema = freezeJsonMap(parameterSchema) {
    if (effect != ToolEffect.export && effect != ToolEffect.network) {
      throw ArgumentError('A channel is export or network');
    }
  }
  final String name, description;
  final ToolEffect effect;
  final DestinationRule destination;
  final Map<String, Object?> parameterSchema;
  final bool supportsCancel;
}

class ChannelRequest {
  ChannelRequest({
    required this.destination,
    Map<String, Object?> parameters = const {},
  }) : parameters = freezeJsonMap(parameters);
  final String destination;
  final Map<String, Object?> parameters;
}

/// What the person is asked to review before the effect.
class ChannelPreview {
  const ChannelPreview({
    required this.invocationId,
    required this.destination,
    required this.parameterDigest,
  });
  final String invocationId;
  final String destination;
  final String parameterDigest;
}

/// The review dialog. In the second phase the module supplies it (as today);
/// the host guarantees approval issuing, receipts and the ledger.
typedef ChannelReview = Future<bool> Function(ChannelPreview preview);

/// Call immediately before the external effect starts.
typedef EffectGuard = void Function();

abstract interface class HostChannel {
  Future<T> run<T>(
    ChannelRequest request,
    Future<T> Function(EffectGuard guard) effect, {
    required ToolCancellationToken cancellation,
    ChannelReview? review,
  });
}
