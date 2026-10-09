import 'package:flutter/material.dart';
import 'package:muyon_module_api/ui_contract.dart';

/// Read-only projection from trusted snapshot facts, never from rejected nodes.
Widget snapshotFallback(DataSnapshot snapshot, InteractionIntent intent) {
  final facts = snapshot.facts.entries.where(
    (e) =>
        intent.mandatoryStates.contains(e.value.state) ||
        intent.requiredBindings.contains(BindingRef.fact(e.key)),
  );
  final sources = <String>{
    for (final e in facts) ...e.value.sourceRefs,
    for (final ref in intent.requiredBindings)
      if (ref.kind == BindingKind.sourceSpan) ref.id,
  };
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final e in facts)
        SelectableText(
          '${e.value.field}: ${e.value.value ?? "Unknown"} · ${e.value.state.name}',
        ),
      for (final id in sources)
        if (snapshot.sources[id] case final source?)
          if (snapshot.sourceDigests[source.artifact.artifactId] ==
                  source.artifact.contentDigest &&
              source.start >= 0 &&
              source.end > source.start &&
              source.end <= source.originalText.length)
            SelectableText(
              source.originalText.substring(source.start, source.end),
            )
          else
            const Text('Source changed. Original span is stale.'),
    ],
  );
}
