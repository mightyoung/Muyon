# Original brand placement + neutral foundation integration

Follow-up to published shell checkpoint3ecb544ad0a47ccc38fe830777f35588b92e8afc.
Parent explicitly released exact dependencies:

- Foundation `a2213ce2cc35bf5d42cdb306197d02a531539380`, containing implementation
  `a810f204c27658a43f3ed13cca7ea0e59ce450b8` and evidence. Ordinary merge retains
  source and review. Remaining Material container/inverse/error/scrim roles now
  map to the published neutral palette; no local modification of ui/system/.
- Brand resources `11d28aa8c85cfeb41a3efffefa6ab446257fc0c1` on
  task/ui-brand-resources-20261022. Ordinary merge, no local resource edits.

Actual placement:

- Main/default Agent identity gets one48dp original mascot_front above its title
  in the centered header; other configured agent/group headers do not repeat it.
  Menu uses the original40dp brand_icon next to Muyon text. Views/contact-sheet
  asset remains bundled but is not rendered as an identity.
- Image uses ContentScale.Fit with no tint, crop, regeneration or binary alteration.
  It is decorative beside the actual identity label. Header retains natural height
  in layout above the reading area, never an overlay; menus/actions remain48dp.
  No mascot in dialogs, approvals or body content; no role animation or authority.
- No manifest/launcher replacement, runtime permission or reader engine introduced.
  Actual production card snapshots remain unbound pending the read-only projection
  owner; no business gateway/create/start/model/search request added.

Verification actually executed:

1. Read actual brand PNGs visually before source placement. Compared all3 resource
   bytes directly with git archive400e206135690c284c8402521e3135cfb7bfaee8 plus
   resource map sizes/SHA256: PASS3, total6429816bytes. Raw diagnostic
   `evidence/brand-original-hashes.log`; full source map in brand resource report.
2. Foundation palette/role regressions:
   `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/ui/system/checks -v`
   PASS2 tests exit0; `evidence/brand-foundation-checks.log`. Mathematical source
   palette/role checks, not raster measurements or UI rendering.
3. Added2 instrumented header targets before implementation: single original
   mascot with body below header, and ordinary header without mascot. Existing
   menu test adds original icon visibility. Total shell instrumented methods8.
   Attempted `:app:compileDebugAndroidTestKotlin :app:connectedDebugAndroidTest`
   using actual temporary official Gradle8.13/JDK21, offline: FAILED exit1 before
   compile at unresolved AGP8.11.1; `evidence/brand-test-first.log`. No behavioral
   RED/GREEN and no passing Android target claimed.
4. Final actual Gradle command from apps/muyon_android:
   `GRADLE_USER_HOME=/workspace/ui-shell-tools/gradle-cache MUYON_UI_GRADLE=/workspace/ui-shell-tools/gradle-8.13/bin/gradle ./gradlew --offline --no-daemon --console=plain :app:compileDebugKotlin :app:compileDebugAndroidTestKotlin :app:lintDebug`
   FAILED exit1 at same AGP8.11.1 resolver prerequisite, before product compilation;
   `evidence/brand-final-android.log`. SDK filesystem failure remains unchanged;
   its installation was not retried, relocated, escalated or bypassed.
5. Authored source/document whitespace PASS. Original Gradle output retains its
   trailing-space diagnostic line; whole raw-log diff-check remains nonzero.
6. Non-author review_shell independently inspected final source diff and exact
   dependencies: no new static blocker, main-only single mascot, original icon,
   unmodified Fit rendering, decorative semantics with adjacent label and natural
   header layout. Confirmed prior Material role issue source-level closed.
   Reviewer did not run Android tests or inspect runtime screenshots.

Limits: no successful Android compilation/lint/APK/device/keyboard/200% font/
TalkBack/screenshot evidence. Rendering performance of original1254px assets and
header/body dimensions still need device verification. This is source placement,
not visual acceptance. No old device result inherited.

Next dependency: exact parent-reviewed read-only host projection SHA. Maintain the
exclusive ProductChatRuntime/ProductService/Rust ownership; MainActivity/ChatScreen
remain the sole shell owner's boundary. Public Office3 work stays independent.
Historical two unknown calls / ¥0.002620 reservation unchanged, main/develop unchanged,
no new paid CI/deployment/credentials/permissions. Leader B alone merges develop.
