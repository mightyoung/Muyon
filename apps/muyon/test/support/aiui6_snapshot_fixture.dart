import 'dart:io';

import 'package:muyon/app/bootstrap.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:supplier_core/supplier_core.dart';

import '../../../../packages/supplier_core/test/fixtures.dart' as fixture;

/// Explicit test setup writes real local records; the production adapter reads.
class InquirySnapshotFixture {
  InquirySnapshotFixture._(this.root, this.host, this.refs);
  final Directory root;
  final MuyonHost host;
  final Map<String, ObjectRef> refs;

  static Future<InquirySnapshotFixture> open() async {
    final root = Directory.systemTemp.createTempSync('aiui6-readonly-');
    final host = await MuyonHost.open('${root.path}/data');
    await host.activateInquiry();
    final store = host.inquiry!.runtime.state.store;
    final supplier = store.save('supplier', fixture.supplier('已保存供应商'));
    final product = store.save('product', fixture.product('已保存物料'));
    final project = store.save('project', fixture.project('READONLY'));
    final item = store.save('project_item', {
      ...fixture.item(project, 'labor', name: '真实预算行', qty: '2', cost: '987654.123'),
      'requirement': null,
    });
    final quote = store.save('quotation', fixture.quotation(
      supplier, product, project, '123456.789'));
    final inquiry = store.createInquiry(project, '真实询价单',
      itemIds: [item], supplierIds: [supplier]);
    final source = host.scopeResolver.sources.singleWhere(
      (source) => source.moduleId == 'inquiry');
    final refs = <String, ObjectRef>{};
    for (final entry in {'project_item': item, 'quotation': quote, 'inquiry': inquiry}.entries) {
      refs[entry.key] = (await source.resolve(ObjectRef(moduleId: 'inquiry',
        objectType: entry.key, objectId: entry.value, nativeProjectId: project)))!;
    }
    return InquirySnapshotFixture._(root, host, refs);
  }

  Future<void> close() async {
    await host.close();
    root.deleteSync(recursive: true);
  }
}
