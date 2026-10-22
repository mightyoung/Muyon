"""Original tiny structural fixtures. No external templates, fonts or user data."""
import io
import json
from pathlib import Path
import zipfile

from .harness import CT, REL, OFFICE, SPECS, inspect


def relationships(entries):
    return (f'<Relationships xmlns="{REL}">' + ''.join(
        f'<Relationship Id="{ident}" Type="{OFFICE}/{typ}" Target="{target}"/>'
        for ident, typ, target in entries) + '</Relationships>').encode()


def package(kind, body, extra, links):
    main, mime, ns, root = SPECS[kind]
    members = {'_rels/.rels': relationships([('rId1', 'officeDocument', main)]),
               main: f'<{root} xmlns="{ns}" xmlns:r="{OFFICE}">{body}</{root}>'.encode(),
               'custom/original.bin': b'Muyon synthetic opaque extension\x00'}
    overrides = [(main, mime)]
    for name, payload, content_type in extra:
        members[name] = payload.encode()
        overrides.append((name, content_type))
    members.update(links)
    members['[Content_Types].xml'] = (f'<Types xmlns="{CT}">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Default Extension="bin" ContentType="application/octet-stream"/>' + ''.join(
            f'<Override PartName="/{name}" ContentType="{ctype}"/>' for name, ctype in overrides) + '</Types>').encode()
    output = io.BytesIO()
    with zipfile.ZipFile(output, 'w') as archive:
        for name in sorted(members):
            entry = zipfile.ZipInfo(name, (2026, 10, 22, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.external_attr = 0o100644 << 16
            archive.writestr(entry, members[name])
    return output.getvalue()


def pdf_sample():
    objects = [b'<< /Type /Catalog /Pages 2 0 R >>',
               b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
               b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
               b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>']
    stream = b'BT /F1 12 Tf 20 150 Td (Muyon original fixture) Tj ET\n'
    objects.append(b'<< /Length ' + str(len(stream)).encode() + b' >>\nstream\n' + stream + b'endstream')
    data = b'%PDF-1.4\n%\xe2\xe3\xcf\xd3\n'
    offsets = [0]
    for index, obj in enumerate(objects, 1):
        offsets.append(len(data))
        data += f'{index} 0 obj\n'.encode() + obj + b'\nendobj\n'
    xref = len(data)
    data += b'xref\n0 6\n0000000000 65535 f \n'
    data += b''.join(f'{offset:010d} 00000 n \n'.encode() for offset in offsets[1:])
    data += f'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode()
    return data


def build_samples():
    w = SPECS['docx'][2]
    x = SPECS['xlsx'][2]
    p = SPECS['pptx'][2]
    a = 'http://schemas.openxmlformats.org/drawingml/2006/main'
    return {
        'minimal.docx': package('docx', '<body><p><r><t>Muyon original fixture</t></r></p><p><r><commentReference w:id="0" xmlns:w="' + w + '"/></r></p><sectPr/></body>',
            [('word/comments.xml', f'<comments xmlns="{w}"><comment xmlns:w="{w}" w:id="0" w:author="Muyon"><p><r><t>Original synthetic comment</t></r></p></comment></comments>', 'application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml')],
            {'word/_rels/document.xml.rels': relationships([('rId2', 'comments', 'comments.xml')])}),
        'minimal.xlsx': package('xlsx', '<sheets><sheet name="Original" sheetId="1" r:id="rId1"/></sheets><calcPr calcId="0" fullCalcOnLoad="1"/>',
            [('xl/worksheets/sheet1.xml', f'<worksheet xmlns="{x}"><sheetData><row r="1"><c r="A1"><v>2</v></c><c r="B1"><f>A1+1</f><v>3</v></c></row></sheetData></worksheet>', 'application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml')],
            {'xl/_rels/workbook.xml.rels': relationships([('rId1', 'worksheet', 'worksheets/sheet1.xml')])}),
        'minimal.pptx': package('pptx', '<sldIdLst><sldId id="256" r:id="rId1"/></sldIdLst><sldSz cx="9144000" cy="6858000"/><notesSz cx="6858000" cy="9144000"/>',
            [('ppt/slides/slide1.xml', f'<p:sld xmlns:p="{p}" xmlns:a="{a}"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/><p:sp><p:nvSpPr><p:cNvPr id="2" name="Original title"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>Muyon original fixture</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>', 'application/vnd.openxmlformats-officedocument.presentationml.slide+xml')],
            {'ppt/_rels/presentation.xml.rels': relationships([('rId1', 'slide', 'slides/slide1.xml')])}),
        'minimal.pdf': pdf_sample(),
    }


def main():
    # Exclusive writes protect existing originals. Regenerate into a new directory
    # via build_samples() when testing; this command creates the committed corpus once.
    dest = Path(__file__).parent / 'fixtures'
    dest.mkdir(exist_ok=False)
    reports = {}
    for name, data in build_samples().items():
        path = dest / name
        with path.open('xb') as output:
            output.write(data)
        reports[name] = inspect(path)
    (dest / 'manifest.json').write_text(json.dumps(reports, sort_keys=True, indent=2) + '\n')


if __name__ == '__main__':
    main()
