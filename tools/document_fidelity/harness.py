"""Bounded, offline, read-only package checks. No editing or safety certification."""
import argparse
import hashlib
import io
import os
import json
import posixpath
import re
import stat
import struct
from pathlib import Path
from urllib.parse import unquote, urlsplit
import xml.etree.ElementTree as ET
from xml.parsers import expat
import zipfile
import zlib

LIMITS = dict(max_file=16 * 1024 * 1024, max_members=2048,
              max_member=8 * 1024 * 1024, max_total=32 * 1024 * 1024,
              max_ratio=100, max_xml_depth=128)
CT = 'http://schemas.openxmlformats.org/package/2006/content-types'
REL = 'http://schemas.openxmlformats.org/package/2006/relationships'
OFFICE = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
SPECS = {
    'docx': ('word/document.xml', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml', 'http://schemas.openxmlformats.org/wordprocessingml/2006/main', 'document'),
    'xlsx': ('xl/workbook.xml', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml', 'http://schemas.openxmlformats.org/spreadsheetml/2006/main', 'workbook'),
    'pptx': ('ppt/presentation.xml', 'application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml', 'http://schemas.openxmlformats.org/presentationml/2006/main', 'presentation'),
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def finding(report, code, part='', detail=''):
    report['findings'].append(dict(code=code, part=part, detail=detail))
    report['decision'] = 'reject'


def unsafe_path(name):
    decoded = unquote(name)
    return (not name or decoded.startswith('/') or '\\' in decoded
            or ':' in decoded or '%' in decoded or '\x00' in decoded
            or any(x in ('', '.', '..') for x in decoded.rstrip('/').split('/')))


def xml_root(data, max_depth):
    # Expat rejects declarations *before* entity expansion; handles UTF-16 too.
    parser = expat.ParserCreate()
    depth = 0

    def forbidden(*_):
        raise ValueError('DTD/entities unsupported')

    def start(*_):
        nonlocal depth
        depth += 1
        if depth > max_depth:
            raise ValueError('XML depth limit')

    def end(*_):
        nonlocal depth
        depth -= 1

    parser.StartDoctypeDeclHandler = forbidden
    parser.EntityDeclHandler = forbidden
    parser.ExternalEntityRefHandler = forbidden
    parser.StartElementHandler = start
    parser.EndElementHandler = end
    parser.Parse(data, True)
    return ET.fromstring(data)


def inspect(path, limits=None):
    """Inspect a bounded immutable byte snapshot. Emits no extracted/output file."""
    cap = LIMITS.copy()
    if limits:
        if any(k not in cap or not isinstance(v, int) or v < 1 or v > cap[k]
               for k, v in limits.items()):
            raise ValueError('limits may only tighten positive defaults')
        cap.update(limits)
    report = dict(schema_version=1, format='unknown', sha256=None, size=None,
                  decision='quarantine', safety='unknown', fidelity='unknown',
                  parts=[], findings=[], limits=cap,
                  dimensions={key: dict(status='not_run', reason='No engine installed or invoked')
                              for key in ('structure', 'visual', 'formula', 'annotation', 'render', 'recalc')})
    try:
        with Path(path).open('rb') as stream:
            if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
                raise ValueError('regular file required')
            data = stream.read(cap['max_file'] + 1)
        report['size'] = len(data)
        if len(data) > cap['max_file']:
            finding(report, 'file_limit', detail='hash not computed: snapshot exceeds cap')
            return report
        report['sha256'] = digest(data)
        suffix = Path(path).suffix.lower().lstrip('.')
        if data.startswith(b'%PDF-'):
            report['format'] = 'pdf'
            if suffix != 'pdf':
                finding(report, 'extension_mismatch')
            if not re.match(rb'%PDF-[12]\.\d[\r\n]', data) or not data.rstrip().endswith(b'%%EOF'):
                finding(report, 'pdf_incomplete')
            # Decode name escapes for conservative marker scan only; streams,
            # object references and PDF grammar remain entirely unparsed.
            scan = re.sub(rb'#([0-9A-Fa-f]{2})', lambda m: bytes([int(m[1], 16)]), data)
            markers = re.findall(rb'/(?:JavaScript|JS|Launch|OpenAction|AA|Encrypt|EmbeddedFile|Filespec|URI|XFA|RichMedia|Sig)\b', scan)
            if markers:
                finding(report, 'pdf_risk_marker', detail=', '.join(sorted({x.decode('ascii') for x in markers})))
            report['limitations'] = ['Incomplete byte-marker scan; absence proves no safety',
                                     'PDF parser, signature verification and rendering NOT_RUN']
        elif data.startswith(b'PK'):
            inspect_zip(data, suffix, report, cap)
        elif data.startswith(bytes.fromhex('d0cf11e0a1b11ae1')):
            finding(report, 'encrypted_or_legacy_container', detail='CFB encrypted OOXML/legacy formats unsupported')
        else:
            finding(report, 'unsupported_container')
    except (OSError, ValueError) as exc:
        finding(report, 'input_error', detail=type(exc).__name__)
    if report['decision'] == 'reject' and report['format'] != 'pdf':
        report['dimensions']['structure'] = dict(status='fail', reason='Package preflight rejected')
    return report


def inspect_zip(data, suffix, report, cap):
    # Reject ZIP64/multidisk; cap central directory entries before ZipFile allocates.
    end = data.rfind(b'PK\x05\x06', max(0, len(data) - 65557))
    if end < 0 or end + 22 > len(data):
        finding(report, 'invalid_zip')
        return
    disk, cd_disk, disk_n, count, cd_size, cd_offset, comment = struct.unpack_from('<4H2IH', data, end + 4)
    if (disk or cd_disk or disk_n != count or count == 65535 or cd_size == 0xffffffff
            or cd_offset == 0xffffffff or end + 22 + comment != len(data)):
        finding(report, 'invalid_zip', detail='unsupported ZIP64/multidisk/trailing bytes')
        return
    if count > cap['max_members']:
        finding(report, 'archive_limits')
        return
    if cd_offset + cd_size != end:
        finding(report, 'invalid_zip')
        return
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            infos = archive.infolist()
            if len(infos) != count or sum(x.file_size for x in infos) > cap['max_total']:
                finding(report, 'archive_limits')
            names = set()
            for info in infos:
                name = info.orig_filename
                if unsafe_path(name):
                    finding(report, 'unsafe_path', name)
                if name in names:
                    finding(report, 'duplicate_part', name)
                names.add(name)
                if stat.S_ISLNK(info.external_attr >> 16):
                    finding(report, 'symlink', name)
                offset = info.header_offset
                if offset < 0 or offset + 30 > cd_offset or data[offset:offset + 4] != b'PK\x03\x04':
                    finding(report, 'invalid_zip', name, 'Invalid local header')
                else:
                    local_flags, local_method = struct.unpack_from('<HH', data, offset + 6)
                    if local_flags & (1 | 64):
                        finding(report, 'encrypted', name, 'Local header encryption flag')
                    if local_flags != info.flag_bits or local_method != info.compress_type:
                        finding(report, 'invalid_zip', name, 'Local/central flags or method disagree')
                if info.flag_bits & (1 | 64):
                    finding(report, 'encrypted', name)
                if info.file_size > cap['max_member'] or info.file_size > max(1, info.compress_size) * cap['max_ratio']:
                    finding(report, 'archive_limits', name)
                if info.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
                    finding(report, 'unsupported_compression', name)
            if report['decision'] == 'reject':
                report['parts'] = [dict(name=x.orig_filename, size=x.file_size, sha256=None) for x in infos]
                return
            payloads = {}
            for info in infos:
                if info.is_dir():
                    continue
                with archive.open(info) as stream:
                    payload = stream.read(cap['max_member'] + 1)
                if len(payload) != info.file_size or len(payload) > cap['max_member']:
                    finding(report, 'archive_limits', info.filename)
                    return
                payloads[info.filename] = payload
                report['parts'].append(dict(name=info.filename, size=len(payload), sha256=digest(payload)))
            inspect_parts(payloads, suffix, report, cap)
    except (zipfile.BadZipFile, NotImplementedError, RuntimeError, OSError, ValueError, EOFError, zlib.error) as exc:
        finding(report, 'invalid_zip', detail=type(exc).__name__)


def inspect_parts(parts, suffix, report, cap):
    roots = {}
    for name, payload in parts.items():
        lower = name.lower()
        if 'vba' in lower or '/macrosheets/' in lower:
            finding(report, 'macro', name)
        if '/embeddings/' in lower or lower.endswith('.ole'):
            finding(report, 'embedded_object', name)
        if lower.endswith(('.xml', '.rels')):
            try:
                roots[name] = xml_root(payload, cap['max_xml_depth'])
            except (expat.ExpatError, ET.ParseError, ValueError):
                finding(report, 'unsafe_or_invalid_xml', name)
    if '[Content_Types].xml' not in roots or '_rels/.rels' not in roots:
        finding(report, 'missing_package_metadata')
        return
    ct = roots['[Content_Types].xml']
    if ct.tag != f'{{{CT}}}Types':
        finding(report, 'invalid_content_types')
        return
    overrides, defaults = {}, {}
    for node in ct:
        if not re.fullmatch(r"[A-Za-z0-9!#$&^_.+-]+/[A-Za-z0-9!#$&^_.+-]+", node.get('ContentType', '')):
            finding(report, 'invalid_content_types', detail='Missing or malformed MIME type')
        if node.tag == f'{{{CT}}}Override':
            raw = node.get('PartName', '')
            name = raw[1:] if raw.startswith('/') else ''
            if unsafe_path(name) or name in overrides or name not in parts:
                finding(report, 'invalid_content_types', name)
            overrides[name] = node.get('ContentType', '')
        elif node.tag == f'{{{CT}}}Default':
            ext = node.get('Extension', '').lower()
            if not ext or ext in defaults:
                finding(report, 'invalid_content_types')
            defaults[ext] = node.get('ContentType', '')
        else:
            finding(report, 'invalid_content_types')
    for name in parts:
        mime = overrides.get(name, defaults.get(name.rsplit('.', 1)[-1].lower()))
        if name != '[Content_Types].xml' and not mime:
            finding(report, 'missing_content_type', name)
        if name.endswith('.rels') and mime != 'application/vnd.openxmlformats-package.relationships+xml':
            finding(report, 'invalid_relationship_content_type', name)
        lowered = (mime or '').lower()
        if 'macroenabled' in lowered or 'vbaproject' in lowered:
            finding(report, 'macro', name)
        if 'oleobject' in lowered:
            finding(report, 'embedded_object', name)
        if mime and ('xml' in lowered) and name not in roots:
            try:
                roots[name] = xml_root(parts[name], cap['max_xml_depth'])
            except (expat.ExpatError, ET.ParseError, ValueError):
                finding(report, 'unsafe_or_invalid_xml', name)
    detected = [kind for kind, spec in SPECS.items() if overrides.get(spec[0]) == spec[1]]
    if len(detected) != 1:
        finding(report, 'unsupported_main_type', detail='Expected one supported non-macro OOXML main type')
        return
    kind = detected[0]
    report['format'] = kind
    main, _, ns, tag = SPECS[kind]
    if main not in parts:
        finding(report, 'missing_main', main)
    if suffix != kind:
        finding(report, 'extension_mismatch')
    if main in roots and roots[main].tag != f'{{{ns}}}{tag}':
        finding(report, 'main_root_mismatch', main)
    main_links = []
    for name, root in list(roots.items()):
        if name.endswith('.rels'):
            if root.tag != f'{{{REL}}}Relationships':
                finding(report, 'invalid_relationships', name)
                continue
            ids = set()
            for node in root:
                target, typ, mode = node.get('Target', ''), node.get('Type', ''), node.get('TargetMode', 'Internal')
                if (node.tag != f'{{{REL}}}Relationship' or not node.get('Id') or node.get('Id') in ids
                        or not re.match(r'^[A-Za-z][A-Za-z0-9+.-]*:', typ)):
                    finding(report, 'invalid_relationships', name)
                ids.add(node.get('Id'))
                if mode == 'External' or urlsplit(target).scheme or target.startswith('//'):
                    finding(report, 'external_relationship', name)
                    continue
                if mode != 'Internal' or not target or '\\' in target or '%' in target:
                    finding(report, 'invalid_relationship_target', name)
                    continue
                base = '' if name == '_rels/.rels' else posixpath.dirname(posixpath.dirname(name))
                resolved = posixpath.normpath(posixpath.join(base, target.lstrip('/')))
                resolved = resolved.split('#', 1)[0]
                if unsafe_path(resolved) or resolved not in parts:
                    finding(report, 'invalid_relationship_target', name)
                if name == '_rels/.rels' and typ == OFFICE + '/officeDocument':
                    main_links.append(resolved)
                if 'vbaproject' in typ.lower():
                    finding(report, 'macro', name)
                if any(x in typ.lower() for x in ('oleobject', '/package')):
                    finding(report, 'embedded_object', name)
        for node in root.iter():
            text = ''.join(node.itertext()) if node.tag.rsplit('}', 1)[-1] in ('f', 'instrText', 'fldSimple') else ''
            text += node.get(f'{{{SPECS["docx"][2]}}}instr', '')
            if re.search(r'(DDE|WEBSERVICE|HYPERLINK|RTD\s*\(|\[[^\]]+\])', text, re.I):
                finding(report, 'active_field_or_formula', name)
    if main_links != [main]:
        finding(report, 'main_relationship_mismatch')
    if report['decision'] != 'reject':
        report['decision'] = 'inspect_only'
        report['dimensions']['structure'] = dict(status='pass', reason='Bounded container/XML/main-part/relationship checks only; no OOXML schema or semantic validation')
    report['limitations'] = ['No complete OOXML schema validation or malware detection',
                             'Unknown parts inventoried; no editing/rendering/semantic preservation proven']


def compare(original, candidate):
    """Conservative all-part byte preservation; never declares edit fidelity."""
    a, b = inspect(original), inspect(candidate)
    result = dict(schema_version=1, original=a, candidate=b, fidelity='unknown',
                  dimensions={k: dict(v) for k, v in b['dimensions'].items()})
    old = {x['name']: x['sha256'] for x in a['parts']}
    new = {x['name']: x['sha256'] for x in b['parts']}
    missing = sorted(old.keys() - new.keys())
    changed = sorted(k for k in old.keys() & new.keys() if old[k] != new[k])
    added = sorted(new.keys() - old.keys())
    status = 'unknown'
    if a['decision'] == 'reject' or b['decision'] == 'reject' or missing or changed:
        status = 'fail'
    elif old and not added:
        status = 'pass'
    result['preservation'] = dict(status=status, missing=missing, changed=changed, added=added,
                                  reason='Exact part bytes only; any intentional edit needs future semantic validator')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('original', type=Path)
    parser.add_argument('--candidate', type=Path)
    args = parser.parse_args()
    result = compare(args.original, args.candidate) if args.candidate else inspect(args.original)
    print(json.dumps(result, ensure_ascii=True, sort_keys=True, indent=2))
    if args.candidate:
        return 2 if result['preservation']['status'] == 'fail' else 0
    return 2 if result['decision'] == 'reject' else 0


if __name__ == '__main__':
    raise SystemExit(main())
