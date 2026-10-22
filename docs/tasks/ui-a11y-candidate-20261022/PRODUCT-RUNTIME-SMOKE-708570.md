# Actual product APK minimum smoke — fixed708570, not PR102

Product source `708570d59ea51024ee69bb62c97f63380d490f78`, based on c130.
This is the **actual com.mightyoung.muyon.product debug APK**, not the component
preview harness. It does **not** include the subsequently merged PR102 Office/Bot
composition (parent reports develop4cbc9b053542dab65cf44f5bfbe98c0df49d56f6).
No product source, package identity, signature or APK bytes changed for this smoke.

APK426369208 bytes, SHA256:
`f1cc240fd981a1ea08841f3964c6422e5b240268984447022406428723ddeb0b`.
The **installed device base.apk** was independently SHA256-hashed by Android's
normal shell tool and returned exactly that value (`device-apk-sha256.txt`).

## Startup and fixture checks

Read actual startup path before installation: MainActivity binds ProductClient,
which calls connect/health. Service constructs local ports and an empty memory
credential vault. Native open/health perform only local database ownership/recovery;
initialization is a separate visible button. Chat entry reads agent_availability
and chat_scope; neither sends a provider/search request. Sending requires separate
configuration/preview/confirmation. No real credentials were supplied.

The task-owned AOSP API26 x86_64 software emulator had **no installed product
package** and **Accounts:0** before installation (`preflight.log`). Existing UI
component-preview package is a different application and was not used as target.
An initial combined read-only getprop/package/account command timed out; it made
no mutation. Individually checked reads then confirmed readiness/absence/account0.
No existing user app data was cleared or overwritten. The small local workspace
created via the real button contains no seeded business data, messages or accounts.

Actual install used ordinary `cmd package install -S 426369208` without replacement
flag. One install session1358214155 was observed progressing48%→81%→100%/sealed,
then returned **Success**. No duplicate install/retry. No runtime permission grant
was requested or accepted; no network/proxy/security changes. This is local-only
smoke behavior, not a whole-device packet-capture claim.

## Actual actions and results

1. `am start -W -n com.mightyoung.muyon.product/.MainActivity`: **Status:ok**,4404ms.
   Actual screen shows Muyon Assistant and `请创建新工作台`; no permission/ANR overlay.
2. Clicked the unique visible `创建新工作台` button, only in this fresh test instance.
   Actual empty chat shows `今天想做些什么？` and blank `消息草稿`; no message typed or sent.
3. Opened actual navigation via `打开工作空间导航`; menu shows main Agent first,
   no fabricated recent conversations, and real existing destination labels.
4. Clicked `关闭菜单`, verified empty main screen; reopened, pressed Back, verified
   main screen and absence of menu heading. Screens/hierarchy preserve those states.
5. Back from main returned to AOSP launcher (`back-foreground.txt`); re-entry
   returned **Status:ok**,2180ms (`relaunch.txt`).

No create-agent/save-draft/document-edit/provider/search/model action was selected.
No unavailable feature was enabled or test backend inserted. The screenshot
script stops on permission/ANR UI; none was encountered in this completed run.
Collected activity logs retain platform slow-operation/lifecycle warnings;
there is no product fatal/crash in the captured log. This is a minimum smoke,
not comprehensive lifecycle/performance acceptance.

## Real Service/native identity read

An **external instrumentation-only** additional test was compiled from archived
`RuntimeHealthSmokeProbe.kt` using `probe.init.gradle`. This did not change the
shipping product APK; its installed bytes remain the exact hash above. The extra
test APK is not a product deliverable. Only this one test method was invoked;
no other product test or inference test ran.

Probe invokes only `health` and `agent_availability` via the real ProductClient/
private Service, asserts identity and closes client in finally. **1/1 PASS**,1.636s,
`OK (1 test)`,status0/terminal code-1. Actual logged health:

```json
{"build_id":"708570d59ea51024ee69bb62c97f63380d490f78:95d79703ba3b05f9af3020118286fb5559f17c7042d183cee394074dc25ae811","synthetic":false,"workspace":"local-workspace","service_pid":3070}
```

Actual availability shows `configured:false`; chat `configured:false`,
`transport_bound:false`,reason `provider_owner_not_bound`; search `configured:false`,
`transport_bound:false`,reason `search_host_not_bound`; local_reads true.
This verifies real product/native health and absence of configured provider binding,
**not** model inference, document ReaderHost authorization, Office/Bot PR102,
full permission/receipt flows or all application functionality.

## Screenshots and delivery status

Four original PNGs are under `evidence/product-runtime-708570/`, with complete
source/APK hashes, file sizes, no-seed fixture caption and metadata in `screenshots.json`.
Actual device: API26 x86_64,1080x1920,420dpi,font1.0, system night mode yes.
They are actual product framebuffer captures, no generated image or composition.

- cold-uninitialized: fresh app before explicit local workspace initialization.
- main-empty: genuine empty main chat after local initialization.
- menu-open: genuine main-Agent navigation and gray remaining strip.
- menu-back-closed: actual return from the menu.

Parent superseded the prior conditional upload instruction while this install was
running: old708570 APK upload is **HELD**, prioritizing a forthcoming Office/Bot+
minimal UI candidate. **No Library preparation/upload/finalization was started**
for the old APK, screenshots or licence attachments; no uncertain upload exists.
Small licence-only attachment is prepared separately, without duplicating APK bytes.
The previously prepared426MB-with-APK ZIP is not uploaded either.

Next dependent work: parent must supply B's exact released new candidate SHA.
Then build/verify/smoke the new composition using the official tool/model caches;
708570 runtime results must not be inherited. No main/develop/PR102/B candidate
branch write or speculative merge performed.
