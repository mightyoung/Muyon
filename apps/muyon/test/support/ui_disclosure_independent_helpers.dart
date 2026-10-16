// Independent helpers for ui_disclosure_independent_test.dart only.
// Explicit test setup writes real local inquiry records through the public
// store; production code (InquiryUiPlanningSource, UiPlanningHarness, the
// Motivation/Stream providers and UiPlanningRequest.toJson) does the rest.
// No real model and no network: the "model" is a capturing callback.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:supplier_core/supplier_core.dart';

import '../../../../packages/supplier_core/test/fixtures.dart' as fixture;

/// One unique canary per data kind. Never reused between kinds.
abstract final class DisclosureCanary {
  // Free text (user decision: never sent to the model by default).
  static const itemRequirement = 'CANARY-ITEM-REQUIREMENT-q7Zk';
  static const itemNotes = 'CANARY-ITEM-NOTES-w2Lp';
  static const quoteAwardNote = 'CANARY-QUOTE-AWARD-NOTE-x9Rm';
  static const quoteNotes = 'CANARY-QUOTE-NOTES-b4Hd';
  static const inquiryNotes = 'CANARY-INQUIRY-NOTES-t6Vc';
  // Unknown (not in ontology) stored key.
  static const unknownField = 'CANARY-UNKNOWN-FIELD-m3Qs';
  // Masked commercial / personal values (low entropy on purpose).
  static const itemUnitCost = '73519.27';
  static const quotePrice = '61842.33';
  static const quoteInquirer = 'CANARY-INQUIRER-NAME-p8Ny';
  // Generic UI checkpoint (recovery context).
  static const checkpointExtracted = 'CANARY-CHECKPOINT-EXTRACTED-e1Ka';
  static const checkpointOverride = 'CANARY-CHECKPOINT-OVERRIDE-o5Gu';
  static const checkpointView = 'CANARY-CHECKPOINT-VIEW-v8Jt';
  static const checkpointDraft = 'CANARY-CHECKPOINT-DRAFT-d3Wy';
  // Contract-level synthetic snapshot.
  static const notDisclosedResidual = 'CANARY-NOTDISCLOSED-RESIDUAL-r2Fx';
  static const restrictedSourceText = 'CANARY-RESTRICTED-SOURCE-TEXT-s7Bn';
  static const unknownViewValue = 'CANARY-UNKNOWN-VIEW-VALUE-u4Cz';
  static const unknownInitialUiState = 'CANARY-UNKNOWN-INITIAL-UI-i9Dv';
  // Explicitly allowed, non-sensitive (must still be serialized).
  static const allowedItemName = 'ALLOW-ITEM-NAME-n5Tq';
  static const allowedItemUnit = 'ALLOW-UNIT-k2Hm';
  static const allowedInquiryTitle = 'ALLOW-INQUIRY-TITLE-j8Pw';
  static const allowedQuoteLeadDays = 7391;
  static const allowedVerifiedFact = 'ALLOW-VERIFIED-FACT-h6Ls';

  static const freeText = {
    'project_item.requirement': itemRequirement,
    'project_item.notes': itemNotes,
    'quotation.award_note': quoteAwardNote,
    'quotation.notes': quoteNotes,
    'inquiry.notes': inquiryNotes,
  };
  static const masked = {
    'project_item.unit_cost': itemUnitCost,
    'quotation.price': quotePrice,
    'quotation.inquirer_name': quoteInquirer,
  };
  static const checkpoint = {
    'extracted': checkpointExtracted,
    'userOverrides': checkpointOverride,
    'viewValues': checkpointView,
    'readableDraft': checkpointDraft,
  };
}

/// Real host + inquiry store with the canary records.
class DisclosureInquiryFixture {
  DisclosureInquiryFixture._(
    this.root,
    this.host,
    this.refs,
    this.unknownStored,
  );
  final Directory root;
  final MuyonHost host;
  final Map<String, ObjectRef> refs;

  /// Whether the store kept the unknown key (if not, that check is vacuous).
  final bool unknownStored;

