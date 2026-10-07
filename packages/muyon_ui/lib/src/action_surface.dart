import 'package:flutter/material.dart';

import 'tokens.dart';

/// Shared content-sized action surface. InkWell provides keyboard activation.
class ActionSurface extends StatefulWidget {
  const ActionSurface({
    super.key,
    required this.label,
    required this.child,
    this.onPressed,
    this.selected = false,
    this.background,
    this.foreground,
    this.minimum = MuyonTokens.minimumTarget,
    this.radius = MuyonTokens.pillRadius,
  });
  final String label;
  final Widget child;
  final VoidCallback? onPressed;
  final bool selected;
  final Color? background, foreground;
  final double minimum, radius;
  @override
  State<ActionSurface> createState() => _ActionSurfaceState();
}

class _ActionSurfaceState extends State<ActionSurface> {
  bool focused = false;
  @override
  Widget build(BuildContext context) {
    final t = MuyonTokens.of(context);
    return Semantics(
      label: widget.label,
      button: true,
      onTap: widget.onPressed,
      enabled: widget.onPressed != null,
      selected: widget.selected,
      excludeSemantics: true,
      child: Tooltip(
        message: widget.label,
        excludeFromSemantics: true,
        child: Material(
          color: widget.background ?? t.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(widget.radius),
            side: BorderSide(
              color: focused
                  ? (widget.background == t.acc ? t.ink : t.acc)
                  : t.ruleStrong,
              width: focused ? 2 : 1,
            ),
          ),
          child: InkWell(
            onTap: widget.onPressed,
            onFocusChange: (value) => setState(() => focused = value),
            borderRadius: BorderRadius.circular(widget.radius),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: widget.minimum,
                minHeight: widget.minimum,
              ),
              child: Padding(
                padding: const EdgeInsets.all(MuyonTokens.space2),
                child: IconTheme(
                  data: IconThemeData(
                    color: widget.foreground ?? t.ink,
                    size: MuyonTokens.iconSize,
                  ),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(color: widget.foreground ?? t.ink),
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
