import 'dart:io';
import 'dart:convert';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon_module_api/muyon_module_api.dart' show ModuleSchema, ModuleMigration;
// Non-author DB boundary assertions. Fixtures adapted from author regression tests; author files remain unchanged.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/ui_formula_registry.dart';
import 'package:muyon/platform/ui_recompute_adapter.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';

const _ref = SnapshotRef('lib2-provenance', 4);
const _artifact = ArtifactRef(
  moduleId: 'inquiry',
  artifactId: 'lib2-provenance-quote',
  contentDigest: 'lib2-provenance-digest',
);
const _limits = UiFormulaLimits(
  maxInputs: 32,
  maxDecimalBytes: 256,
  maxInputBytes: 16384,
);

SourceSpanRef _span(String text) => SourceSpanRef(
  artifact: _artifact,
  originalText: text,
  start: 0,
  end: text.length,
);

ObjectRef _obj(String id) => ObjectRef(
  moduleId: 'inquiry',
  objectType: 'quote_line',
  objectId: id,
  revisionRef: '1',
);

/// Host-shaped token: the draft revision is the live session/context
/// revision, as a real host probe reads it.
UiPublishToken _token(SnapshotRef base, {int draftRevision = 0}) =>
    UiPublishToken(
      baseSnapshotRef: base,
      draftRevision: draftRevision,
      hostGeneration: 1,
      sourceGeneration: 1,
      permissionGeneration: 1,
      scopeKey: 'lib2-provenance',
    );

SnapshotFact _fact(
  String object,
  String field,
  Object? value,
  FactState state, {
  required String unit,
  List<String> sources = const [],
}) => SnapshotFact(
  object: _obj(object),
  field: field,
  value: value,
  state: state,
  unit: unit,
  sourceRefs: sources,
);

UiFormulaDefinition _product(
  String computationId,
  String priceFact, {
  String object = 'a',
  String field = 'price',
}) => UiFormulaDefinition.product(
  computationId: computationId,
  quantity: const UiFormulaSlot.uiState('qty', unit: '件'),
  unitPrice: UiFormulaSlot.fact(
    priceFact,
    object: _obj(object),
    field: field,
    unit: 'CNY/件',
  ),
  currency: 'CNY',
  quantityUnit: '件',
  decimalPolicy: UiFormulaDecimalPolicy.supplierCoreUnsigned,
);

UiNode _metric(String id, String computed, {String label = '行成本'}) => UiNode(
  id: id,
  component: 'Metric',
  properties: {'label': label},
  bindings: {'value': BindingRef.computed(computed)},
);

/// A host-accepted library-2 base. Every [oldValues] entry is a previously
/// published computed result that claims `verified` with a stale unit and a
/// stale source, so any reuse is observable.
ValidatedUiPlan _base({
  UiCatalog? catalog,
  required Map<String, SnapshotFact> facts,
  required Map<String, UiFormulaDefinition> defs,
  required Map<String, Object?> oldValues,
  required List<UiNode> nodes,
  Map<String, SourceSpanRef> sources = const {},
  Map<String, Object?> state = const {'qty': '2'},
  Map<String, UiEditSpec> specs = const {'qty': UiStringEdit()},
  Map<String, UiCollection> collections = const {},
  Set<BindingRef> required = const {},
  Set<FactState> mandatory = const {},
  Set<String> actions = const {'edit', 'detail', 'back'},
  UiActionContext? actionContext,
}) {
  final snapshot = DataSnapshot(
    ref: _ref,
    facts: facts,
    initialUiState: state,
    editSpecs: specs,
    sources: {'s-old': _span('旧来源 88'), ...sources},
    sourceDigests: {_artifact.artifactId: _artifact.contentDigest},
    computations: {
      for (final e in oldValues.entries)
        e.key: ComputedValue(
          value: e.value,
          inputVersion: _ref,
          computationId: defs[e.key]!.computationId,
        ),
    },
    computedEvidence: {
      for (final id in oldValues.keys)
        id: UiComputedEvidence(
          state: FactState.verified,
          unit: 'STALE',
          sourceRefs: ['s-old'],
        ),
    },
    collections: collections,
    actionContext: actionContext,
  );
  final intent = InteractionIntent(
    id: 'lib2-provenance-intent',
    purpose: 'readonly recompute',
    snapshotRef: _ref,
    requiredBindings: required,
    mandatoryStates: mandatory,
    allowedActionRefs: actions,
  );
  final checked = validateUiPlan(
    UIPlan(
      surfaceId: 'lib2-provenance',
      revision: 6,
      catalogVersion: (catalog ?? library2UiCatalog).version,
      snapshotRef: _ref,
      intentRef: intent.id,
      root: 'root',
      nodes: [
        UiNode(
          id: 'root',
          component: 'PageScaffold',
          properties: {'title': '来源核对'},
          children: [for (final n in nodes) n.id],
        ),
        ...nodes,
      ],
    ),
    snapshot,
    intent,
    catalog ?? library2UiCatalog,
  );
  expect(checked.errors, isEmpty, reason: 'fixture must be host-accepted');
  return checked.validatedPlan!;
}

