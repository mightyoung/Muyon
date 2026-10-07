import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:uuid/uuid.dart';

import '../platform/tool_registry.dart';
import '../services/models/tool_names.dart';
import 'module_host.dart';

/// Whether [destination] is allowed by both a tool's [rule] and the module's
/// manifest [policy]. Anything unparseable is refused. Only ever narrows.
bool destinationAllowed(
  String destination,
  DestinationRule rule,
  NetworkPolicy policy,
) {
  final uri = Uri.tryParse(destination);
  final host = uri?.host ?? '';
  if (uri == null || host.isEmpty) return false;
  bool within(Set<String> fixed, bool publicWeb) =>
      fixed.contains(host) || (publicWeb && uri.scheme == 'https');
  return within(rule.fixedHosts, rule.publicWeb) &&
      within(policy.fixedHosts, policy.publicWeb);
}

/// Default result check for a module's write tool: what it reports having
/// written must belong to the module and to a project the user selected. It
/// generalizes `validateInquiryWriteResult`; a module cannot loosen it.
Future<void> validateModuleWriteResult(
  String moduleId,
  ResolvedAssistantScope scope,
  ToolCallResult result,
) async {
  final projects = {
    for (final ref in scope.objects)
      if (ref.moduleId == moduleId) ?ref.nativeProjectId,
  };
  bool outside(ObjectRef ref) =>
      ref.moduleId != moduleId || !projects.contains(ref.nativeProjectId);
  if (result.artifactRefs.isNotEmpty ||
      result.objectRefs.any(outside) ||
      result.changes.any((change) => outside(change.ref))) {
    throw const ToolPlatformException(
      'result_scope_mismatch',
      'Written records are outside the selected project',
    );
  }
}

/// The host's [ToolRegistrar]: a module *declares* tools, this registers them
/// with the effect that the method used implies. It holds the module's id and
/// the registry privately and offers nothing that touches approvals, receipts
/// or the outbound ledger; the registry's own dispatch still demands a
/// one-use approval for every write or external call.
class HostToolRegistrar implements ToolRegistrar {
  HostToolRegistrar(this.moduleId, this._registry, this._manifest, this._link);

  @override
  final String moduleId;
  final ToolRegistry _registry;
  final ModuleManifest _manifest;
  final ModuleLink _link;
  final _registered = <String>[];
  var _sealed = false;

  /// Ids registered so far, for availability changes.
  List<String> get registeredToolIds => List.unmodifiable(_registered);

  /// Called by the host when `registerTools` returns; later calls throw.
  void seal() => _sealed = true;

  Set<String> get _dataModules => {moduleId, ..._manifest.requiredDependencies};

  static final _name = RegExp(r'^[a-z][a-z0-9_]*$');

  String _claim(String name) {
    if (_sealed) {
      throw StateError('Tools can only be declared inside registerTools');
    }
    if (!_name.hasMatch(name)) {
      throw ArgumentError('Invalid tool name "$name" in module $moduleId');
    }
    final id = '$moduleId.$name';
    // A function-name clash would let a model call one tool as another.
    toolIdsByFunctionNameOf([
      for (final info in _registry.list()) info.descriptor.toolId,
      id,
    ]);
    return id;
  }

  Future<ToolCallResult> Function(ToolCallContext) _wrap(
    ModuleToolHandler handler,
  ) => (call) async {
    call.cancellation.throwIfCancelled();
    final state = await _link.activate(moduleId);
    if (state.status != ModuleStatus.ready) {
      return ToolCallResult(
        status: ToolCallStatus.failed,
        summary:
            'Module $moduleId is unavailable: ${state.reason ?? 'unknown'}',
      );
    }
    return handler(_Context(call, _link, moduleId));
  };

  void _register(
    ToolSpec spec,
    ToolEffect effect,
    ModuleToolHandler handler, {
    required Set<AssistantScopeKind> defaultScopes,
    Future<void> Function(ResolvedAssistantScope, ToolCallResult)? validate,
    void Function(ToolCallRequest)? preflight,
  }) {
    final id = _claim(spec.name);
    final scopes = spec.scopes ?? defaultScopes;
    if (scopes.isEmpty) throw ArgumentError('Tool $id supports no scope');
    _registry.register(
      providerId: moduleId,
      descriptor: ToolDescriptor(
        toolId: id,
        moduleId: moduleId,
        effect: effect,
        description: spec.description,
        parameterSchema: spec.parameterSchema,
        resultSchema: spec.resultSchema,
        supportsCancel: spec.supportsCancel,
      ),
      supportedScopes: scopes,
      dataModuleIds: _dataModules,
      validateResult: validate,
      preflight: preflight,
      handler: _wrap(handler),
    );
    _registered.add(id);
  }

  @override
  void read(ToolSpec spec, ModuleToolHandler handler) => _register(
    spec,
    ToolEffect.read,
    handler,
    defaultScopes: {...AssistantScopeKind.values},
  );

  @override
  void write(WriteToolSpec spec, ModuleToolHandler handler) => _register(
    spec,
    ToolEffect.write,
    handler,
    defaultScopes: {AssistantScopeKind.selectedObjects},
    validate: (scope, result) =>
        validateModuleWriteResult(moduleId, scope, result),
  );