  static Future<DisclosureInquiryFixture> open() async {
    final root = Directory.systemTemp.createTempSync('ui-disclosure-indep-');
    final host = await MuyonHost.open('${root.path}/data');
    await host.activateInquiry();
    final store = host.inquiry!.runtime.state.store;
    final supplier = store.save('supplier', fixture.supplier('披露测试供应商'));
    final product = store.save('product', fixture.product('披露测试物料'));
    final project = store.save('project', fixture.project('DISCLOSE'));
    final item = store.save('project_item', {
      ...fixture.item(
        project,
        'labor',
        name: DisclosureCanary.allowedItemName,
        qty: '3',
        cost: DisclosureCanary.itemUnitCost,
      ),
      'unit': DisclosureCanary.allowedItemUnit,
      'requirement': DisclosureCanary.itemRequirement,
      'notes': DisclosureCanary.itemNotes,
    });
    final quote = store.save('quotation', {
      ...fixture.quotation(
        supplier,
        product,
        project,
        DisclosureCanary.quotePrice,
      ),
      'inquirer_name': DisclosureCanary.quoteInquirer,
      'lead_time_days': DisclosureCanary.allowedQuoteLeadDays,
      'award_note': DisclosureCanary.quoteAwardNote,
      'notes': DisclosureCanary.quoteNotes,
    });
    final inquiry = store.createInquiry(
      project,
      DisclosureCanary.allowedInquiryTitle,
      itemIds: [item],
      supplierIds: [supplier],
    );
    store.save('inquiry', {
      ...store.get('inquiry', inquiry)!.data,
      'notes': DisclosureCanary.inquiryNotes,
    }, id: inquiry);
    // Unknown key: written through the public store if it accepts it.
    var unknownStored = false;
    try {
      store.save('project_item', {
        ...store.get('project_item', item)!.data,
        'x_unregistered_field': DisclosureCanary.unknownField,
      }, id: item);
      unknownStored = jsonEncode(store.get('project_item', item)!.data)
          .contains(DisclosureCanary.unknownField);
    } catch (_) {
      unknownStored = false;
    }
    final source = host.scopeResolver.sources.singleWhere(
      (source) => source.moduleId == 'inquiry',
    );
    final refs = <String, ObjectRef>{};
    for (final entry in {
      'project_item': item,
      'quotation': quote,
      'inquiry': inquiry,
    }.entries) {
      refs[entry.key] = (await source.resolve(
        ObjectRef(
          moduleId: 'inquiry',
          objectType: entry.key,
          objectId: entry.value,
          nativeProjectId: project,
        ),
      ))!;
    }
    return DisclosureInquiryFixture._(root, host, refs, unknownStored);
  }

  /// Raw stored JSON (host-internal), used only for fingerprint analysis.
  String rawRow(String type) =>
      host.inquiry!.runtime.state.store.db.select(
            'SELECT data FROM $type WHERE id=?',
            [refs[type]!.objectId],
          ).single['data']
          as String;

  Future<void> close() async {
    await host.close();
    root.deleteSync(recursive: true);
  }
}

/// Captures exactly what the production providers hand to the model callback.
/// The second argument of requestModel is the model-visible prompt; the
/// UiPlanningRequest object itself stays host-side.
class CapturingModel {
  final prompts = <String>[];
  final requests = <UiPlanningRequest>[];

  Future<String> Function(UiPlanningRequest, String) batch(
    String Function(UiPlanningRequest) reply,
  ) => (request, prompt) async {
    requests.add(request);
    prompts.add(prompt);
    return reply(request);
  };

  Future<void> Function(UiPlanningRequest, String, void Function(String))
  stream(String Function(UiPlanningRequest) reply) =>
      (request, prompt, receive) async {
        requests.add(request);
        prompts.add(prompt);
        receive(reply(request));
      };
}

/// Every canary from [canaries] that occurs in [modelVisible].
Map<String, String> leaked(String modelVisible, Map<String, String> canaries) =>
    {
      for (final e in canaries.entries)
        if (modelVisible.contains(e.value)) e.key: e.value,
    };

String sha256Hex(String value) => sha256.convert(utf8.encode(value)).toString();

/// A valid aiui-stream/2 answer binding every required fact of [request].
String validStreamFor(UiPlanningRequest request) {
  String node(
    String id,
    String component, {
    String? parent,
    Map<String, Object?> props = const {},
    Map<String, Object?> bind = const {},
  }) => jsonEncode({
    'op': 'node',
    'id': id,
    'component': component,
    'parent': ?parent,
    'props': props,
    'bind': bind,
  });
  final lines = [
    node('root', 'PageScaffold', props: {'title': '已保存事实'}),
  ];
  var i = 0;
  for (final binding in request.intent.requiredBindings) {
    lines.add(
      node(
        'f${i++}',
        'KeyValue',
        parent: 'root',
        bind: {
          'value': {'kind': binding.kind.name, 'id': binding.id},
        },
      ),
    );
  }
  lines.add('{"op":"end"}');
  return '${lines.join('\n')}\n';
}
