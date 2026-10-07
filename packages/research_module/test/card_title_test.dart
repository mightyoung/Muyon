import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_module/src/core/card_title.dart';

void main() {
  test('keeps emoji surrogate pairs whole at the truncation point', () {
    final title = cardTitleFromMarkdown('🙂' * 70, fallback: '研究卡');
    expect(title, '${'🙂' * 60}…');
    expect(title.characters.length, 61);
  });

  test('keeps Chinese characters whole at the truncation point', () {
    final title = cardTitleFromMarkdown(
      '${'长' * 70}\n\n正文',
      fallback: '研究卡',
    );
    expect(title, '${'长' * 60}…');
  });

  test('keeps combining marks with their base character', () {
    const cluster = 'e\u0301';
    final title = cardTitleFromMarkdown(cluster * 70, fallback: '研究卡');
    expect(title, '${cluster * 60}…');
    expect(title.characters.length, 61);
  });

  test('keeps zero-width-joiner emoji sequences whole', () {
    const family = '👨‍👩‍👧';
    final title = cardTitleFromMarkdown(family * 70, fallback: '研究卡');
    expect(title, '${family * 60}…');
    expect(title.characters.length, 61);
  });

  test('strips heading marks and uses the fallback for empty text', () {
    expect(cardTitleFromMarkdown('# 标题\n\n正文', fallback: '研究卡'), '标题');
    expect(cardTitleFromMarkdown('   ', fallback: '研究卡'), '研究卡');
  });
}