  /// A rule must sit inside the manifest's network policy and name somewhere.
  void _checkRule(String id, DestinationRule rule) {
    final policy = _manifest.network;
    final empty = rule.fixedHosts.isEmpty && !rule.publicWeb;
    final outside =
        (rule.publicWeb && !policy.publicWeb) ||
        rule.fixedHosts.any(
          (host) => !policy.fixedHosts.contains(host) && !policy.publicWeb,
        );
    if (empty || outside) {
      throw ArgumentError(
        'Destination rule of $id is empty or outside the manifest network '
        'policy of $moduleId',
      );
    }
  }

  void Function(ToolCallRequest) _destinationGuard(DestinationRule rule) =>
      (request) {
        final destination = request.destination;
        if (destination == null ||
            !destinationAllowed(destination, rule, _manifest.network)) {
          throw const ToolPlatformException(
            'destination_blocked',
            'Destination is outside what this module may send to',
          );
        }
      };

  @override
  void external(ExternalToolSpec spec, ModuleToolHandler handler) {
    _checkRule('$moduleId.${spec.name}', spec.destination);
    final guard = _destinationGuard(spec.destination);
    _register(
      spec,
      spec.effect,
      (ctx) {
        // Defence in depth: the registry already refused at prepare.
        guard(ctx.call.request);
        return handler(ctx);
      },
      defaultScopes: {AssistantScopeKind.selectedObjects},
      preflight: guard,
    );
  }

  @override
  HostChannel channel(ChannelSpec spec) {
    final id = _claim(spec.name);
    _checkRule(id, spec.destination);
    final channel = _Channel(_registry, id, spec, _manifest.network);
    _registry.register(
      providerId: moduleId,
      descriptor: ToolDescriptor(
        toolId: id,
        moduleId: moduleId,
        effect: spec.effect,
        description: spec.description,
        parameterSchema: spec.parameterSchema,
        supportsCancel: spec.supportsCancel,
        // Only module code, through the approved path below, may run it.
        modelSelectable: false,
      ),
      supportedScopes: {AssistantScopeKind.global},
      dataModuleIds: {moduleId},
      preflight: _destinationGuard(spec.destination),
      handler: channel.handle,
    );
    _registered.add(id);
    return channel;
  }
}

class _Context implements ModuleToolContext {
  _Context(this.call, this._link, this._moduleId);
  @override
  final ToolCallContext call;
  final ModuleLink _link;
  final String _moduleId;

  @override
  Future<T> runtime<T extends ModuleRuntime>() async {
    final runtime = _link.runtime<T>(_moduleId);
    if (runtime == null) {
      throw StateError('Module $_moduleId has no active runtime');
    }
    return runtime;
  }
}

/// The skeleton the inquiry web and hub authorities share: prepare, the
/// person reviews, the host approves, the registry invokes. The module only
/// supplies the review and the effect.
class _Channel implements HostChannel {
  _Channel(this._registry, this._toolId, this._spec, this._policy);
  final ToolRegistry _registry;
  final String _toolId;
  final ChannelSpec _spec;
  final NetworkPolicy _policy;
  final _pending = <String, Future<ToolCallResult> Function(ToolCallContext)>{};

  Future<ToolCallResult> handle(ToolCallContext call) {
    final pending = _pending[call.request.invocationId];
    if (pending == null) throw StateError('No trusted channel operation');
    return pending(call);
  }

  @override
  Future<T> run<T>(
    ChannelRequest request,
    Future<T> Function(EffectGuard guard) effect, {
    required ToolCancellationToken cancellation,
    ChannelReview? review,
  }) async {
    void validate() {
      cancellation.throwIfCancelled();
      if (_registry.inspect(_toolId)?.available != true) {
        throw StateError('Host channel is unavailable');
      }
    }

    validate();
    if (review == null) throw StateError('No trusted host review');
    if (!destinationAllowed(request.destination, _spec.destination, _policy)) {
      throw const ToolPlatformException(
        'destination_blocked',
        'Destination is outside what this module may send to',
      );
    }
    final call = ToolCallRequest(
      invocationId: const Uuid().v4(),
      toolId: _toolId,
      scope: const AssistantScope.global(),
      destination: request.destination,
      parameters: request.parameters,
    );
    final prepared = await _registry.prepare(call);
    validate();
    final approved = await review(
      ChannelPreview(
        invocationId: call.invocationId,
        destination: request.destination,
        parameterDigest: prepared.parameterDigest,
      ),
    );
    validate();
    if (!approved) throw StateError('Host denied this channel request');
    final grant = await _registry.approve(prepared);
    validate();
    late T value;
    var effectStarted = false;
    _pending[call.invocationId] = (context) async {
      void guard() {
        validate();
        context.checkBeforeEffect();
        effectStarted = true;
      }

      value = await effect(guard);
      validate();
      return ToolCallResult(
        status: ToolCallStatus.succeeded,
        summary: 'Channel request completed',
        data: {'destination': request.destination},
      );
    };
    try {
      final result = await _registry.invoke(
        call.withApproval(grant),
        cancellation: cancellation,
      );
      if (result.status != ToolCallStatus.succeeded) {
        throw ChannelFailure(
          interrupted: result.status == ToolCallStatus.interrupted,
        );
      }
      return value;
    } catch (error) {
      if (error is ChannelFailure) rethrow;
      throw ChannelFailure(interrupted: effectStarted);
    } finally {
      _pending.remove(call.invocationId);
    }
  }
}
