import json,pathlib,hashlib,argparse
parser=argparse.ArgumentParser()
parser.add_argument("--base-url",required=True)
parser.add_argument("--executable-path",required=True)
parser.add_argument("--output",default="/tmp/muyon-ui-browser-evidence")
args=parser.parse_args()
from urllib.parse import urlparse
if urlparse(args.base_url).scheme not in ("http","https"): parser.error("Authorized HTTP(S) preview required")
from playwright.sync_api import sync_playwright,expect
out=pathlib.Path(args.output);out.mkdir(exist_ok=True)
results=[]
browser_version=None
def enable(page):
 page.get_by_role('button',name='Enable accessibility').dispatch_event('click')
def saved(page):
 return page.evaluate('Object.fromEntries(Object.keys(localStorage).filter(k=>k.startsWith("muyon-public-workspace:")).map(k=>[k,JSON.parse(localStorage[k])]))')
with sync_playwright() as p:
 b=p.chromium.launch(executable_path=args.executable_path,headless=True)
 browser_version=b.version
 for width,height in [(390,844),(1440,900)]:
  print('start viewport',width,flush=True);ctx=b.new_context(viewport={'width':width,'height':height});page=ctx.new_page();errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
  page.goto(args.base_url.rstrip('/')+'/?workspace=1',wait_until='networkidle');enable(page)
  field=page.get_by_role('textbox',name='Fact quantity');field.click();field.press('Meta+A');field.press_sequentially('14');field.press('Tab')
  for target,title in [('Open public object','Public object'),('Open public source','Public source')]:
   page.get_by_role('button',name=target,exact=True).click();page.get_by_text(title,exact=True).wait_for();page.get_by_role('button',name='Back',exact=True).click();field.click();expect(field).to_have_value('14')
  page.mouse.move(width//2,min(height-100,650));page.mouse.wheel(0,320)
  page.wait_for_function('Object.keys(localStorage).some(k=>k.startsWith("muyon-public-workspace:")&&JSON.parse(localStorage[k]).scrollOffset>0)') if width==390 else None
  before_scroll=page.get_by_role('button',name='Quote B',exact=True).bounding_box()['y']
  page.get_by_role('button',name='Save checkpoint',exact=True).click();page.reload(wait_until='networkidle');enable(page)
  if width==390:
   marker=page.get_by_role('button',name='Quote B',exact=True)
   marker.wait_for()
   for _ in range(20):
    if abs(marker.bounding_box()['y']-before_scroll)<2: break
    page.wait_for_timeout(100)
   assert abs(marker.bounding_box()['y']-before_scroll)<2, 'Scroll position was not restored after reload'
  field.click();expect(field).to_have_value('14')
  page.screenshot(path=str(out/f'workspace-{width}.png'))
  workspace={k:v for k,v in saved(page).items() if v['surfaceId']=='comparison'};print('workspace pass',width,flush=True)
  page.goto(args.base_url.rstrip('/')+'/?subconversation=1',wait_until='networkidle');enable(page)
  page.get_by_role('button',name='打开子对话',exact=True).click();draft=page.get_by_role('textbox',name='待发输入');draft.click();page.wait_for_timeout(250);draft.press_sequentially('pending draft',delay=100);draft.press('Tab')
  page.get_by_role('button',name='保存并关闭',exact=True).click();page.get_by_role('button',name='打开子对话',exact=True).click();draft.click();expect(draft).to_have_value('pending draft');page.get_by_role('button',name='保存并关闭',exact=True).click()
  page.get_by_role('button',name='查询最新',exact=True).click();expect(page.get_by_text('只读历史引用：子成果 v1',exact=False)).to_have_count(1)
  page.get_by_role('button',name='打开子对话',exact=True).click();page.get_by_role('button',name='模拟子成果更新',exact=True).click();expect(page.get_by_text('子成果 v2',exact=True)).to_have_count(1);page.get_by_role('button',name='保存并关闭',exact=True).click()
  expect(page.get_by_text('只读历史引用：子成果 v2',exact=False)).to_have_count(0)
  page.get_by_role('button',name='查询最新',exact=True).click();expect(page.get_by_text('只读历史引用：子成果 v1',exact=False)).to_have_count(1);expect(page.get_by_text('只读历史引用：子成果 v2',exact=False)).to_have_count(1)
  page.reload(wait_until='networkidle');enable(page);expect(page.get_by_text('只读历史引用：子成果 v2',exact=False)).to_have_count(1);page.get_by_role('button',name='打开子对话',exact=True).click();draft.click();expect(draft).to_have_value('pending draft');expect(page.get_by_text('模拟任务运行中；关闭仅保存 UI',exact=True)).to_have_count(1)
  page.screenshot(path=str(out/f'child-{width}.png'));page.get_by_role('button',name='保存并关闭',exact=True).click()
  if errors: raise AssertionError('Uncaught page errors: '+repr(errors))
  results.append({'viewport':[width,height],'workspace':workspace,'child':{k:v for k,v in saved(page).items() if v['surfaceId']=='public-ui4c-child'},'pageErrors':errors,'checks':['object/source return preserves input','reload restores draft','mobile scroll checkpoint and rendered position restore','child close/reopen and reload restores draft','explicit latest only','immutable v1 retained after v2','simulated running indicator retained'],'publicFixtureOnly':True,'realAuthorityOrCancellationProven':False})
  ctx.close()
 b.close()
(out/'results.json').write_text(json.dumps({'browserVersion':browser_version,'baseURL':args.base_url,'results':results},ensure_ascii=False,indent=2));print(json.dumps({'passed':len(results),'evidence':str(out),'pageErrors':[r['pageErrors'] for r in results]},ensure_ascii=False))
