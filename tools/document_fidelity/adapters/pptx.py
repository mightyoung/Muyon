"""One slide/ordinary rectangular text shape/paragraph/run only; no theme/master."""
import posixpath
import re
from . import xlsx,text_common as common
from ..harness import OFFICE
P='http://schemas.openxmlformats.org/presentationml/2006/main'
A='http://schemas.openxmlformats.org/drawingml/2006/main'


def prepare(source,raw):
    plan=common.source_plan(source,raw,'pptx');parts=plan['source_parts'];op=plan['request']['operation']
    if op['paragraph_index'] != 0 or op['run_index'] != 0:raise ValueError('single_text_run_only')
    presentation,_=xlsx.tree(parts['ppt/presentation.xml'])
    if presentation.tag != f'{{{P}}}presentation' or presentation.attrib or [n.tag for n in common.elements(presentation)] != [f'{{{P}}}sldIdLst',f'{{{P}}}sldSz',f'{{{P}}}notesSz']:
        raise ValueError('complex_presentation_unsupported')
    if any(n.attrib for n in presentation.findall(f'{{{P}}}sldIdLst')):raise ValueError('complex_slide_list')
    slides=presentation.findall(f'{{{P}}}sldIdLst/{{{P}}}sldId')
    if len(common.elements(presentation.find(f'{{{P}}}sldIdLst'))) != 1 or any(len(n) or set(n.attrib) != {'id',f'{{{OFFICE}}}id'} for n in slides):raise ValueError('complex_slide_identity')
    if len(slides)!=1 or slides[0].get('id') != str(op['slide_id']):raise ValueError('slide_identity_or_complex_deck')
    rels,_=xlsx.tree(parts['ppt/_rels/presentation.xml.rels'])
    if len(common.elements(rels))!=1:raise ValueError('auxiliary_slide_relationships_unsupported')
    links=[n for n in rels if n.get('Id') == slides[0].get(f'{{{OFFICE}}}id')]
    if len(links)!=1 or links[0].get('Type') != OFFICE+'/slide' or links[0].get('TargetMode','Internal') != 'Internal':raise ValueError('wrong_slide_relation')
    part=posixpath.normpath(posixpath.join('ppt',links[0].get('Target','')))
    if part!=op['part'] or part not in parts:raise ValueError('slide_part_conflict')
    allowed={'ppt/presentation.xml','ppt/_rels/presentation.xml.rels',part}
    if any(n.startswith('ppt/') and n not in allowed for n in parts):raise ValueError('master_theme_notes_or_auxiliary_unsupported')
    root,specials=xlsx.tree(parts[part])
    pnames=('sld','cSld','spTree','nvGrpSpPr','cNvPr','cNvGrpSpPr','nvPr','grpSpPr','sp','nvSpPr','cNvSpPr','spPr','txBody','clrMapOvr')
    anames=('xfrm','off','ext','prstGeom','avLst','bodyPr','lstStyle','p','r','rPr','t','masterClrMapping')
    tags={f'{{{P}}}{n}' for n in pnames}|{f'{{{A}}}{n}' for n in anames}
    attrs={f'{{{P}}}cNvPr':{'id','name','hidden'},f'{{{A}}}off':{'x','y'},f'{{{A}}}ext':{'cx','cy'},f'{{{A}}}prstGeom':{'prst'},f'{{{A}}}rPr':{'lang','b','i','sz'}}
    common.screen(root,tags,attrs)
    if root.tag != f'{{{P}}}sld':raise ValueError('unsupported_slide')
    # A complete direct-child grammar for this tiny synthetic subset. Same-tag
    # nodes in the wrong container must not become apparent plain text shapes.
    grammar={
        f'{{{P}}}sld':[f'{{{P}}}cSld',f'{{{P}}}clrMapOvr'],
        f'{{{P}}}cSld':[f'{{{P}}}spTree'],
        f'{{{P}}}spTree':[f'{{{P}}}nvGrpSpPr',f'{{{P}}}grpSpPr',f'{{{P}}}sp'],
        f'{{{P}}}nvGrpSpPr':[f'{{{P}}}cNvPr',f'{{{P}}}cNvGrpSpPr',f'{{{P}}}nvPr'],
        f'{{{P}}}sp':[f'{{{P}}}nvSpPr',f'{{{P}}}spPr',f'{{{P}}}txBody'],
        f'{{{P}}}nvSpPr':[f'{{{P}}}cNvPr',f'{{{P}}}cNvSpPr',f'{{{P}}}nvPr'],
        f'{{{P}}}spPr':[f'{{{A}}}xfrm',f'{{{A}}}prstGeom'],
        f'{{{A}}}xfrm':[f'{{{A}}}off',f'{{{A}}}ext'],
        f'{{{A}}}prstGeom':[f'{{{A}}}avLst'],
        f'{{{P}}}txBody':[f'{{{A}}}bodyPr',f'{{{A}}}lstStyle',f'{{{A}}}p'],
        f'{{{A}}}p':[f'{{{A}}}r'],
        f'{{{P}}}clrMapOvr':[f'{{{A}}}masterClrMapping']}
    for node in root.iter():
        if not isinstance(node.tag,str):continue
        if node.tag == f'{{{A}}}r':
            if [n.tag for n in common.elements(node)] not in ([f'{{{A}}}t'],[f'{{{A}}}rPr',f'{{{A}}}t']):raise ValueError('complex_run')
        elif [n.tag for n in common.elements(node)] != grammar.get(node.tag,[]):raise ValueError('complex_shape_structure')
    for node in root.findall(f'.//{{{A}}}rPr'):
        if any(node.get(k,'0') not in ('0','1','false','true') for k in ('b','i')):raise ValueError('invalid_font_flags')
        if node.get('sz') is not None and not 100<=int(node.get('sz'))<=9600:raise ValueError('font_size_unsupported')
        if node.get('lang') is not None and not re.fullmatch(r'[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*',node.get('lang')):raise ValueError('font_language_unsupported')

    all_ids=root.findall(f'.//{{{P}}}cNvPr');ids=[n.get('id') for n in all_ids]
    if any(not i or not re.fullmatch(r'[1-9][0-9]{0,9}',i) for i in ids):raise ValueError('invalid_shape_id')
    if len(ids)!=len(set(ids)) or any(n.get('hidden','0') not in ('0','false') for n in all_ids):raise ValueError('duplicate_or_hidden_shape')
    shapes=root.findall(f'{{{P}}}cSld/{{{P}}}spTree/{{{P}}}sp')
    if len(shapes)!=1 or shapes[0].find(f'{{{P}}}nvSpPr/{{{P}}}cNvPr').get('id') != str(op['shape_id']):raise ValueError('shape_identity_or_complex_slide')
    shape=shapes[0]
    if [n.tag for n in common.elements(shape)] != [f'{{{P}}}nvSpPr',f'{{{P}}}spPr',f'{{{P}}}txBody']:raise ValueError('complex_shape')
    props=shape.find(f'{{{P}}}spPr')
    if [n.tag for n in common.elements(props)] != [f'{{{A}}}xfrm',f'{{{A}}}prstGeom'] or props.find(f'{{{A}}}prstGeom').get('prst')!='rect':raise ValueError('complex_geometry')
    transform=props.find(f'{{{A}}}xfrm')
    if [n.tag for n in common.elements(transform)] != [f'{{{A}}}off',f'{{{A}}}ext']:raise ValueError('complex_transform')
    off,ext=common.elements(transform);size=presentation.find(f'{{{P}}}sldSz')
    x,y,cx,cy=(int(off.get('x','-1')),int(off.get('y','-1')),int(ext.get('cx','0')),int(ext.get('cy','0')))
    if min(x,y)<0 or min(cx,cy)<=0 or x+cx>int(size.get('cx','0')) or y+cy>int(size.get('cy','0')):raise ValueError('out_of_slide_bounds')
    body=shape.find(f'{{{P}}}txBody')
    if [n.tag for n in common.elements(body)] != [f'{{{A}}}bodyPr',f'{{{A}}}lstStyle',f'{{{A}}}p'] or len(body.find(f'{{{A}}}bodyPr')) or len(body.find(f'{{{A}}}lstStyle')):raise ValueError('complex_text_body')
    para=body.find(f'{{{A}}}p')
    if [n.tag for n in common.elements(para)] != [f'{{{A}}}r']:raise ValueError('multi_paragraph_or_run_unsupported')
    run=para.find(f'{{{A}}}r');children=common.elements(run)
    if [n.tag for n in children] not in ([f'{{{A}}}t'],[f'{{{A}}}rPr',f'{{{A}}}t']):raise ValueError('complex_run')
    if any(len(n) for n in run.findall(f'{{{A}}}rPr')):raise ValueError('complex_run_style')
    target=run.find(f'{{{A}}}t')
    def selected(newroot):return newroot.find(f'{{{P}}}cSld/{{{P}}}spTree/{{{P}}}sp/{{{P}}}txBody/{{{A}}}p/{{{A}}}r/{{{A}}}t')
    return common.finish(plan,part,root,specials,target,run,f'slideId={op["slide_id"]}/shapeId={op["shape_id"]}/p[0]/r[0]/t',selected)


def preview(source,raw):return common.preview(prepare,source,raw)
