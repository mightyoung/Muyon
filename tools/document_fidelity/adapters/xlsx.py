"""Independent stdlib oracle: conservative single-value XML delta, no engine."""
import copy
import hashlib
import io
import math
from pathlib import Path
import posixpath
import re
import tempfile
import xml.etree.ElementTree as ET
import zipfile

from ..harness import inspect, OFFICE, REL
from .protocol import LIMITS, cell_address, numeric, parse_request

S = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
XML = 'http://www.w3.org/XML/1998/namespace'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def inspect_bytes(data, format='xlsx'):
    if format not in ('xlsx','docx','pptx') or type(data) is not bytes or len(data) > LIMITS['max_input_bytes']:
        raise ValueError('input_limit_or_type')
    with tempfile.TemporaryDirectory(prefix='document-adapter-preflight-') as tmp:
        path = Path(tmp)/('snapshot.'+format)
        with path.open('xb') as output:
            output.write(data)
        path.chmod(0o400)
        return inspect(path)


def members(data):
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        return {name: archive.read(name) for name in archive.namelist() if not name.endswith('/')}


def tree(data):
    parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=True, insert_pis=True))
    root = ET.fromstring(data, parser=parser)
    # Preserve all comments/PIs, including those before/after the root.
    specials, depth, root_seen = [], 0, False
    for event, node in ET.iterparse(io.BytesIO(data), events=('start','end','comment','pi')):
        if event == 'start':
            depth += 1
            root_seen = True
        elif event == 'end':
            depth -= 1
        else:
            location = 'inside' if depth else ('epilog' if root_seen else 'prolog')
            specials.append((event, location, node.text))
    return root, specials


def signature(node):
    return (node.tag, tuple(sorted(node.attrib.items())), node.text, node.tail,
            tuple(signature(child) for child in node))


def target_value(root, address):
    cells = [c for c in root.findall(f'{{{S}}}sheetData/{{{S}}}row/{{{S}}}c') if c.get('r') == address]
    if len(cells) != 1:
        raise ValueError('missing_or_ambiguous_cell')
    cell = cells[0]
    values = cell.findall(f'{{{S}}}v')
    if (cell.get('t') not in (None, 'n') or cell.find(f'{{{S}}}f') is not None
            or len(values) != 1 or len(values[0]) or set(values[0].attrib)):
        raise ValueError('unsupported_non_numeric_or_formula_cell')
    numeric(values[0].text)
    return values[0]


