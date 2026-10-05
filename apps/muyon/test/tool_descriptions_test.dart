import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

/// E6: every tool registered at startup (except MCP tools, which carry their
/// own remote descriptions) must have a description that tells a model what it
/// does and whether it writes, exports or sends data. Descriptions are data,
/// not instructions, and never promise authorization.
void main() {
  test('startup tools carry safe, effect-accurate descriptions', () async {
    final root = Directory.systemTemp.createTempSync('tool-desc-');
    final host = await MuyonHost.open(root.path);
    try {
      final tools = host.tools.list();
      expect(tools, isNotEmpty);
      const forbidden = ['无需确认', '直接执行', '已授权'];
      const effectWords = ['写入', '修改', '删除', '导出', '发送', '下载', '联网'];
      for (final tool in tools) {
        final id = tool.descriptor.toolId;
        if (tool.providerId.startsWith('mcp:')) continue;
        final description = tool.descriptor.description;
        expect(description.trim(), isNotEmpty, reason: '$id 缺少说明');
        expect(
          description.length,
          inInclusiveRange(20, 200),
          reason: '$id 说明长度 ${description.length}',
        );
        for (final word in forbidden) {
          expect(
            description.contains(word),
            isFalse,
            reason: '$id 含“$word”',
          );
        }
        if (tool.accessLevel != ToolAccessLevel.read) {
          expect(
            effectWords.any(description.contains),
            isTrue,
            reason: '$id（${tool.accessLevel.name}）未写明写入/导出/发送效果',
          );
        }
      }
    } finally {
      await host.close();
      root.deleteSync(recursive: true);
    }
  });
}
