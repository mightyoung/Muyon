import 'package:muyon_module_api/ui_contract.dart';

/// Fixed host copy for derived presentation outputs. Model reason text is not
/// evidence of a host failure or a person's presentation preference.
enum UiPlanningReasonCategory { user, host, model }

final class UiPlanningReason {
  const UiPlanningReason(this.code, this.category, this.description);
  final String code, description;
  final UiPlanningReasonCategory category;

  static const _host = UiPlanningReasonCategory.host;
  static const _user = UiPlanningReasonCategory.user;
  static const _model = UiPlanningReasonCategory.model;
  static const _reasons = <String, UiPlanningReason>{
    'user_presentation_changed': UiPlanningReason(
      'user_presentation_changed',
      _user,
      '呈现偏好已由用户更改，本轮内容卡不再使用。',
    ),
    'user_text_only': UiPlanningReason(
      'user_text_only',
      _user,
      '当前选择「只用文字」，不显示内容卡。',
    ),
    'user_explicit_request_required': UiPlanningReason(
      'user_explicit_request_required',
      _user,
      '当前选择「少用」，本轮未从宿主入口明确请求内容卡。',
    ),
    'planning_disabled': UiPlanningReason(
      'planning_disabled',
      _host,
      '内容卡规划当前未启用。',
    ),
    'host_request_changed': UiPlanningReason(
      'host_request_changed',
      _host,
      '呈现请求已变化，本次布局不再使用。',
    ),
    'host_state_unavailable': UiPlanningReason(
      'host_state_unavailable',
      _host,
      '宿主事实暂不可读取，内容卡暂不显示。',
    ),
    'stale_host_state': UiPlanningReason(
      'stale_host_state',
      _host,
      '请求中的事实或界面版本已过期。',
    ),
    'answer_unavailable': UiPlanningReason(
      'answer_unavailable',
      _host,
      '尚无可用于规划内容卡的文字回答。',
    ),
    'host_state_changed': UiPlanningReason(
      'host_state_changed',
      _host,
      '宿主事实或呈现状态已变化，本次布局不再使用。',
    ),
    'cancelled': UiPlanningReason('cancelled', _host, '界面规划已取消，已读取事实仅供只读查看。'),
    'provider_unavailable': UiPlanningReason(
      'provider_unavailable',
      _host,
      '界面规划服务暂不可用，已使用只读事实展示。',
    ),
    'invalid_decision': UiPlanningReason(
      'invalid_decision',
      _host,
      '布局决策未通过宿主检查，已使用只读事实展示。',
    ),
    'stale_surface': UiPlanningReason(
      'stale_surface',
      _host,
      '布局的界面版本已过期，已使用只读事实展示。',
    ),
    'invalid_plan': UiPlanningReason(
      'invalid_plan',
      _host,
      '布局未通过宿主校验，已使用只读事实展示。',
    ),
    'current_authority_changed': UiPlanningReason(
      'current_authority_changed',
      _host,
      '当前操作权限已变化，已使用只读事实展示。',
    ),
    'planner_timeout': UiPlanningReason(
      'planner_timeout',
      _host,
      '界面规划超时，已使用只读事实展示。',
    ),
    'planner_unavailable': UiPlanningReason(
      'planner_unavailable',
      _host,
      '界面规划暂不可用，已使用只读事实展示。',
    ),
    'malformed_stream': UiPlanningReason(
      'malformed_stream',
      _host,
      '界面流格式未通过检查，已使用只读事实展示。',
    ),
    'limit_exceeded': UiPlanningReason(
      'limit_exceeded',
      _host,
      '界面流超出宿主限制，已使用只读事实展示。',
    ),
    'incomplete': UiPlanningReason('incomplete', _host, '界面流未完成，已使用只读事实展示。'),
    'model_unavailable': UiPlanningReason(
      'model_unavailable',
      _host,
      '规划模型暂不可用，已使用只读事实展示。',
    ),
    'transport_error': UiPlanningReason(
      'transport_error',
      _host,
      '界面流传输中断，已使用只读事实展示。',
    ),
    'validated_stream_2': UiPlanningReason(
      'validated_stream_2',
      _host,
      '流式内容卡已通过宿主校验。',
    ),
    'model_no_card': UiPlanningReason(
      'model_no_card',
      _model,
      '模型本轮未提供内容卡，保留文字回答。',
    ),
    'model_supplement': UiPlanningReason(
      'model_supplement',
      _model,
      '已校验内容卡，作为文字回答的补充。',
    ),
    'model_replace_presentation': UiPlanningReason(
      'model_replace_presentation',
      _model,
      '已校验内容卡用于呈现，原文字回答保留。',
    ),
  };

  static UiPlanningReason forCode(String code) =>
      _reasons[code] ?? _reasons['planner_unavailable']!;

  static UiPlanningReason host(String code) {
    final reason = forCode(code);
    return reason.category == _model || code == 'validated_stream_2'
        ? _reasons['planner_unavailable']!
        : reason;
  }

  /// Only these three decision-consistent codes can come from a batch/model
  /// provider. Even a model spelling a host code does not gain that provenance.
  static UiPlanningResult modelResult(UiPlanningResult value) =>
      UiPlanningResult(
        decision: value.decision,
        reasonCode: value.reasonCode.isEmpty
            ? ''
            : switch (value.decision) {
                UiDisplayDecision.textOnly => 'model_no_card',
                UiDisplayDecision.supplement => 'model_supplement',
                UiDisplayDecision.replacePresentation =>
                  'model_replace_presentation',
              },
        plan: value.plan,
      );
}
