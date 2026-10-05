import 'package:flutter/material.dart';

/// Short, interruptible transitions; never animate every row in a data table.
abstract final class AppMotion {
  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ||
      WidgetsBinding
          .instance
          .platformDispatcher
          .accessibilityFeatures
          .reduceMotion;

  static Duration duration(BuildContext context, {int milliseconds = 180}) =>
      reduced(context) ? Duration.zero : Duration(milliseconds: milliseconds);
}

/// Keep native back gestures and platform transitions unless motion is reduced.
class AccessiblePageTransitions extends PageTransitionsBuilder {
  const AccessiblePageTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (AppMotion.reduced(context)) return child;
    final native =
        const PageTransitionsTheme().builders[Theme.of(context).platform] ??
        const FadeUpwardsPageTransitionsBuilder();
    return native.buildTransitions(
      route,
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}