def preview(source, raw):
    """Metadata preview only; unsupported flags never authorize execution."""
    result = dict(status='unsupported', reasons=[], sheet=None, cell=None,
                  hidden=dict(sheet='unknown', row='unknown', column='unknown'),
                  protected='unknown', merged='unknown', old_value=None, new_value=None)
    try:
        request = parse_request(raw)
        if request['operation']['kind'] != 'set_numeric_cell' or sha(source) != request['source_sha256']:
            raise ValueError('request_or_hash_mismatch')
        op = request['operation']
        result.update(sheet=op['sheet'], cell=op['cell'], new_value=op['replacement'])
        report = inspect_bytes(source)
        if report['decision'] != 'inspect_only' or report['format'] != 'xlsx':
            raise ValueError('source_preflight_rejected')
        parts = members(source)
        book, _ = tree(parts['xl/workbook.xml'])
        sheets = [n for n in book.findall(f'{{{S}}}sheets/{{{S}}}sheet') if n.get('name') == op['sheet']]
        if len(sheets) != 1: raise ValueError('ambiguous_sheet')
        state = sheets[0].get('state', 'visible')
        result['hidden']['sheet'] = False if state == 'visible' else (True if state in ('hidden','veryHidden') else 'unknown')
        rels, _ = tree(parts['xl/_rels/workbook.xml.rels'])
        links = [n for n in rels if n.get('Id') == sheets[0].get(f'{{{OFFICE}}}id') and n.get('Type') == OFFICE+'/worksheet']
        if len(links) != 1: raise ValueError('ambiguous_sheet_relation')
        part = posixpath.normpath(posixpath.join('xl',links[0].get('Target','')))
        root, _ = tree(parts[part])
        row_index, column_index = cell_address(op['cell'])
        rows = [n for n in root.findall(f'{{{S}}}sheetData/{{{S}}}row') if any(c.get('r') == op['cell'] for c in n.findall(f'{{{S}}}c'))]
        if len(rows) != 1 or rows[0].get('r') != str(row_index): raise ValueError('ambiguous_row')
        def flag(value):
            if value in (None,'0','false'): return False
            if value in ('1','true'): return True
            return 'unknown'
        def dimension(value):
            parsed = float(value)
            if not math.isfinite(parsed) or parsed < 0: raise ValueError('invalid_dimension')
            return parsed
        row_hidden = flag(rows[0].get('hidden'))
        fmt = root.find(f'{{{S}}}sheetFormatPr')
        if rows[0].get('ht') is not None and dimension(rows[0].get('ht')) <= 0: row_hidden = True
        if fmt is not None and flag(fmt.get('zeroHeight')) is not False: row_hidden = flag(fmt.get('zeroHeight'))
        if fmt is not None and fmt.get('defaultRowHeight') is not None and dimension(fmt.get('defaultRowHeight')) <= 0: row_hidden = True
        result['hidden']['row'] = row_hidden
        columns = []
        for col in root.findall(f'{{{S}}}cols/{{{S}}}col'):
            first,last = int(col.get('min','0')),int(col.get('max','0'))
            if not 1 <= first <= last <= 16384: raise ValueError('invalid_column_range')
            if first <= column_index <= last: columns.append(col)
        if len(columns) > 1: raise ValueError('ambiguous_columns')
        result['hidden']['column'] = flag(columns[0].get('hidden')) if columns else False
        if columns and columns[0].get('width') is not None and dimension(columns[0].get('width')) <= 0: result['hidden']['column'] = True
        if fmt is not None and fmt.get('defaultColWidth') is not None and dimension(fmt.get('defaultColWidth')) <= 0: result['hidden']['column'] = True
        result['protected'] = book.find(f'{{{S}}}workbookProtection') is not None or root.find(f'{{{S}}}sheetProtection') is not None
        result['merged'] = False
        for merged in root.findall(f'{{{S}}}mergeCells/{{{S}}}mergeCell'):
            ranges = merged.get('ref','').split(':')
            if len(ranges) != 2: raise ValueError('invalid_merge')
            a,b = (cell_address(x) for x in ranges)
            if a[0] > b[0] or a[1] > b[1]: raise ValueError('invalid_merge')
            if a[0] <= row_index <= b[0] and a[1] <= column_index <= b[1]: result['merged'] = True
        cells = [c for c in rows[0].findall(f'{{{S}}}c') if c.get('r') == op['cell']]
        if len(cells) != 1: raise ValueError('ambiguous_cell')
        value = cells[0].find(f'{{{S}}}v')
        result['old_value'] = value.text if value is not None else None
        numeric_target = target_value(root,op['cell'])
        if numeric(numeric_target.text) != numeric(op['expected']): raise ValueError('expected_value_conflict')
        if any(v is not False for v in result['hidden'].values()): result['reasons'].append('hidden_or_unknown_visibility')
        if result['protected']: result['reasons'].append('protected_target')
        if result['merged']: result['reasons'].append('merged_target')
        if not result['reasons']: result['status'] = 'supported'
    except (ValueError,KeyError,TypeError,ET.ParseError):
        result['reasons'].append('preview_unsupported')
    return result


