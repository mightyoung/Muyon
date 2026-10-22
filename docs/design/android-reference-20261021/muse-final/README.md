# Muse UI revision · 2026-10-21

Local UI delivery verified. Source candidate:
`07fd4509fb4653a67435957c4ba021a2c142af00`.
Build ID:
`07fd4509fb4653a67435957c4ba021a2c142af00:8f4ecd44b0d5b1b2c9a1f31abc82fbfcdc32693b43aec81b722bde2292e7ab93`.

[Installable APK](/private/tmp/muyon-muse-07fd4509.apk)
SHA256: `ded73c00ab079a2475e85091c86b498e0eb111412f6c59c759511a7076170ab1`.
This named copy is independent of subsequent Gradle output overwrites.

## What changed

The user's latest correction supersedes the first mixed-product visual treatment.
Muse supplies colors, button variants, card/field/dialog geometry, navigation and
the composer. Claude's selected Sans/Serif resources supply interface/response
typography, with system Chinese fallback. [Sources and exact tokens](../REFERENCES.md).

- 240dp sidebar on wide windows; compact menu drawer. No permanent bottom tab bar.
- Neutral #fcfcfc background, white surfaces, Muse dark palette and readable text.
- Agent cards:16dp radius,20dp padding,minheight256; wide two-column grid.
  Identity → instructions → review remains a real saved editing flow.
- Composer:32dp radius, plain15/24 textarea, plus menu and32dp visual send tile
  inside48dp touch target. No floating Material field label or large send button.
- Model/budget settings, search, local reads, new conversation and terminal history
  are in the plus menu. They are absent from the normal conversation surface.
- Unknown original requests, pending business receipts and consequential approvals
  retain explicit recovery controls. Historical terminal facts start collapsed;
  a deliberate query reveals the verified receipt.
- Only connection/initialization failures expose status/retry. Retry recreates the
  client lease and does not replay a business write.

## Actual screens

These are instrumented screenshots of the running application with synthetic
test roles and real local operations; they are not generated UI mockups.

| Surface | Compact light | Wide dark |
| --- | --- | --- |
| Conversation home | [Home](screens/00-chat-home.png) | [Home](wide-dark/00-chat-home.png) |
| Agent directory | [Directory](screens/01-agent-library.png) | [Directory](wide-dark/01-agent-library.png) |
| Agent identity | [Details](screens/02-agent-detail.png) | [Details](wide-dark/02-agent-detail.png) |
| Identity editor | [Editor](screens/02b-agent-editor.png) | [Editor](wide-dark/02b-agent-editor.png) |
| Save review | [Review](screens/02c-agent-review.png) | [Review](wide-dark/02c-agent-review.png) |
| Group | [Details](screens/03-group-detail.png) | [Details](wide-dark/03-group-detail.png) |
| Group conversation | [Chat](screens/04-group-chat.png) | [Chat](wide-dark/04-group-chat.png) |
| Expanded keyboard | [Input](screens/05-chat-ime.png) | [Input](wide-dark/05-chat-ime.png) |

[200% font screenshots](font2/05-chat-ime.png),
[all24 screenshot hashes/dimensions](SCREENSHOTS.json).

## Verification

Same APK/test APK pair for all accepted results:

- **26/26 required device methods PASS**, no failed/skipped/duplicate/omitted
  method.16 existing core methods +5 new UI/storage methods +5 picker methods
  (one of those generates fixtures). [Suite](SUITE.json), [manifest](SUITE-MANIFEST.json).
- Two further executions of the navigation/edit/input method PASS:200% font on
  compact API26 and1280dp wide/dark API26. These are repeated variants, not two
  additional unique methods. [Variant results](VARIANTS.json).
- Actual menu navigation, absence of permanent configuration controls, settings
  access, edited-role persistence, unchanged instructions, separate conversation
  IDs and preservation of global original identity markers are asserted.
- IME is confirmed actually visible; edited text and disabled send are displayed
  above its boundary. Screenshot capture waits for accessibility quiescence.
- Existing real supplier/research workflows,8 immediate owner rebind cycles,
  callback-loss original receipt recovery, code-point/contract vectors and price
  proof refusal pass. [Core log](CORE.log).
- Actual system PDF selection/cancel/zero publication/reselect/confirm/private
  attachment, ZIP import, directory import and private attachment after deleting
  the exact generated source all pass. [Picker PDF](PICKER-PDF.log),
  [private-after-source-removal](PICKER-PRIVATE.log).
- `assembleDebug`, `assembleDebugAndroidTest`, `lintDebug` PASS; dual ABI,
  generated bridge equality, native hashes and16KiB ELF/APK alignment PASS.
  [Build](BUILD.log), [package gate](PACKAGE.json).
- Python evidence gates4/4 PASS. [Log](PYTHON.log).

Compact instance: `emulator-5556`, API26, arm64,320×640px/160dpi. Font setting
restored to1.0. Wide instance: task-owned read-only `emulator-5580`, API26,
physical1280×960px/160dpi,1280dp window, dark mode; not a physical tablet claim.
Earlier attempts to enlarge5556 were rejected as evidence because API26 clamped
its frame and UiAutomation returned no valid screenshot. The accepted wide
evidence uses the separately booted framebuffer, not those attempts.

The Rust source and business/runtime/IPC implementations are unchanged by this
UI revision; the earlier127 passing Rust executions remain historical evidence,
not newly executed tests. No provider/key/paid call was made.

## Boundaries

The reference desktop was locked, so no authenticated reference screenshots were
captured. Exact component values and actual implementation screens are recorded;
cross-platform pixel-level parity is not certified.

Agent/group records are durable local organization. They do not silently inject
instructions, dispatch members or imply separate model runtimes. Live provider
pricing proof and the prior I04 hold remain unchanged. The overall36-scenario
product acceptance remains PARTIAL/HOLD; this UI delivery does not close it.
