import 'package:flutter/material.dart';
import 'package:muyon_ui/muyon_ui.dart';

/// The research workbench uses the shared Folio theme from `muyon_ui`.
ThemeData workbenchTheme({bool dark = false}) =>
    muyonTheme(dark ? Brightness.dark : Brightness.light);