def prepare(source, raw):
    request = parse_request(raw)
    target_preview = preview(source, raw)
    if target_preview['status'] != 'supported':
        raise ValueError('target_preview_unsupported')
    if sha(source) != request['source_sha256']:
        raise ValueError('source_hash_mismatch')
    report = inspect_bytes(source)
    if report['decision'] != 'inspect_only' or report['format'] != 'xlsx':
        raise ValueError('source_preflight_rejected')
    payloads = members(source)
    workbook, _ = tree(payloads['xl/workbook.xml'])
    if workbook.find(f'{{{S}}}workbookProtection') is not None:
        raise ValueError('protected_workbook_unsupported')
    op = request['operation']
    sheets = [sheet for sheet in workbook.findall(f'{{{S}}}sheets/{{{S}}}sheet') if sheet.get('name') == op['sheet']]
    if len(sheets) != 1 or sheets[0].get('state', 'visible') != 'visible':
        raise ValueError('hidden_or_ambiguous_sheet_unsupported')
    relations, _ = tree(payloads['xl/_rels/workbook.xml.rels'])
    links = [link for link in relations if link.get('Id') == sheets[0].get(f'{{{OFFICE}}}id')]
    if (len(links) != 1 or links[0].get('Type') != OFFICE + '/worksheet'
            or links[0].get('TargetMode', 'Internal') != 'Internal'):
        raise ValueError('unsupported_worksheet_relationship')
    target = posixpath.normpath(posixpath.join('xl', links[0].get('Target', '')))
    if target not in payloads or target.startswith('../'):
        raise ValueError('unsupported_worksheet_part')
    root, specials = tree(payloads[target])
    if root.tag != f'{{{S}}}worksheet' or root.find(f'{{{S}}}sheetProtection') is not None:
        raise ValueError('protected_or_unsupported_worksheet')
    # Namespace-valued attributes / markup-compatibility need a richer oracle.
    for node in root.iter():
        if isinstance(node.tag, str) and not node.tag.startswith(f'{{{S}}}'):
            raise ValueError('unknown_worksheet_namespace_unsupported')
        for key, value in node.attrib.items():
            if (key.startswith('{') and not key.startswith((f'{{{OFFICE}}}', f'{{{XML}}}'))) or (':' in value and not (key == 'ref' and re.fullmatch(r'[A-Z]{1,3}[1-9][0-9]*:[A-Z]{1,3}[1-9][0-9]*', value))):
                raise ValueError('namespace_attribute_unsupported')
    row, col = cell_address(op['cell'])
    for merged in root.findall(f'{{{S}}}mergeCells/{{{S}}}mergeCell'):
        endpoints = merged.get('ref', '').split(':')
        if len(endpoints) != 2:
            raise ValueError('unsupported_merge_range')
        start, end = (cell_address(x) for x in endpoints)
        if start[0] <= row <= end[0] and start[1] <= col <= end[1]:
            raise ValueError('merged_cell_unsupported')
    value = target_value(root, op['cell'])
    if numeric(value.text) != numeric(op['expected']):
        raise ValueError('expected_value_conflict')
    expected = copy.deepcopy(root)
    target_value(expected, op['cell']).text = op['replacement']
    return dict(request=request, source_report=report, target_part=target, source_parts=payloads, preview=target_preview,
                expected_signature=signature(expected), source_specials=specials)


def validate_candidate(plan, candidate):
    result = dict(status='fail', reasons=[], source_manifest=plan['source_report']['parts'],
                  candidate_sha256=sha(candidate), candidate_manifest=[])
    try:
        expected_format = plan.get('format','xlsx')
        report = inspect_bytes(candidate,expected_format)
        result['candidate_manifest'] = report['parts']
        if report['decision'] != 'inspect_only' or report['format'] != expected_format:
            result['reasons'].append('candidate_preflight_rejected')
            return result
        old, new = plan['source_parts'], members(candidate)
        if set(old) != set(new):
            result['reasons'].append('part_set_changed')
        for name in old.keys() & new.keys():
            if name != plan['target_part'] and old[name] != new[name]:
                result['reasons'].append('invariant_part_changed:' + name)
        if plan['target_part'] in new:
            root, specials = tree(new[plan['target_part']])
            if signature(root) != plan['expected_signature'] or specials != plan['source_specials']:
                result['reasons'].append('unauthorized_semantic_delta')
        if not result['reasons']:
            result['status'] = 'pass'
    except (ValueError, KeyError, ET.ParseError, zipfile.BadZipFile):
        result['reasons'].append('invalid_candidate')
    return result
