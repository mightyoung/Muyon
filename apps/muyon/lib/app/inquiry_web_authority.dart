import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:supplier_core/supplier_core.dart';
import 'package:uuid/uuid.dart';

import '../platform/tool_registry.dart';
import '../platform/grants/host_tool_authorization.dart';
import '../platform/grants/host_effect_intent.dart';
import '../platform/grants/outbound_content_reviewer.dart';
import '../platform/outbound_tool_ledger.dart';

/// Registers a recorded channel, not a model-callable grant operation. Only an
/// invocation-bound application closure can execute this provider's handler.
class InquiryWebAuthority implements AssistantWebAuthority {
  InquiryWebAuthority(this.registry, {HostToolAuthorization? authorization})
    : _authorization =
          authorization ??
          (registry.supportsAuthorizationLinks
              ? HostToolAuthorization(
                  registry: registry,
                  reviewer: ReviewerChain(const [
                    NoopReviewer(),
                  ], timeout: const Duration(seconds: 5)),
                )
              : null) {
    registry.register(
      providerId: 'inquiry',
      descriptor: ToolDescriptor(
        toolId: toolId,
        moduleId: 'inquiry',
        effect: ToolEffect.network,
        supportsCancel: true,
        modelSelectable: false,
        description: '询价模块内部的联网通道：只执行宿主已确认的单次网页读取，不提供给模型选择。',
        parameterSchema: {
          'type': 'object',
          'properties': {
            'method': {
              'type': 'string',
              'enum': ['GET'],
            },
            'url': {'type': 'string', 'maxLength': 2048},
            'sessionId': {'type': 'string', 'maxLength': 128},
            'maxBodyBytes': {
              'type': 'integer',
              'enum': [524288],
            },
          },
          'required': ['method', 'url', 'sessionId', 'maxBodyBytes'],
          'additionalProperties': false,
        },
      ),
      supportedScopes: {AssistantScopeKind.global},
      dataModuleIds: {'inquiry'},
      effectIntent: _authorization == null
          ? null
          : (request, _) => _intents[request.invocationId],
      handler: (context) {
        final pending = _pending[context.request.invocationId];
        if (pending == null) throw StateError('No trusted web operation');
        return pending(context);
      },
    );
  }

  void disable() => registry.setAvailability(
    toolId,
    available: false,
    reason: 'Inquiry module is closed',
  );

  static const toolId = 'inquiry.web.request';
  final ToolRegistry registry;
  final HostToolAuthorization? _authorization;
  final _intents = <String, HostEffectIntent>{};
  final _pending = <String, Future<ToolCallResult> Function(ToolCallContext)>{};

  @override
  Future<T> run<T>({
    required Uri destination,
    required String sessionId,
    required AiCancellation cancellation,
    required AssistantWebReview? review,
    required void Function() validateSession,
    required Future<T> Function(void Function()) operation,
  }) async {
    String? boundInvocation;
    try {
      void validate() {
        cancellation.check();
        validateSession();
        if (registry.inspect(toolId)?.available != true) {
          throw StateError('Host web channel is unavailable');
        }
      }

      validate();
      if (review == null) throw StateError('No trusted host review');
      if (sessionId.isEmpty || sessionId.length > 128) {
        throw StateError('No bound inquiry session');
      }
      final request = ToolCallRequest(
        invocationId: const Uuid().v4(),
        toolId: toolId,
        scope: const AssistantScope.global(),
        destination: destination.toString(),
        parameters: {
          'method': 'GET',
          'sessionId': sessionId,
          'url': destination.toString(),
          'maxBodyBytes': AssistantWebTools.maxBodyBytes,
        },
      );
      boundInvocation = request.invocationId;
      if (_authorization != null) {
        _intents[request.invocationId] = HostEffectIntent.transport(
          toolId: toolId,
          invocationId: request.invocationId,
          endpoint: destination,
          endpointIdentity: 'inquiry-web:GET:$sessionId',
          content: const [],
        );
      }
      final prepared = await registry.prepare(request);
      final localReview = await _authorization?.review(prepared);
      validate();
      if (localReview?.action == ReviewAction.block) {
        throw StateError('Local review blocked this web request');
      }
      validate();
      final approved = await cancellation.wait(
        review(
          AssistantWebApprovalPreview(
            destination: destination,
            invocationId: request.invocationId,
            parameterDigest: prepared.parameterDigest,
          ),
          cancellation,
        ),
      );
      validate();
      if (!approved) throw StateError('Host denied this web destination');
      final grant = localReview == null
          ? await registry.approve(prepared)
          : await _authorization!.confirm(localReview);
      if (grant == null) throw StateError('Host confirmation unavailable');
      validate();
      final token = ToolCancellationToken();
      final detach = cancellation.onCancel(token.cancel);
      late T value;
      var effectStarted = false;
      _pending[request.invocationId] = (context) async {
        final authorization = registry.authorizationLink(context.request);
        void checkBeforeEffect() {
          validate();
          context.checkBeforeEffect();
          final intent = _intents[context.request.invocationId];
          if (intent != null) {
            authorization?.check(
              registry.database,
              toolId,
              destination,
              intent.payloadDigest,
            );
          }
          effectStarted = true;
        }

        value = await OutboundToolLedger(registry.database).run(
          toolId: toolId,
          authorization: authorization,
          channel: 'inquiry_web',
          isCancelled: () => cancellation.isCancelled,
          destination: destination,
          payload: const [],
          operation: (_) => operation(checkBeforeEffect),
        );
        validate();
        return ToolCallResult(
          status: ToolCallStatus.succeeded,
          summary: 'Bounded public HTTPS hop completed',
          data: {
            'destination': Uri(
              scheme: destination.scheme,
              host: destination.host,
              port: destination.hasPort ? destination.port : null,
              path: destination.path,
            ).toString(),
            'method': 'GET',
          },
        );
      };
      try {
        // Do not race invocation with cancellation: wait for the durable final
        // receipt. The bounded operation races its I/O and closes its transport.
        final result = await registry.invoke(
          request.withApproval(grant),
          cancellation: token,
        );
        if (result.status != ToolCallStatus.succeeded) {
          throw AssistantWebAuthorityFailure(
            interrupted: result.status == ToolCallStatus.interrupted,
          );
        }
        validate();
        return value;
      } catch (error) {
        if (error is AssistantWebAuthorityFailure) rethrow;
        throw AssistantWebAuthorityFailure(interrupted: effectStarted);
      } finally {
        _pending.remove(request.invocationId);
        detach();
      }
    } finally {
      if (boundInvocation != null) _intents.remove(boundInvocation);
    }
  }
}
