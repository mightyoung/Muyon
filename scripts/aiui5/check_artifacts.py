#!/usr/bin/env python3
"""F5a source inventory only; never validates or enables a UI capability."""
import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/fixtures/aiui5/component-mapping.json'
CAT = 'packages/muyon_ui/lib/src/dynamic/catalog.dart'
VAL = 'packages/muyon_module_api/lib/src/ui/validation.dart'
STATE = 'packages/muyon_module_api/lib/src/ui/state.dart'
SURFACE = 'packages/muyon_ui/lib/src/dynamic/surface.dart'
RESTORE = 'packages/muyon_ui/lib/src/dynamic/workspace.dart'
CODEC = 'packages/muyon_module_api/lib/src/ui/workspace.dart'
ROUTER = 'apps/muyon/lib/assistant/ui_planning_events.dart'
TEST = 'packages/muyon_ui/test/aiui5_f5a_contract_fixture_test.dart'
BOUNDARY = 'packages/muyon_ui/test/library_contract_boundary_test.dart'

# Per-component adapter decisions. These are proposed, never runtime registration.
DETAILS = {
 'PageScaffold': ('navigation_layout', 'PageScaffold', 'title; ordered children -> Column', 'node IDs; scroll/focus'),
 'MasterDetail': ('navigation_layout', 'MasterDetail', 'first child master; remaining children detail Column', 'stable child IDs'),
 'Field': ('surface', 'TextFormField', 'fact value/state/unit; draft String -> controller.text', 'String override; fact immutable'),
 'Table': ('data', 'MuyonTable', 'host columns/cells -> rows; current renderer only scalar value/alternate', 'collection IDs/version; sort view only'),
 'SourceList': ('surface', 'SelectableText', 'sourceSpan -> excerpt; expandedSources by node ID', 'source digest recheck'),
 'ObjectChip': ('primitives', 'ObjectChip', 'label; host fact.object -> trusted detail', 'current detailNode; ObjectRef recheck'),
 'StatusBadge': ('primitives', 'StatusBadge', 'fact state -> tone; value -> label', 'mandatory FactState'),
 'ScopeChip': ('primitives', 'ScopeChip', 'label/value; host scope -> status', 'scope invalidation readOnly'),
 'WarnBanner': ('confirmation', 'WarnBanner', 'fact value/state; explain -> semantic', 'taint/mandatory state; no grant'),
 'SegmentedPill': ('primitives', 'SegmentedPill', 'selected original/value -> position; change String -> sort', 'viewValues; no draft increment'),
 'ConfirmCard': ('confirmation', 'ConfirmCard', 'host actionContext -> ConfirmItem; real receipt -> status', 'operation refs; no persisted approval'),
 'BatchConfirmCard': ('confirmation', 'BatchConfirmCard', 'current single ConfirmItem list; host batch mapping future', 'operation refs; unknown locked'),
 'Heading': ('layout', 'Heading', 'text; level 1..3 future validator range', 'stable node; readonly text'),
 'Prose': ('layout', 'Prose', 'text -> paragraphs', 'stable node; model text identified'),
 'Section': ('layout', 'Section', 'title; ordered children', 'stable child IDs'),
 'Columns': ('layout', 'Columns', 'ordered children; responsive width from host/theme', 'stable child IDs'),
 'Tabs': ('layout', 'MuyonTabs', 'host labels <-> child IDs; current schema lacks labels/controlled selection', 'selectedChildId view; current position local only'),
 'Disclosure': ('layout', 'Disclosure', 'title; many children -> one Column child', 'expanded view; current bool local only'),
 'KeyValue': ('data', 'KeyValue', 'host key/value collection -> items', 'column/item IDs/version'),
 'Metric': ('data', 'Metric', 'value/unit/label; computed delta -> numeric display', 'inputVersion and source provenance'),
 'CompareTable': ('data', 'CompareTable', 'host columns/rows/marks; add stable row callback after adoption', 'row ID -> current ObjectRef; no index identity'),
 'Chart': ('data', 'Chart', 'bar/line/pie; host numeric points; same points -> text data table', 'item IDs/source/inputVersion'),
 'Choice': ('inputs', 'Choice', 'host options IDs/labels; selected IDs -> Set view; custom disabled', 'sorted ID array; membership revision; host parameterEdit override vs viewSelection view role preserved'),
 'Form': ('inputs', 'MuyonForm', 'title/submitLabel; children; readonly subtree gate', 'business operation/receipt; no replay'),
 'NumberStepper': ('inputs', 'NumberStepper', 'finite double value/min/max/step; no truncation', 'typed number override/spec version'),
 'Slider': ('inputs', 'MuyonSlider', 'finite double value/min/max; host step -> divisions policy', 'typed number override/spec version'),
 'Toggle': ('inputs', 'Toggle', 'bool value/change; current edit_input blocker', 'bool override; never stringify'),
 'DateField': ('inputs', 'DateField', 'ISO date -> DateTime year/month/day; host first/last', 'date string/spec; nullable explicit'),
 'SourceCard': ('business', 'SourceCard', 'title; sourceSpan -> excerpt/location/onOpen', 'digest/version recheck'),
 'FileCard': ('business', 'FileCard', 'host file/ObjectRef -> name,sizeText,onOpen; no model path', 'reference availability recheck'),
 'ProgressCard': ('business', 'ProgressCard', 'host value -> finite progress/step/tone', 'host task version/receipt'),
 'Checklist': ('business', 'Checklist', 'host items -> ChecklistItem; index,bool -> frozen stable ID adapter', 'checked typed projection; fact readonly'),
 'Timeline': ('business', 'Timeline', 'host versioned events -> TimelineEvent time/title/detail', 'event IDs/version; readonly'),
}

