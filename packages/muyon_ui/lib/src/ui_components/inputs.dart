import 'package:flutter/material.dart';

import '../tokens.dart';
import 'state.dart';

bool _enabled(UiComponentState state, Object? callback) =>
    state == UiComponentState.ready && callback != null;

/// Pick one or several options; optionally type an option that is not listed.
class Choice extends StatefulWidget {
  const Choice({
    super.key,
    required this.label,
    required this.options,
    this.selected = const {},
    this.optionIds,
    this.selectedIds,
    this.onChangedIds,
    this.multiple = false,
    this.allowCustom = false,
    this.onChanged,
    this.state = UiComponentState.ready,
    this.errorMessage,
  }) : assert(optionIds == null || optionIds.length == options.length);
  final String label;
  final List<String> options;
  final Set<String> selected;
  final List<String>? optionIds;
  final Set<String>? selectedIds;
  final ValueChanged<Set<String>>? onChangedIds;
  final bool multiple, allowCustom;
  final ValueChanged<Set<String>>? onChanged;
  final UiComponentState state;
  final String? errorMessage;

  bool get usesIds => optionIds != null;
  Set<String> get selection => usesIds ? (selectedIds ?? const {}) : selected;
  String identityAt(int index) => usesIds ? optionIds![index] : options[index];
  String get selectedLabels => selection
      .map((id) {
        if (!usesIds) return id;
        final index = optionIds!.indexOf(id);
        return index < 0 ? '已失效选项' : options[index];
      })
      .join('、');

  String get textEquivalent =>
      '$label（${multiple ? '可多选' : '单选'}）：'
      '${selection.isEmpty ? '未选' : '已选 $selectedLabels'}；'
      '选项：${options.join('、')}';

  @override
  State<Choice> createState() => _ChoiceState();
}

class _ChoiceState extends State<Choice> {
  final custom = TextEditingController();
  final extra = <String>[];

  @override
  void dispose() {
    custom.dispose();
    super.dispose();
  }

  void toggle(Choice rendered, String option) {
    if (!mounted || !identical(widget, rendered)) return;
    final next = {...rendered.selection};
    if (rendered.multiple) {
      next.contains(option) ? next.remove(option) : next.add(option);
    } else {
      next
        ..clear()
        ..add(option);
    }
    if (rendered.usesIds) {
      rendered.onChangedIds?.call(Set.unmodifiable(next));
    } else {
      rendered.onChanged?.call(next);
    }
  }

  void addCustom(Choice rendered) {
    if (!mounted || !identical(widget, rendered)) return;
    if (rendered.usesIds) return;
    final text = custom.text.trim();
    if (text.isEmpty) return;
    if (!rendered.options.contains(text) && !extra.contains(text)) {
      setState(() => extra.add(text));
    }
    custom.clear();
    toggle(rendered, text);
  }

