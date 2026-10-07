import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:supplier_core/supplier_core.dart';
import 'package:uuid/uuid.dart';

import '../platform/tool_registry.dart';
import '../platform/outbound_tool_ledger.dart';

/// Registers a recorded channel, not a model-callable grant operation. Only an
/// invocation-bound application closure can execute this provider's handler.
class InquiryWebAuthority implements AssistantWebAuthority {
  InquiryWebAuthority(this.registry) {
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
    final prepared = await registry.prepare(request);
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
    final grant = await registry.approve(prepared);
    validate();
    final token = ToolCancellationToken();
    final detach = cancellation.onCancel(token.cancel);
    late T value;
    var effectStarted = false;
    _pending[request.invocationId] = (context) async {
      void checkBeforeEffect() {
        validate();
        context.checkBeforeEffect();
        effectStarted = true;
      }

      value = await OutboundToolLedger(registry.database).run(
        toolId: toolId,
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
        data: {'destination': destination.toString(), 'method': 'GET'},
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
  }
}
