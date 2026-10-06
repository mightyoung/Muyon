import 'package:supplier_core/supplier_core.dart';

/// Ids of the seeded inquiry data.
class NorthStarFixtureData {
  NorthStarFixtureData({
    required this.projectId,
    required this.supplierA,
    required this.supplierB,
    required this.cableItem,
    required this.trayItem,
    required this.cableProduct,
    required this.firstInquiry,
  });
  final String projectId, supplierA, supplierB, cableItem, trayItem;
  final String cableProduct, firstInquiry;
}

/// Seeds through the inquiry module's own Store functions, the same way
/// `inquiry_write_tools_test` and `business_tools_test` do.
NorthStarFixtureData seedInquiry(Store store) {
  Map<String, Object?> supplier(String name) => {
    'name': name,
    'aliases': <String>[],
    'address': null,
    'categories': <String>[],
    'notes': null,
    'merged_into': null,
    'rating': null,
    'rating_note': null,
  };
  Map<String, Object?> item(
    String projectId,
    String name,
    String qty,
    String unitCost,
  ) => {
    'project_id': projectId,
    'category': 'material',
    'product_id': null,
    'name': name,
    'qty': qty,
    'unit': '米',
    'quotation_id': null,
    'unit_cost': unitCost,
    'unit_price': null,
    'notes': null,
  };
  final supplierA = store.save('supplier', supplier('北极星甲电气'));
  final supplierB = store.save('supplier', supplier('北极星乙线缆'));
  final projectId = store.save('project', {
    'code': 'NS-1',
    'name': '北极星验收项目',
    'status': 'active',
    'type': 'market',
    'level': 'A',
    'customer': null,
    'contract_no': null,
    'contract_amount': null,
    'department': null,
    'leader': null,
    'start_date': null,
    'end_date': null,
    'currency': 'CNY',
    'tax_mode': 'included',
    'markup_rate': '0',
    'notes': null,
  });
  final cable = store.save(
    'project_item',
    item(projectId, '电缆', '100', '11.80'),
  );
  final tray = store.save('project_item', item(projectId, '桥架', '20', '45.00'));
  final inquiry = store.createInquiry(
    projectId,
    '首轮询价',
    itemIds: [cable, tray],
    supplierIds: [supplierA, supplierB],
  );
  const context = (inquirer: '北极星验收', asOf: null);
  for (final (itemId, supplierId, price) in [
    (cable, supplierA, '12.50'),
    (cable, supplierB, '11.80'),
    (tray, supplierA, '45.00'),
    (tray, supplierB, '47.20'),
  ]) {
    store.quoteForInquiry(
      inquiry,
      itemId,
      supplierId,
      price: price,
      context: context,
    );
  }
  return NorthStarFixtureData(
    projectId: projectId,
    supplierA: supplierA,
    supplierB: supplierB,
    cableItem: cable,
    trayItem: tray,
    cableProduct:
        store.get('project_item', cable)!.data['product_id']! as String,
    firstInquiry: inquiry,
  );
}
