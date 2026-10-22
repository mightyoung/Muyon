import sys,json,re,traceback
from pathlib import Path
sys.path.insert(0,'/workspace/host-bot-native-tools')
from task_adb_transport import shell
e=Path('/workspace/host-bot-native-tools/evidence')
command='am instrument -w -r -e class com.mightyoung.muyon.product.agentipc.BotNativeServiceAcceptanceTest com.mightyoung.muyon.product.test/androidx.test.runner.AndroidJUnitRunner'
(e/'instrumentation-dispatch.json').write_text(json.dumps({'state':'DISPATCH_ONCE','command':command,'no_automatic_retry':True},indent=2))
summary={'command':command,'legacy_shell_exit_status':None,'device_test_result':'UNKNOWN'}
try:
 out=shell(command,e/'device-instrumentation.log')
 statuses=[];prior=0
 for m in re.finditer(r'INSTRUMENTATION_STATUS_CODE: (-?\d+)',out):
  block=out[prior:m.start()];prior=m.end()
  name=re.findall(r'INSTRUMENTATION_STATUS: test=([^\r\n]+)',block)
  statuses.append({'method':name[-1] if name else None,'code':int(m.group(1))})
 expected={'realServiceSaveCasCancelAndProcessLossRestore','realNativePreparedOriginalIsDiscoveredAndExplicitlyFencedByService','committedNativeReplyDiscardedIsRecoveredOnlyAsOriginalHistory'}
 completed=[x for x in statuses if x['code']==0]
 passed=len(completed)==3 and {x['method'] for x in completed}==expected and 'OK (3 tests)' in out and 'INSTRUMENTATION_CODE: -1' in out and 'FAILURES!!!' not in out and all(x['code'] in (0,1) for x in statuses)
 summary.update(statuses=statuses,terminal_transport_closed=True,device_test_result='PASS' if passed else 'FAIL')
except Exception as ex:
 summary.update(error=repr(ex),state='UNKNOWN_NO_RETRY');traceback.print_exc()
finally:
 (e/'device-test-summary.json').write_text(json.dumps(summary,indent=2))
 try:shell("logcat -d -v brief -s BotNativeAcceptance:I '*:S'",e/'device-identity-logcat.log')
 except Exception as ex:(e/'device-identity-logcat-error.txt').write_text(repr(ex))
 print(json.dumps(summary,indent=2))
if summary['device_test_result']!='PASS':raise SystemExit(1)
