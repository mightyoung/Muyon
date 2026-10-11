import 'package:flutter/material.dart';

import '../assistant/personal_agent.dart';
import '../assistant/ui_presentation_preference.dart';

/// Presentation preference only; mandatory approvals remain outside this gate.
class UiPlanningPreferenceSwitch extends StatefulWidget {
  const UiPlanningPreferenceSwitch({super.key, required this.agent,
    this.title = '界面与可视化'});
  final PersonalAgent agent;
  final String title;
  @override
  State<UiPlanningPreferenceSwitch> createState() => _UiPlanningPreferenceSwitchState();
}

class _UiPlanningPreferenceSwitchState extends State<UiPlanningPreferenceSwitch> {
  bool saving = false, failed = false;
  int fieldGeneration = 0;
  Future<void> save(UiPresentationMode? value) async {
    if (saving || value == null) return;
    final agent = widget.agent;
    setState(() { saving = true; failed = false; });
    try { await agent.savePresentationMode(value); }
    catch (_) { if (mounted && identical(widget.agent, agent)) setState(() {
      failed = true;
      // FormField changes its own value before async persistence. Recreate it
      // from the committed host mode on failure, never the tentative choice.
      fieldGeneration++;
    }); }
    finally { if (mounted && identical(widget.agent, agent)) setState(() => saving = false); }
  }
  @override
  void didUpdateWidget(UiPlanningPreferenceSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.agent, widget.agent)) { saving = false; failed = false; }
  }
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DropdownButtonFormField<UiPresentationMode>(
        key: ValueKey('${widget.agent.presentationMode.name}:$fieldGeneration'),
        initialValue: widget.agent.presentationMode,
        decoration: InputDecoration(labelText: widget.title),
        items: [for (final mode in UiPresentationMode.values)
          DropdownMenuItem(value: mode, child: Text(mode.label))],
        onChanged: saving ? null : save),
      Text(failed ? '设置未保存，请重试' : '少用仅在明确请求展示时规划；模型与业务操作仍需既有审批'),
    ],
  );
}