  @override
  Widget build(BuildContext context) {
    final rendered = widget;
    final t = MuyonTokens.of(context);
    VoidCallback? callbackAt(int index, List<String> all, bool enabled) {
      if (!enabled) return null;
      final identity = rendered.usesIds
          ? rendered.identityAt(index)
          : all[index];
      return () => toggle(rendered, identity);
    }

    final on = _enabled(
      widget.state,
      widget.usesIds ? widget.onChangedIds : widget.onChanged,
    );
    assert(
      widget.optionIds == null ||
          widget.optionIds!.toSet().length == widget.optionIds!.length,
    );
    final all = [...widget.options, if (!widget.usesIds) ...extra];
    return UiComponentFrame(
      state: widget.state,
      textEquivalent: widget.textEquivalent,
      errorMessage: widget.errorMessage,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label, style: TextStyle(color: t.ink2)),
          const SizedBox(height: MuyonTokens.space2),
          Wrap(
            spacing: MuyonTokens.space2,
            runSpacing: MuyonTokens.space2,
            children: [
              for (var optionIndex = 0; optionIndex < all.length; optionIndex++)
                Semantics(
                  button: true,
                  selected: widget.selection.contains(
                    widget.usesIds
                        ? widget.identityAt(optionIndex)
                        : all[optionIndex],
                  ),
                  inMutuallyExclusiveGroup: !widget.multiple,
                  label: all[optionIndex],
                  excludeSemantics: true,
                  onTap: callbackAt(optionIndex, all, on),
                  child: InkWell(
                    key: ValueKey(
                      'choice-${widget.usesIds ? widget.identityAt(optionIndex) : all[optionIndex]}',
                    ),
                    borderRadius: BorderRadius.circular(
                      MuyonTokens.optionRadius,
                    ),
                    onTap: callbackAt(optionIndex, all, on),
                    child: UiMinTarget(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: MuyonTokens.space4,
                          vertical: MuyonTokens.space2,
                        ),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color:
                              widget.selection.contains(
                                widget.usesIds
                                    ? widget.identityAt(optionIndex)
                                    : all[optionIndex],
                              )
                              ? t.accentTint
                              : t.surface,
                          border: Border.all(
                            color:
                                widget.selection.contains(
                                  widget.usesIds
                                      ? widget.identityAt(optionIndex)
                                      : all[optionIndex],
                                )
                                ? t.accent
                                : t.ruleStrong,
                          ),
                          borderRadius: BorderRadius.circular(
                            MuyonTokens.optionRadius,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.selection.contains(
                              widget.usesIds
                                  ? widget.identityAt(optionIndex)
                                  : all[optionIndex],
                            )) ...[
                              Icon(Icons.check, size: 18, color: t.accent),
                              const SizedBox(width: MuyonTokens.space1),
                            ],
                            Flexible(
                              child: Text(
                                all[optionIndex],
                                style: TextStyle(
                                  color:
                                      widget.selection.contains(
                                        widget.usesIds
                                            ? widget.identityAt(optionIndex)
                                            : all[optionIndex],
                                      )
                                      ? t.accent
                                      : t.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (widget.allowCustom && !widget.usesIds)
            Padding(
              padding: const EdgeInsets.only(top: MuyonTokens.space3),
              // Field on its own line so its label is not cut at 200% text.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const ValueKey('choice-custom'),
                    controller: custom,
                    enabled: on,
                    decoration: const InputDecoration(labelText: '其他（自己填写）'),
                    onSubmitted: on ? (_) => addCustom(rendered) : null,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: UiMinTarget(
                      child: TextButton(
                        key: const ValueKey('choice-custom-add'),
                        onPressed: on ? () => addCustom(rendered) : null,
                        child: const Text('添加'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Groups inputs under a title with one submit button. The host still
/// decides whether the submit does anything.
class MuyonForm extends StatelessWidget {
  const MuyonForm({
    super.key,
    required this.title,
    required this.children,
    this.submitLabel = '提交',
    this.onSubmit,
    this.state = UiComponentState.ready,
    this.errorMessage,
  });
  final String title, submitLabel;
  final List<Widget> children;
  final VoidCallback? onSubmit;
  final UiComponentState state;
  final String? errorMessage;

  String get textEquivalent => '表单：$title，按钮：$submitLabel';

  @override
  Widget build(BuildContext context) {
    final t = MuyonTokens.of(context);
    final on = _enabled(state, onSubmit);
    return UiComponentFrame(
      state: state,
      textEquivalent: textEquivalent,
      errorMessage: errorMessage,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(MuyonTokens.space4),
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(color: t.rule),
          borderRadius: BorderRadius.circular(MuyonTokens.cardRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            for (final c in children)
              Padding(
                padding: const EdgeInsets.only(top: MuyonTokens.space3),
                // Children may be ready library inputs or native TextFields.
                // Lock all user input paths without removing readable labels.
                child: Semantics(
                  readOnly: state == UiComponentState.readOnly,
                  blockUserActions: state != UiComponentState.ready,
                  child: ExcludeFocus(
                    excluding: state != UiComponentState.ready,
                    child: AbsorbPointer(
                      absorbing: state != UiComponentState.ready,
                      child: c,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: MuyonTokens.space4),
            Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: uiMinTarget,
                  minHeight: uiMinTarget,
                ),
                child: FilledButton(
                  key: const ValueKey('form-submit'),
                  onPressed: on ? onSubmit : null,
                  child: Text(submitLabel),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A number with minus and plus buttons, clamped to [min, max].
class NumberStepper extends StatelessWidget {
  const NumberStepper({
    super.key,
    required this.label,
    required this.value,
    this.min = 0,
    this.max = 999999,
    this.step = 1,
    this.unit,
    this.onChanged,
    this.state = UiComponentState.ready,
    this.errorMessage,
  });
  final String label;
  final double value, min, max, step;
  final String? unit;
  final ValueChanged<double>? onChanged;
  final UiComponentState state;
  final String? errorMessage;

  String get textEquivalent =>
      '$label：${uiFormatNumber(value)}${unit ?? ''}，范围 ${uiFormatNumber(min)} 到 ${uiFormatNumber(max)}';

  @override
  Widget build(BuildContext context) {
    final t = MuyonTokens.of(context);
    final on = _enabled(state, onChanged);
    void change(double delta) =>
        onChanged?.call((value + delta).clamp(min, max).toDouble());
    return UiComponentFrame(
      state: state,
      textEquivalent: textEquivalent,
      errorMessage: errorMessage,
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: t.ink2)),
          ),
          Semantics(
            button: true,
            label: '减少 $label',
            excludeSemantics: true,
            onTap: on && value > min ? () => change(-step) : null,
            child: UiMinTarget(
              child: IconButton(
                key: const ValueKey('stepper-minus'),
                onPressed: on && value > min ? () => change(-step) : null,
                icon: const Icon(Icons.remove),
              ),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 56),
            child: Text(
              '${uiFormatNumber(value)}${unit ?? ''}',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.ink, fontWeight: FontWeight.w600),
            ),
          ),
          Semantics(
            button: true,
            label: '增加 $label',
            excludeSemantics: true,
            onTap: on && value < max ? () => change(step) : null,
            child: UiMinTarget(
              child: IconButton(
                key: const ValueKey('stepper-plus'),
                onPressed: on && value < max ? () => change(step) : null,
                icon: const Icon(Icons.add),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Height of the slider's touch area; kept as one constant on purpose.
const double sliderTargetHeight = uiMinTarget;

class MuyonSlider extends StatelessWidget {
  const MuyonSlider({
    super.key,
    required this.label,
    required this.value,
    this.min = 0,
    this.max = 100,
    this.divisions,
    this.unit,
    this.onChanged,
    this.state = UiComponentState.ready,
    this.errorMessage,
  });
  final String label;
  final double value, min, max;
  final int? divisions;
  final String? unit;
  final ValueChanged<double>? onChanged;
  final UiComponentState state;
  final String? errorMessage;

  String get textEquivalent =>
      '$label：${uiFormatNumber(value)}${unit ?? ''}，范围 ${uiFormatNumber(min)} 到 ${uiFormatNumber(max)}';

  @override
  Widget build(BuildContext context) {
    final t = MuyonTokens.of(context);
    final on = _enabled(state, onChanged);
    return UiComponentFrame(
      state: state,
      textEquivalent: textEquivalent,
      errorMessage: errorMessage,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: TextStyle(color: t.ink2)),
              ),
              Text(
                '${uiFormatNumber(value)}${unit ?? ''}',
                style: TextStyle(color: t.ink, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          SizedBox(
            key: const ValueKey('slider-target'),
            height: sliderTargetHeight,
            // The slider itself only reports a value; give it a name.
            child: Semantics(
              label: label,
              child: Slider(
                value: value.clamp(min, max).toDouble(),
                min: min,
                max: max,
                divisions: divisions,
                label: uiFormatNumber(value),
                semanticFormatterCallback: (v) =>
                    '$label ${uiFormatNumber(v)}${unit ?? ''}',
                onChanged: on ? onChanged : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Toggle extends StatelessWidget {
  const Toggle({
    super.key,
    required this.label,
    required this.value,
    this.onChanged,
    this.state = UiComponentState.ready,
    this.errorMessage,
  });
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final UiComponentState state;
  final String? errorMessage;

  String get textEquivalent => '$label：${value ? '开' : '关'}';

  @override
  Widget build(BuildContext context) {
    final t = MuyonTokens.of(context);
    final on = _enabled(state, onChanged);
    return UiComponentFrame(
      state: state,
      textEquivalent: textEquivalent,
      errorMessage: errorMessage,
      child: Semantics(
        toggled: value,
        label: label,
        excludeSemantics: true,
        onTap: on ? () => onChanged!(!value) : null,
        child: InkWell(
          key: const ValueKey('toggle'),
          borderRadius: BorderRadius.circular(MuyonTokens.radius),
          onTap: on ? () => onChanged!(!value) : null,
          child: UiMinTarget(
            child: Row(
              children: [
                Expanded(
                  child: Text(label, style: TextStyle(color: t.ink)),
                ),
                IgnorePointer(
                  child: ExcludeSemantics(
                    child: Switch(value: value, onChanged: on ? (_) {} : null),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String uiDateText(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    this.value,
    this.first,
    this.last,
    this.onChanged,
    this.state = UiComponentState.ready,
    this.errorMessage,
  });
  final String label;
  final DateTime? value, first, last;
  final ValueChanged<DateTime>? onChanged;
  final UiComponentState state;
  final String? errorMessage;

  String get textEquivalent =>
      '$label：${value == null ? '未选择日期' : uiDateText(value!)}';

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate:
          value ??
          (first != null && now.isBefore(first!)
              ? first!
              : last != null && now.isAfter(last!)
              ? last!
              : now),
      firstDate: first ?? DateTime(now.year - 20),
      lastDate: last ?? DateTime(now.year + 20),
    );
    if (picked != null) onChanged?.call(picked);
  }

  @override
  Widget build(BuildContext context) {
    final t = MuyonTokens.of(context);
    final on = _enabled(state, onChanged);
    return UiComponentFrame(
      state: state,
      textEquivalent: textEquivalent,
      errorMessage: errorMessage,
      child: Semantics(
        button: true,
        label: '修改$label，当前${value == null ? '未选择' : uiDateText(value!)}',
        excludeSemantics: true,
        onTap: on ? () => _pick(context) : null,
        child: InkWell(
          key: const ValueKey('date-field'),
          borderRadius: BorderRadius.circular(MuyonTokens.inputRadius),
          onTap: on ? () => _pick(context) : null,
          child: UiMinTarget(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: MuyonTokens.space3,
                vertical: MuyonTokens.space2,
              ),
              decoration: BoxDecoration(
                border: Border.all(color: t.ruleStrong),
                borderRadius: BorderRadius.circular(MuyonTokens.inputRadius),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_outlined, size: 20, color: t.ink2),
                  const SizedBox(width: MuyonTokens.space2),
                  Expanded(
                    child: Text(
                      '$label  ${value == null ? '选择日期' : uiDateText(value!)}',
                      style: TextStyle(color: value == null ? t.ink3 : t.ink),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
