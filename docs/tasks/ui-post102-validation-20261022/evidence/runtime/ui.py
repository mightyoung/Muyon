from pathlib import Path
import sys,re,json,hashlib,xml.etree.ElementTree as E
sys.path.insert(0,'/workspace/ui-shell-tools/post102/smoke')
from device import root,shell,service
sha='c8044174a37fdc0e4d807307f81fc56a7cc74232'
def hierarchy(tag):
 result=shell('uiautomator dump /data/local/tmp/muyon-product-smoke.xml',tag+'-dump.txt',120)
 if 'dumped' not in result.lower():raise RuntimeError('UI dump not confirmed: '+result)
 raw=service('shell:cat /data/local/tmp/muyon-product-smoke.xml',30);(root/(tag+'.xml')).write_bytes(raw)
 tree=E.fromstring(raw.decode());nodes=list(tree.iter('node'))
 danger=[n for n in nodes if n.attrib.get('package') in ['com.android.packageinstaller','com.android.permissioncontroller'] or 'isn\'t responding' in n.attrib.get('text','') or '无响应' in n.attrib.get('text','')]
 if danger:raise RuntimeError('Permission/ANR dialog present; do not auto-accept')
 return nodes

def capture(tag):
 nodes=hierarchy(tag)
 png=service('exec:screencap -p',60);assert png.startswith(b'\x89PNG\r\n\x1a\n')
 name=sha+'-PRODUCT-RUNTIME-PR102-PLUS-UI-CANDIDATE-api26-1080x1920-font1.0-'+tag+'.png';p=root/name;p.write_bytes(png)
 summary=[{'text':n.attrib.get('text'),'description':n.attrib.get('content-desc'),'package':n.attrib.get('package'),'bounds':n.attrib.get('bounds'),'enabled':n.attrib.get('enabled')} for n in nodes if n.attrib.get('text') or n.attrib.get('content-desc')]
 (root/(tag+'-summary.json')).write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'tag':tag,'file':str(p),'sha256':hashlib.sha256(png).hexdigest(),'labels':summary},ensure_ascii=False),flush=True);return nodes

def tap(nodes,**attrs):
 matches=[n for n in nodes if all(n.attrib.get(k)==v for k,v in attrs.items())];assert len(matches)==1,[(n.attrib) for n in matches]
 n=matches[0];assert n.attrib.get('enabled')=='true';x1,y1,x2,y2=map(int,re.findall(r'\d+',n.attrib['bounds']));print(shell('input tap '+str((x1+x2)//2)+' '+str((y1+y2)//2)),flush=True)
if __name__=='__main__':capture(sys.argv[1])
