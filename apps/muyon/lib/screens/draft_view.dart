import 'package:flutter/material.dart';
import 'package:muyon_ui/muyon_ui.dart';

import '../assistant/agent_drafts.dart';

/// The draft of a reply being streamed (ADR-0005 §5.3). Everything shown here
/// comes from [AgentDraft.text], which the assistant core has already reduced
/// to what the person may read; this widget only adds the state caption.
class DraftView extends StatelessWidget {
  const DraftView({super.key, required this.draft});
  final AgentDraft draft;

  @override
  Widget build(BuildContext context) {
    final tokens = MuyonTokens.of(context);
    final theme = Theme.of(context);
    final waiting = draft.stage == DraftStage.generating && draft.text.isEmpty;
    final caption = switch (draft.stage) {
      DraftStage.generating when waiting => '正在思考…',
      DraftStage.generating => '生成中，尚未确认完成',
      DraftStage.preparingTool => '正在准备调用工具…',
      DraftStage.interrupted => '已中断，部分内容未保存',
      DraftStage.discarded => '回复格式不符，已丢弃',
      DraftStage.committed => '',
    };
    final warn =
        draft.stage == DraftStage.interrupted ||
        draft.stage == DraftStage.discarded;
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        key: const ValueKey('assistant-draft'),
        decoration: BoxDecoration(
          color: warn ? tokens.amberBg : tokens.sunken,
          borderRadius: BorderRadius.circular(MuyonTokens.radius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(MuyonTokens.space3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (draft.text.isNotEmpty) ...[
                // Plain text: nothing here is interpreted as markup.
                SelectableText(draft.text),
                const SizedBox(height: MuyonTokens.space2),
              ],
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (draft.stage == DraftStage.generating ||
                      draft.stage == DraftStage.preparingTool) ...[
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: MuyonTokens.space2),
                  ],
                  Flexible(
                    child: Text(
                      caption,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: warn ? tokens.amber : tokens.ink2,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
