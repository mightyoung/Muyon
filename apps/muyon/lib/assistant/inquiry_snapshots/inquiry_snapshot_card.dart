import 'package:flutter/material.dart';
import 'package:muyon_ui/muyon_ui.dart';

import '../ontology_cards/ontology_card.dart';
import 'inquiry_readonly_snapshot.dart';

/// Presents one host-prepared inquiry snapshot using the trusted ontology card.
/// This widget has no read, navigation, or action path of its own.
final class InquirySnapshotCard extends StatelessWidget {
  const InquirySnapshotCard({super.key, required this.snapshot});

  final InquiryReadonlySnapshot snapshot;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '${snapshot.scene.label} · 已保存事实',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: MuyonTokens.space2),
      const Text('来源：询价插件的已保存记录；建议尚未写入'),
      const SizedBox(height: MuyonTokens.space2),
      Text(snapshot.sourceLabel),
      const SizedBox(height: MuyonTokens.space2),
      OntologyCard(snapshot: snapshot.record),
    ],
  );
}
