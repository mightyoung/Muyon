import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

class MutableLocalDestination implements DestinationRule {
  @override
  bool localExport = true;
  @override
  bool publicWeb = false;
  @override
  Set<String> fixedHosts = <String>{};
}

void main() {
  test(
    'validated local export snapshots survive later mutable rule getters',
    () {
      final rule = MutableLocalDestination();
      final tool = ExternalToolSpec(
        name: 'review_export',
        description: 'snapshot probe',
        effect: ToolEffect.export,
        destination: rule,
      );
      final channel = ChannelSpec(
        name: 'review_channel',
        description: 'snapshot probe',
        effect: ToolEffect.export,
        destination: rule,
        parameterSchema: const {'type': 'object'},
      );
      rule.localExport = false;
      rule.publicWeb = true;
      rule.fixedHosts.add('changed.example');
      for (final snapshot in [tool.destination, channel.destination]) {
        expect(identical(snapshot, rule), isFalse);
        expect(snapshot.localExport, isTrue);
        expect(snapshot.publicWeb, isFalse);
        expect(snapshot.fixedHosts, isEmpty);
        expect(localExportRuleProblems(ToolEffect.export, snapshot), isEmpty);
      }
    },
  );
}