def read(path):
    return (ROOT / path).read_text()

def cite(path, needle):
    s = read(path)
    assert needle in s, (path, needle)
    return {'path': path, 'line': s[:s.index(needle)].count('\n') + 1, 'symbol': needle}

def balanced(s, start, opening, closing):
    # Restricted audited Dart catalog syntax; fails loudly if inventory changes.
    depth = 0
    for i in range(start, len(s)):
        if s[i] == opening:
            depth += 1
        elif s[i] == closing:
            depth -= 1
            if depth == 0:
                return s[start:i + 1], i + 1
    raise AssertionError('unbalanced catalog')

def schema(raw):
    result = {'allowsChildren': 'allowsChildren: true' in raw}
    for key in ['properties', 'requiredProperties', 'bindings', 'requiredBindings', 'events', 'eventActions']:
        m = re.search(r'\b' + key + r':\s*\{', raw)
        block = balanced(raw, m.end() - 1, '{', '}')[0] if m else '{}'
        if key.startswith('required'):
            result[key] = re.findall(r"'([^']+)'", block)
        elif key in ('properties', 'events'):
            result[key] = dict(re.findall(r"'([^']+)'\s*:\s*(UiValueType\.\w+|null)", block))
        else:
            result[key] = {k: re.findall(r"BindingKind\.(\w+)|'([^']+)'", v)
                           for k, v in re.findall(r"'([^']+)'\s*:\s*\{([^}]*)\}", block)}
            result[key] = {k: [a or b for a, b in v] for k, v in result[key].items()}
    return result

