import 'package:flutter/material.dart';
import 'package:muyon_ui/muyon_ui.dart';
import 'package:muyon_ui/dynamic_ui.dart';

import 'fixture_ports.dart';

class PreviewApp extends StatelessWidget {
  const PreviewApp({super.key, required this.fixture});
  final PreviewFixture fixture;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Muyon semantic preview',
    theme: muyonTheme(Brightness.light),
    home: _PreviewHome(initial: fixture),
  );
}

class _PreviewHome extends StatefulWidget {
  const _PreviewHome({required this.initial});
  final PreviewFixture initial;
  @override
  State<_PreviewHome> createState() => _PreviewHomeState();
}

class _PreviewHomeState extends State<_PreviewHome> {
  late PreviewFixture fixture = widget.initial;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Muyon · public fixture preview')),
    body: SafeArea(
      child: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 12,
                    children: [
                      TextButton(
                        onPressed: () =>
                            setState(() => fixture = comparisonFixture()),
                        child: const Text('Fixture A'),
                      ),
                      TextButton(
                        onPressed: () => setState(
                          () => fixture = comparisonFixture(alternative: true),
                        ),
                        child: const Text('Fixture B'),
                      ),
                      TextButton(
                        onPressed: () => setState(
                          () => fixture = comparisonFixture(invalid: true),
                        ),
                        child: const Text('Invalid plan fallback'),
                      ),
                    ],
                  ),
                ),
                SemanticUiSurface(
                  snapshot: fixture.snapshot,
                  intent: fixture.intent,
                  result: fixture.plan,
                  originalAnswer: fixture.answer,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
