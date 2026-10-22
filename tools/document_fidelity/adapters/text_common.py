"""Shared conservative text preparation, fingerprints and exact XML oracle."""
import copy
import hashlib
import json
import xml.etree.ElementTree as ET
from . import xlsx
from .protocol import parse_request


def elements(node):
    return [n for n in node if isinstance(n.tag,str)]


def local_fingerprint(node):
    def form(n):
        tag = n.tag if isinstance(n.tag,str) else ('#comment' if n.tag is ET.Comment else '#pi')
        return [tag, sorted(n.attrib.items()), n.text, n.tail, [form(c) for c in n]]
    data=json.dumps(form(node),ensure_ascii=True,separators=(',',':')).encode()
    return hashlib.sha256(data).hexdigest()


def source_plan(source,raw,format):
    request=parse_request(raw)
    kind={'docx':'replace_docx_run_text','pptx':'replace_pptx_shape_text'}[format]
    if request['operation']['kind'] != kind or xlsx.sha(source) != request['source_sha256']:
        raise ValueError('request_or_source_conflict')
    report=xlsx.inspect_bytes(source,format)
    if report['decision'] != 'inspect_only' or report['format'] != format:
        raise ValueError('source_preflight_rejected')
    return dict(request=request,source_report=report,source_parts=xlsx.members(source),format=format)


def screen(root,allowed_tags,allowed_attributes):
    for node in root.iter():
        if not isinstance(node.tag,str):continue
        if node.tag not in allowed_tags or any(k not in allowed_attributes.get(node.tag,set()) for k in node.attrib):
            raise ValueError('complex_or_unknown_layout_unsupported')


def finish(plan,part,root,specials,target,run,path,run_in_copy):
    op=plan['request']['operation']
    if len(target) or target.text != op['expected'] or local_fingerprint(run) != op['target_sha256']:
        raise ValueError('target_precondition_conflict')
    if op['replacement'].strip() != op['replacement'] and target.get('{http://www.w3.org/XML/1998/namespace}space') != 'preserve':
        raise ValueError('xml_space_change_unsupported')
    expected=copy.deepcopy(root)
    run_in_copy(expected).text=op['replacement']
    plan.update(target_part=part,expected_signature=xlsx.signature(expected),source_specials=specials,
                preview=dict(status='supported',format=plan['format'],part=part,structure_path=path,
                             local_sha256=local_fingerprint(run),old_value=target.text,new_value=op['replacement'],
                             layout='narrow_synthetic_subset',render='not_run'))
    return plan


def preview(prepare,source,raw):
    try:return prepare(source,raw)['preview']
    except (ValueError,KeyError,TypeError,IndexError,ET.ParseError) as exc:
        return dict(status='unsupported',reasons=[str(exc) if isinstance(exc,ValueError) else 'invalid_source_or_locator'])