def build():
    s = read(CAT)
    entries = {}
    # Source order implements minimal -> dynamic -> library overrides.
    for match in re.finditer(r"(?:'(?P<name>[^']+)'|(?P<loop>component)):\s*UiComponentSchema\(", s):
        raw, _ = balanced(s, match.end() - 1, '(', ')')
        names = [match['name']] if match['name'] else re.findall(r"'([^']+)'", s[s.rfind('for (final component', 0, match.start()):match.start()])
        for name in names:
            entries[name] = {'catalog': {'path': CAT, 'line': s[:match.start()].count('\n') + 1}, 'schema': schema(raw)}
    assert set(entries) == set(DETAILS) and len(entries) == 33
    routes = {}
    for m in re.finditer(r"'([^']+)':\s*(?:const )?UiActionDefinition\(", s):
        raw, _ = balanced(s, m.end() - 1, '(', ')')
        route = re.search(r'route: UiActionRoute\.(\w+)', raw)[1]
        local = re.search(r'localAction: UiLocalAction\.(\w+)', raw)
        routes[m[1]] = {'route': route, 'localAction': local[1] if local else None,
                        'consumer': cite(STATE, 'UiEventOutcome dispatch(') if route == 'local' else cite(ROUTER, 'Future<void> dispatch(')}
    surface = read(SURFACE)
    rendered = set(re.findall(r"case '([^']+)':", surface))
    assert len(rendered) == 12
    for name, entry in entries.items():
        group, widget, params, restore = DETAILS[name]
        if group == 'surface':
            widget_ref = cite(SURFACE, widget + '(')
        else:
            path = ('packages/muyon_ui/lib/src/ui_components/' if group in {'layout', 'data', 'inputs', 'business'} else 'packages/muyon_ui/lib/src/') + group + '.dart'
            widget_ref = cite(path, 'class ' + widget + ' ')
        entry.update({
            'catalogVersion': 'library-1',
            'bindingShape': 'current scalar/sourceSpan only; draft collection kind resolves collections exclusively; fact/computed/uiState retain original namespaces',
            'collectionBindingDraft': 'collection -> snapshot.collections; stream/2 adoption required; reject ID collision with any scalar namespace; cellStateRefs -> host cellStates' if name in {'Table', 'KeyValue', 'CompareTable', 'Chart', 'Choice', 'Checklist', 'Timeline'} else None,
            'validator': cite(VAL, 'List<String> validateUiNode('),
            'renderer': cite(SURFACE, "case '" + name + "':") if name in rendered else cite(SURFACE, 'default:'),
            'renderCaseInventory': 'existing case (minimal/dynamic only)' if name in rendered else 'no case; default unavailable text if render reached',
            'currentRendering': 'library-1 whole-surface snapshotFallback; catalog identity gate blocks render()',
            'surfaceCatalogGate': cite(SURFACE, 'if (!identical(controller.current.catalog, dynamicUiCatalog)'),
            'proposedWidget': widget_ref, 'proposedParameters': params,
            'currentPayload': entry['schema']['events'],
            'proposedPayloadDraft': {
                'Toggle': 'bool; declared bool state only',
                'NumberStepper': 'finite JSON number; exact host range/step',
                'Slider': 'finite JSON number; preserve fraction; host range/step',
                'DateField': 'YYYY-MM-DD or explicitly nullable null; DateTime adapter',
                'Choice': 'canonical stable item ID array; host parameterEdit increments draftRevision/recomputes dependencies, viewSelection preserves draftRevision/no recompute',
                'Checklist': 'stable itemId + bool; declared checked state; facts readonly',
                'CompareTable': 'collectionId + collectionRevision + itemId; host ObjectRef resolution',
                'Tabs': 'declared selectedChildId view; labels/children same host IDs',
                'Disclosure': 'declared expanded bool view',
            }.get(name, 'preserve current declared payload; no new business authority'),
            'actions': entry['schema']['eventActions'],
            'actionRoutes': {action: routes[action] for actions in entry['schema']['eventActions'].values() for action in actions},
            'state': cite(STATE, 'UiEventOutcome dispatch('),
            'router': cite(ROUTER, 'Future<void> dispatch('),
            'restore': cite(RESTORE, 'static Future<UiWorkspaceController> open('),
            'codec': cite(CODEC, 'Map<String, Object?> encodeUiPresentation('),
            'restorePolicyDraft': restore,
            'textAndStates': 'reuse resolved host values; proposed library ready/loading/error/readOnlyDegraded gate; current adapter is not four-state certification',
            'fixture': TEST if name in {'Field', 'Toggle', 'CompareTable', 'Metric'} else BOUNDARY if name in {'Table', 'Checklist', 'Timeline', 'Chart'} else 'future bound-plan fixture required',
            'futureAcceptance': 'every_catalog_component_renders_from_validated_bound_plan:' + name,
        })
    sources = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in sorted({CAT, VAL, STATE, SURFACE, RESTORE, CODEC, ROUTER} | {e['proposedWidget']['path'] for e in entries.values()})}
    return {'status': 'draft inventory, not capability acceptance', 'baseSha': '0466f113fd7dd41f99c38cef11eca428622a6fac', 'count': 33, 'currentRendererCases': 12, 'componentsWithoutRenderCase': 21, 'librarySurfaceFallbacks': 33, 'sourceSha256': sources, 'components': entries}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    result = json.dumps(build(), ensure_ascii=False, indent=2) + '\n'
    if args.write:
        OUT.write_text(result)
    assert OUT.read_text() == result, 'manifest drift; review source then regenerate'
    vectors = json.loads(read('docs/fixtures/aiui5/draft-vectors.json'))
    assert vectors['status'] == 'draft; future-only; no production codec'
    ids = [v['id'] for v in vectors['cases']]
    assert len(ids) == len(set(ids))
    for group in ['typed', 'collection', 'detail', 'projection', 'restore']:
        cases = [v for v in vectors['cases'] if v['group'] == group]
        assert {'accept', 'reject'} <= {v['decisionDraft'] for v in cases}, group
    for v in vectors['cases']:
        assert v['expectedAcceptance'] == 'future-only' and v['reason']
    lines = [json.loads(line) for line in read('docs/fixtures/aiui5/string-projection.library-1.jsonl').splitlines()]
    assert lines[-1] == {'op': 'end'} and len(lines) == 6
    assert lines[1]['id'] == 'root'
    assert not any({'route', 'snapshotRef', 'intentRef', 'catalogVersion', 'revision', 'surfaceId'} & line.keys() for line in lines)
    collection_fixture = json.loads(read('docs/fixtures/aiui5/collection-binding.draft.json'))
    assert collection_fixture['status'] == 'draft; future-only; no production codec'
    assert collection_fixture['bindingResolutionDraft'] == {'fact': 'facts', 'computed': 'computations', 'uiState': 'initialUiState', 'collection': 'collections'}
    assert collection_fixture['protocolDraft'] == 'aiui-stream/2-not-adopted'
    assert collection_fixture['modelLines'][1]['bind']['rows'] == {'kind': 'collection', 'id': 'quote-comparison'}
    assert len(collection_fixture['negativeCases']) == 10
    assert all(c['expectedAcceptance'] == 'future-only' for c in collection_fixture['negativeCases'])
    # Check concrete fixture pointers/value agreement only. This is not a codec
    # implementation and does not evaluate negative mutations or accept plans.
    host = collection_fixture['hostSnapshotDraft']
    entry = host['collections']['quote-comparison']
    for row in entry['rows']:
        for column, value in row['cells'].items():
            state = entry['cellStates'][entry['cellStateRefs'][row['itemId']][column]]
            fact = host['facts'][state['valueRef']['id']]
            assert state['valueRef']['kind'] == 'fact' and fact['value'] == value
            assert fact['state'] == state['state'] and fact['sourceRefs'] == state['sourceRefs']
    missing = entry['cellStates']['state-b-price']
    assert missing['state'] == 'notDisclosed' and missing['missingReason'] == 'not_disclosed'
    assert entry['rows'][1]['cells']['price'] is None
    print(f'F5a artifact checks: PASS; 33 catalog schemas, 12 renderer cases, 21 components without render case; library-1 whole-surface fallback; {len(ids)} future-only vectors. No runtime/codec validation.')

if __name__ == '__main__':
    main()
