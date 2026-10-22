"""Single direct body paragraph/run/text only; complex Word features rejected."""
from . import xlsx,text_common as common
W='http://schemas.openxmlformats.org/wordprocessingml/2006/main'
XML='http://www.w3.org/XML/1998/namespace'


def prepare(source,raw):
    plan=common.source_plan(source,raw,'docx');parts=plan['source_parts'];op=plan['request']['operation']
    if any(n.startswith('word/') and n != 'word/document.xml' for n in parts):
        raise ValueError('word_auxiliary_features_unsupported')
    root,specials=xlsx.tree(parts['word/document.xml'])
    tags={f'{{{W}}}{n}' for n in ('document','body','p','r','rPr','t','b','i','sectPr')}
    attrs={f'{{{W}}}t':{f'{{{XML}}}space'},f'{{{W}}}b':{f'{{{W}}}val'},f'{{{W}}}i':{f'{{{W}}}val'}}
    common.screen(root,tags,attrs)
    if root.tag != f'{{{W}}}document' or [n.tag for n in common.elements(root)] != [f'{{{W}}}body']:
        raise ValueError('unsupported_document_structure')
    body=common.elements(root)[0];children=common.elements(body)
    if not children or any(n.tag not in (f'{{{W}}}p',f'{{{W}}}sectPr') for n in children):raise ValueError('unsupported_body')
    sections=[n for n in children if n.tag == f'{{{W}}}sectPr']
    if len(sections)>1 or (sections and (sections[0] is not children[-1] or len(sections[0]))):raise ValueError('complex_sections_unsupported')
    paragraphs=body.findall(f'{{{W}}}p')
    for p in paragraphs:
        if not common.elements(p) or any(n.tag != f'{{{W}}}r' for n in common.elements(p)):raise ValueError('complex_paragraph_unsupported')
        for run in p.findall(f'{{{W}}}r'):
            children=common.elements(run)
            if [n.tag for n in children] not in ([f'{{{W}}}t'],[f'{{{W}}}rPr',f'{{{W}}}t']):raise ValueError('complex_run_unsupported')
            for child in run.findall(f'{{{W}}}rPr'):
                if any(n.tag not in (f'{{{W}}}b',f'{{{W}}}i') or len(n) or n.get(f'{{{W}}}val','1') not in ('1','0','true','false') for n in common.elements(child)):
                    raise ValueError('complex_run_style_unsupported')
    pi,ri=op['paragraph_index'],op['run_index']
    try:run=paragraphs[pi].findall(f'{{{W}}}r')[ri]
    except IndexError as exc:raise ValueError('missing_run') from exc
    target=run.find(f'{{{W}}}t')
    def selected(newroot):return newroot.findall(f'{{{W}}}body/{{{W}}}p')[pi].findall(f'{{{W}}}r')[ri].find(f'{{{W}}}t')
    return common.finish(plan,'word/document.xml',root,specials,target,run,
                         f'document/body/p[{pi}]/r[{ri}]/t',selected)


def preview(source,raw):return common.preview(prepare,source,raw)
