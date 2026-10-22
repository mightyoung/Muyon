"""Original tiny simple-layout specimens; no application-open/render claim."""
import json
from pathlib import Path
from .generate_fixtures import package,relationships
from .harness import OFFICE,SPECS,inspect


def build_samples():
    w,p=SPECS['docx'][2],SPECS['pptx'][2]
    a='http://schemas.openxmlformats.org/drawingml/2006/main'
    word=package('docx', '<body><p><r><t xml:space="preserve">Original </t></r><r><rPr><b/></rPr><t>target</t></r><r><t xml:space="preserve"> unchanged</t></r></p><sectPr/></body>',[],{})
    slide=f'<p:sld xmlns:p="{p}" xmlns:a="{a}"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/><p:sp><p:nvSpPr><p:cNvPr id="2" name="Original title"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="100" y="100"/><a:ext cx="1000000" cy="500000"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr><p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang="en-US" b="1"/><a:t>target</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>'
    ppt=package('pptx','<sldIdLst><sldId id="256" r:id="rId1"/></sldIdLst><sldSz cx="9144000" cy="6858000"/><notesSz cx="6858000" cy="9144000"/>', [('ppt/slides/slide1.xml',slide,'application/vnd.openxmlformats-officedocument.presentationml.slide+xml')], {'ppt/_rels/presentation.xml.rels':relationships([('rId1','slide','slides/slide1.xml')])})
    return {'simple-run.docx':word,'simple-shape.pptx':ppt}


def main():
    dest=Path(__file__).parent/'fixtures_subsets';dest.mkdir(exist_ok=False)
    manifest={}
    for name,data in build_samples().items():
        path=dest/name
        with path.open('xb') as stream:stream.write(data)
        manifest[name]=inspect(path)
    (dest/'manifest.json').write_text(json.dumps(manifest,sort_keys=True,indent=2)+'\n')

if __name__=='__main__':main()
