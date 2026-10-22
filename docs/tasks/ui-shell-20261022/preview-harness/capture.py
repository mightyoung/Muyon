import sys,xml.etree.ElementTree as E,re,json,hashlib,struct
from pathlib import Path
sys.path.insert(0,'/workspace/ui-shell-tools');from owned_emulator_adb import LocalEmulator
root=Path('/workspace/muyon-ui-shell/docs/tasks/ui-shell-20261022/preview-screens-043bed');root.mkdir(exist_ok=True)
source='043bed97e218bc25202a803aff3c0de1a5da031f'
log=Path('/workspace/ui-shell-tools/ui-component-preview/capture-actions.jsonl')
def service(command):
 s=LocalEmulator();s.s.settimeout(120)
 try:r=s.read_service(command)
 finally:s.close()
 return r
def shell(command):
 r=service('shell:'+command).decode(errors='replace')
 with log.open('a') as f:f.write(json.dumps({'command':command,'output':r},ensure_ascii=False)+'\n')
 return r
def window():
 shell('uiautomator dump /data/local/tmp/muyon-preview.xml')
 raw=service('shell:cat /data/local/tmp/muyon-preview.xml')
 nodes=list(E.fromstring(raw).iter('node'))
 labels=[n.attrib.get('text','') for n in nodes]
 if any("isn't responding" in x for x in labels):raise RuntimeError('ANR overlay: capture refused')
 return nodes,raw
rows=[]
for page,night,menu in [('chat','no',True),('cards','no',False),('bot','no',False),('group','no',False),('chat','yes',False),('chat','yes',True),('bot','yes',False)]:
 print('START',page,night,menu,flush=True)
 shell('cmd uimode night '+night)
 shell('am force-stop com.mightyoung.muyon.uicomponentpreview')
 result=shell('am start -W -n com.mightyoung.muyon.uicomponentpreview/com.mightyoung.muyon.preview.PreviewActivity --es page '+page)
 if 'Status: ok' not in result:raise RuntimeError(result)
 nodes,xml=window()
 if menu:
  buttons=[n for n in nodes if n.attrib.get('content-desc')=='打开工作空间导航']
  if len(buttons)!=1:raise RuntimeError('exact visible menu button unavailable')
  x1,y1,x2,y2=map(int,re.findall(r'\d+',buttons[0].attrib['bounds']))
  shell('input tap '+str((x1+x2)//2)+' '+str((y1+y2)//2));nodes,xml=window()
 labels=[n.attrib.get('text','') for n in nodes]
 expected='主 Agent 与置顶' if menu else {'chat':'Muyon 主 Agent','cards':'原请求只读快照','bot':'配置 Bot','group':'群组协作方式'}[page]
 if not any(expected in x for x in labels):raise RuntimeError('expected surface absent '+expected)
 raw=service('exec:screencap -p')
 assert raw.startswith(b'\x89PNG\r\n\x1a\n')
 surface='menu' if menu else page;theme='dark' if night=='yes' else 'light'
 name=f'{source}-component-preview-{surface}-{theme}-api26-font1-synthetic.png';p=root/name;p.write_bytes(raw)
 (root/(name+'.xml')).write_bytes(xml)
 rows.append({'file_name':name,'path':str(p),'sha256':hashlib.sha256(raw).hexdigest(),'pixels':list(struct.unpack('>II',raw[16:24])),'source_sha':source,'capture_kind':'actual Android runtime COMPOSE COMPONENT PREVIEW, not full product APK','synthetic_data':True,'surface':surface,'theme':theme,'device':'task-owned software AOSP emulator','api':26,'abi':'x86_64','density_dpi':420,'font_scale':1.0,'state':'no ANR in pre-capture visible hierarchy; manually inspect PNG too'})
 print('CAPTURED',name,len(raw),flush=True)
 (root/'CAPTURES.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n')
