import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:supplier_core/supplier_core.dart';
import 'package:uuid/uuid.dart';

import '../platform/tool_registry.dart';

/// Registers a recorded channel, not a model-callable grant operation. Only an
/// invocation-bound application closure can execute this provider's handler.
class InquiryHubAuthority implements HubAuthority {
  InquiryHubAuthority(this.registry) {
    registry.register(
      providerId: 'inquiry',
      descriptor: ToolDescriptor(
        toolId: toolId,
        moduleId: 'inquiry',
        effect: ToolEffect.network,
        // Internal channel: only the inquiry module's own, host-reviewed code
        // path may use it; the assistant must never pick it.
        modelSelectable: false,
        description:
            '资料中心内部通道：经宿主一次性确认后联网访问资料中心。发布会把你选定的供应商、物料和报价资料'
            '发送到该中心，属于远端写入；结果不确定时先向中心查询，不会自动重发。仅供询价模块内部使用。',
        supportsCancel: true,
        parameterSchema: {
          'type': 'object',
          'properties': {
            'method': {
              'type': 'string',
              'enum': ['GET', 'POST'],
            },
            'url': {'type': 'string', 'maxLength': 2048},
            'payloadDigest': {'type': 'string', 'maxLength': 64},
            'publishes': {'type': 'boolean'},
          },
          'required': ['method', 'url', 'payloadDigest', 'publishes'],
          'additionalProperties': false,
        },
      ),
      supportedScopes: {AssistantScopeKind.global},
      dataModuleIds: {'inquiry'},
      handler: (context) {
        final pending = _pending[context.request.invocationId];
        if (pending == null) throw StateError('No trusted hub operation');
        return pending(context);
      },
    );
  }

  void disable() => registry.setAvailability(
    toolId,
    available: false,
    reason: 'Inquiry module is closed',
  );

  static const toolId = 'inquiry.hub.request';
  final ToolRegistry registry;
  final _pending = <String, Future<ToolCallResult> Function(ToolCallContext)>{};

  @override
  Future<T> run<T>({
    required HubRequest request,
    required AiCancellation cancellation,
    required HubReview? review,
    required void Function() validateSession,
    required Future<T> Function(void Function()) operation,
  }) async {
    void validate() {
      cancellation.check();
      validateSession();
      if (registry.inspect(toolId)?.available != true) {
        throw StateError('Host hub channel is unavailable');
      }
    }

    validate();
    if (review == null) throw StateError('No trusted host review');
    final payloadDigest = await hubDigest(request.body);
    validate();
    final invocation = ToolCallRequest(
      invocationId: const Uuid().v4(),
      toolId: toolId,
      scope: const AssistantScope.global(),
      destination: request.destination.toString(),
      parameters: {
        'method': request.method,
        'url': request.destination.toString(),
        'payloadDigest': payloadDigest,
        'publishes': request.publishes,
      },
    );
    final prepared = await registry.prepare(invocation);
    validate();
    final approved = await cancellation.wait(
      review(
        HubApprovalPreview(
          request,
          invocation.invocationId,
          prepared.parameterDigest,
          payloadDigest,
        ),
        cancellation,
      ),
    );
    validate();
    if (!approved) throw StateError('Host denied this hub request');
    final grant = await registry.approve(prepared);
    validate();
    final token = ToolCancellationToken();
    final detach = cancellation.onCancel(token.cancel);
    late T value;
    _pending[invocation.invocationId] = (context) async {
      void checkBeforeEffect() {
        validate();
        context.checkBeforeEffect();
      }

      value = await operation(checkBeforeEffect);
      validate();
      return ToolCallResult(
        status: ToolCallStatus.succeeded,
        summary: 'Bounded hub request completed',
        data: {'method': request.method, 'payloadDigest': payloadDigest},
      );
    };
    try {
      // Do not race invocation with cancellation: wait for the durable final
      // receipt. The bounded operation races its I/O and closes its transport.
      final result = await registry.invoke(
        invocation.withApproval(grant),
        cancellation: token,
      );
      if (result.status != ToolCallStatus.succeeded) {
        throw HubException('宿主未完成本次资料中心请求记录');
      }
      validate();
      return value;
    } catch (_) {
      throw HubException('资料中心请求或宿主记录未完成');
    } finally {
      _pending.remove(invocation.invocationId);
      detach();
    }
  }
}