UiFormulaRegistry _registry(Map<String, UiFormulaDefinition> defs) =>
    UiFormulaRegistry(definitions: defs.values.toList(), limits: _limits);

final class _PausedPort implements UiRecomputePort {
  _PausedPort(this.release, this.delegate);
  final Completer<void>? release;
  final UiRecomputePort delegate;
  @override
  Future<UiRecomputeResult> rebuild(UiRecomputeInput input) async {
    if (release != null) await release!.future;
    return delegate.rebuild(input);
  }
}

ValidatedUiPlan _recoveryBase() {
  final defs = {'total': _product('cost:a', 'price')};
  return _base(
    facts: {
      'price': _fact('a', 'price', '7', FactState.verified, unit: 'CNY/件'),
    },
    defs: defs,
    oldValues: {'total': '88'},
    state: {'qty': '', 'sort': 'original', 'expanded': false},
    specs: {
      'qty': const UiStringEdit(),
      'sort': const UiStringEdit(view: true),
      'expanded': const UiBoolEdit(view: true),
    },
    actions: {'edit', 'submit', 'sort', 'detail', 'back'},
    actionContext: UiActionContext(
      draftRevision: 0,
      draft: {'qty': ''},
      operations: {
        'old': HostOperationRef(draftRevision: 0, inputRefs: {'qty'}),
      },
    ),
    nodes: [
      _metric('metric', 'total'),
      UiNode(
        id: 'toggle',
        component: 'Toggle',
        properties: {'label': 'Expanded'},
        bindings: {'value': const BindingRef.uiState('expanded')},
        events: {
          'change': ActionBinding(actionRef: 'edit', inputRefs: ['expanded']),
        },
      ),
      UiNode(
        id: 'qty',
        component: 'Field',
        properties: {'label': 'Quantity'},
        bindings: {
          'value': const BindingRef.fact('price'),
          'draft': const BindingRef.uiState('qty'),
        },
        events: {
          'change': ActionBinding(actionRef: 'edit', inputRefs: ['qty']),
        },
      ),
      UiNode(
        id: 'sort',
        component: 'SegmentedPill',
        bindings: {'selected': const BindingRef.uiState('sort')},
        events: {
          'change': ActionBinding(actionRef: 'sort', inputRefs: ['sort']),
        },
      ),
      UiNode(
        id: 'submit',
        component: 'Form',
        properties: {'title': 'Submit'},
        events: {
          'submit': ActionBinding(
            actionRef: 'submit',
            inputRefs: ['qty'],
            operationKeyRef: 'old',
            expectedDraftRevision: 0,
          ),
        },
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('managed DB writable positive control and exact zero writes in blocked states', () async {
    final dir = Directory.systemTemp.createTempSync('lib2-zero-db-');
    final storage = StorageManager(dir.path);
    final db = await storage.open('review', ModuleSchema(version:1, definitionDigest:'review-1', migrations:[
      ModuleMigration(version:1,id:'review-1',definitionDigest:'review-1',migrate:(raw) {
        raw.execute('CREATE TABLE records(id INTEGER PRIMARY KEY,value TEXT)');
        raw.execute("INSERT INTO records VALUES(1,'sentinel-968173')");
        raw.execute('CREATE TABLE operation_logs(id INTEGER PRIMARY KEY,value TEXT)');
        raw.execute('CREATE TABLE totals(id INTEGER PRIMARY KEY,value INTEGER)');
        raw.execute('INSERT INTO totals VALUES(1,619)');
      })]));
    addTearDown(() async {await storage.close(); dir.deleteSync(recursive:true);});
    String bytes() => jsonEncode([for(final table in ['records','operation_logs','totals'])
      db.raw.select('SELECT * FROM $table').map((r)=>Map<String,Object?>.from(r)).toList()]);
    var commits=0;
    db.onCommit=(){commits++;};
    Future<void> sink(UiEvent event) => db.write((raw) {
      raw.execute("UPDATE records SET value='admitted-968173' WHERE id=1");
      raw.execute("INSERT INTO operation_logs(value) VALUES('admitted-968173')");
      raw.execute('UPDATE totals SET value=value+37 WHERE id=1');
    });
    final defs={'total':_product('cost:a','price')};
    for(final mode in ['fresh','stale','pending','readonly','cancelled']) {
      var readonly=false;
      final release=Completer<void>();
      late UiSurfaceController c;
      c=UiSurfaceController(_recoveryBase(),onEvent:sink,readOnlyProbe:()=>readonly,
        recomputePort:_PausedPort(mode=='pending'||mode=='cancelled'?release:null,
          UiLiveFormulaRecomputePort(currentPlan:()=>c.current,registry:_registry(defs),computations:defs,parameterStateKeys:{'qty'})),
        publishTokenProbe:()=>_token(c.current.snapshot.ref,draftRevision:c.session.draftRevision));
      try {
        final submit=c.current.plan.nodes.singleWhere((n)=>n.id=='submit');
        expect(c.allowsInteraction(submit,'submit'),isTrue,reason:'fresh non-vacuous admission $mode');
        Future<UiPublishOutcome>? pending;
        if(mode=='stale') expect(await c.recompute(),UiPublishOutcome.invalid);
        if(mode=='pending'||mode=='cancelled') {
          pending=c.recompute(); expect(c.recomputing,isTrue);
          if(mode=='cancelled') c.cancelRecompute();
        }
        if(mode=='readonly') readonly=true;
        final before=bytes(), beforeCommits=commits;
        final result=await c.dispatchCaptured(c.captureRender(),submit,'submit');
        if(mode=='fresh') {
          expect(result,UiDispatchOutcome.routed);
          expect(bytes(),isNot(before)); expect(commits,beforeCommits+1);
          expect(db.raw.select('SELECT value FROM totals').single['value'],656);
          expect(db.raw.select('SELECT * FROM operation_logs').length,1);
        } else {
          expect(result,UiDispatchOutcome.stale,reason:mode);
          expect(bytes(),before,reason:mode); expect(commits,beforeCommits,reason:mode);
        }
        if(pending!=null) {
          release.complete();
          expect(await pending,mode=='cancelled'?UiPublishOutcome.staleToken:UiPublishOutcome.invalid);
          expect(bytes(),before); expect(commits,beforeCommits);
        }
      } finally {c.dispose();}
    }
  });
  test('readonly revoked inside final unchanged-token probe prevents publish',() async {
    var readonly=false, firstProbe=true;
    final defs={'total':_product('cost:a','price')};
    final base=_base(facts:{'price':_fact('a','price','7',FactState.verified,unit:'CNY/件')},
      defs:defs,oldValues:{'total':'88'},nodes:[_metric('metric','total')]);
    late UiSurfaceController c;
    c=UiSurfaceController(base,readOnlyProbe:()=>readonly,
      recomputePort:UiLiveFormulaRecomputePort(currentPlan:()=>c.current,registry:_registry(defs),computations:defs,parameterStateKeys:{'qty'}),
      publishTokenProbe:(){if(!firstProbe) readonly=true; firstProbe=false;
        return _token(c.current.snapshot.ref,draftRevision:c.session.draftRevision);});
    try {
      expect(await c.recompute(),UiPublishOutcome.invalid); expect(c.current,same(base));
      expect(c.outdated,isTrue); expect(c.session.resolve(const BindingRef.computed('total')),'88');
    } finally {c.dispose();}
  });
}
