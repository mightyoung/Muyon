"""Original complex DOCX/XLSX fixtures and a non-executable single-edit plan."""
import json
from pathlib import Path

from .generate_fixtures import package, relationships
from .harness import OFFICE, SPECS, inspect


def build_complex_samples():
    w, x = SPECS['docx'][2], SPECS['xlsx'][2]
    docx = package('docx', f'''<body xmlns:w="{w}"><p><bookmarkStart w:id="1" w:name="SyntheticTarget"/><r><t xml:space="preserve">Original </t></r><commentRangeStart w:id="0"/><r><rPr><b/></rPr><t>target</t></r><commentRangeEnd w:id="0"/><r><t xml:space="preserve"> unchanged</t></r><r><commentReference w:id="0"/></r><bookmarkEnd w:id="1"/></p><sectPr><headerReference w:type="default" r:id="rId3"/><pgSz w:w="11906" w:h="16838"/><pgMar w:top="1440" w:bottom="1440" w:left="1440" w:right="1440"/></sectPr></body>''',
        [('word/comments.xml', f'<comments xmlns="{w}" xmlns:w="{w}"><comment w:id="0" w:author="Muyon"><p><r><t>Original synthetic comment</t></r></p></comment></comments>', 'application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml'),
         ('word/header1.xml', f'<hdr xmlns="{w}"><p><r><t>Original header</t></r></p></hdr>', 'application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml')],
        {'word/_rels/document.xml.rels': relationships([('rId2', 'comments', 'comments.xml'), ('rId3', 'header', 'header1.xml')])})
    xlsx = package('xlsx', '<workbookPr date1904="1"/><sheets><sheet name="Original" sheetId="1" r:id="rId1"/><sheet name="Hidden" sheetId="2" state="hidden" r:id="rId2"/></sheets><definedNames><definedName name="SyntheticInput">Original!$A$1</definedName></definedNames><calcPr calcId="0" fullCalcOnLoad="1" forceFullCalc="1"/>',
        [('xl/worksheets/sheet1.xml', f'''<worksheet xmlns="{x}" xmlns:r="{OFFICE}"><dimension ref="A1:C4"/><sheetData><row r="1"><c r="A1"><v>2</v></c><c r="B1"><f>A1+1</f><v>999</v></c><c r="C1"><v>0.123456789012345</v></c></row><row r="2"><c r="A2" s="1"><v>44500</v></c></row><row r="3"><c r="A3" t="inlineStr"><is><t>Original merged title</t></is></c></row><row r="4"><c r="A4" t="inlineStr"><is><t>Original comment anchor</t></is></c></row></sheetData><mergeCells count="1"><mergeCell ref="A3:B3"/></mergeCells><legacyDrawing r:id="rId2"/></worksheet>''', 'application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml'),
         ('xl/worksheets/sheet2.xml', f'<worksheet xmlns="{x}"><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>Original hidden value</t></is></c></row></sheetData></worksheet>', 'application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml'),
         ('xl/styles.xml', f'<styleSheet xmlns="{x}"><fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="14" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>', 'application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml'),
         ('xl/comments/comment1.xml', f'<comments xmlns="{x}"><authors><author>Muyon</author></authors><commentList><comment ref="A4" authorId="0"><text><t>Original synthetic comment</t></text></comment></commentList></comments>', 'application/vnd.openxmlformats-officedocument.spreadsheetml.comments+xml'),
         ('xl/drawings/comments.vml', '<xml xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:x="urn:schemas-microsoft-com:office:excel"><v:shapetype id="_x0000_t202" coordsize="21600,21600" o:spt="202" path="m,l,21600r21600,l21600,xe"><v:stroke joinstyle="miter"/><v:path gradientshapeok="t" o:connecttype="rect"/></v:shapetype><v:shape id="_x0000_s1025" type="#_x0000_t202" style="position:absolute;width:108pt;height:59pt;visibility:hidden" fillcolor="#ffffe1" o:insetmode="auto"><v:textbox><div/></v:textbox><x:ClientData ObjectType="Note"><x:MoveWithCells/><x:SizeWithCells/><x:Anchor>0, 15, 3, 2, 2, 31, 6, 1</x:Anchor><x:AutoFill>False</x:AutoFill><x:Row>3</x:Row><x:Column>0</x:Column></x:ClientData></v:shape></xml>', 'application/vnd.openxmlformats-officedocument.vmlDrawing')],
        {'xl/_rels/workbook.xml.rels': relationships([('rId1', 'worksheet', 'worksheets/sheet1.xml'), ('rId2', 'worksheet', 'worksheets/sheet2.xml'), ('rId3', 'styles', 'styles.xml')]),
         'xl/worksheets/_rels/sheet1.xml.rels': relationships([('rId1', 'comments', '../comments/comment1.xml'), ('rId2', 'vmlDrawing', '../drawings/comments.vml')])})
    return {'complex.docx': docx, 'complex.xlsx': xlsx}


def operation_contract(name, report):
    if name not in ('complex.docx', 'complex.xlsx'):
        raise ValueError('only original complex synthetic specimens allowed')
    is_docx = name.endswith('.docx')
    target = 'word/document.xml' if is_docx else 'xl/worksheets/sheet1.xml'
    return dict(schema_version=1, source_sha256=report['sha256'], original_name=name,
                execution_allowed=False, reason='Isolation probe failed; licensing/origin gates incomplete',
                round_trip='not_run', independent_reopen='not_run', semantic_comparison='not_run',
                render='not_run', recalc='not_run', visual='not_run', annotation='not_run',
                allowed_changed_parts=[target],
                byte_invariant_parts=sorted(x['name'] for x in report['parts'] if x['name'] != target),
                operation=dict(kind='replace_single_run_text' if is_docx else 'set_single_cell_value',
                               target='bookmark SyntheticTarget / bold run text' if is_docx else 'Original!A1',
                               expected='target' if is_docx else '2', replacement='edited' if is_docx else '5'),
                semantic_invariants=(['Exactly one w:t changes target -> edited; all attributes/rPr, adjacent runs, bookmarks, comment references, header and all other nodes unchanged'] if is_docx else
                                     ['Exactly A1/v changes 2 -> 5; all other nodes/attributes unchanged', 'B1 formula A1+1 and deliberately stale authored cache999 remain unchanged; recalculation NOT_RUN']),
                forbidden=['source overwrite', 'network', 'macros', 'external refresh', 'embedded payload execution',
                           'unreviewed engine', 'unknown-part loss or rewrite', 'unapproved changed part or semantic node'])


def main():
    destination = Path(__file__).parent / 'fixtures_complex'
    destination.mkdir(exist_ok=False)
    manifest = {}
    for name, payload in build_complex_samples().items():
        path = destination / name
        with path.open('xb') as output:
            output.write(payload)
        report = inspect(path)
        manifest[name] = dict(source=report, operation_contract=operation_contract(name, report))
    (destination / 'manifest.json').write_text(json.dumps(manifest, sort_keys=True, indent=2) + '\n')


if __name__ == '__main__':
    main()
