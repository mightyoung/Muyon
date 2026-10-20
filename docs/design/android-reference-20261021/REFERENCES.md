# Android page reference evidence

Latest user correction: Muse for the complete UI, Claude typography, quiet chat
without permanent configuration/button clutter. The initial WorkBuddy/Grok split
is superseded for visuals; neutral icons and member relationships are retained.
Source folder: https://drive.google.com/drive/folders/1ifCHLvXiRAThyWUyCb6FbP8CfvKjnrVi

## Package identity (observed with Android SDK aapt)

| Drive file | Package | Version | SHA256 |
| --- | --- | --- | --- |
| base.apk / 1KbqHQeFiaclV6qx5vC8lq0i9MNDHbCwx | ai.x.grok.bot | 1.14.1 | ef03c2e090d38318f5d47887d004c223c8b59ab3b40d7c44f390a15f0ed43aed |
| base(1).apk / 1U8RgVCVXvavevoCEeNKs9H2Tf6k1Vjc6 | com.facebook.aura | 11.0.0.8.164 | c7e788b5df855912dffbefc4c017f2e621b54aaeef954424f56339bd994fcefa |
| base(2).apk / 12u0R5_dyUPamFlX2VSQUX8Wg6G8-cQWh | com.tencent.workbuddy.app | 2.6.1 | 5ce904337ba2821fb1cdb7965075445746d198bc82d40b12d6842d24f1da34e3 |

The other two supplied files were identified as Claude and ChatGPT and were not
used for this design. WorkBuddy exceeds the connector's 256MiB limit; the same
Drive file was downloaded directly, not replaced by another package. APKs stay
outside Git at `/private/tmp/muyon-design-references`.

REA skill: `/Users/muyi/.claude/skills/reverse-engineer-anything/SKILL.md`.
Fixed CLI `rea-agents@6.4.0` was used without global configuration changes.
WorkBuddy archive inspection evidence:
`ev_9065911715f26142680584f7e7a8d3719c4ddf38d2d0f6a1179d2e0d2a66118c`.
Android decompilation returned `capability_unavailable`: the separately supplied
JADX MCP JAR is absent. SDK `aapt`, ZIP inventory and existing readable desktop
bundles supplied the supported static evidence; no successful JADX run is claimed.

## Components translated to Compose

Muse desktop `hatch/index.html`: `CreateSharedAgentDialog`,
`CreateSharedAgentReviewStep`, identity fields name/role/avatar/accent and separate
instructions; Intro → Definition → Review; 16px identity card, 20px padding,
12px secondary pane. These are observed packaged React components, not an Android
Compose source library. They inform native component structure.
Bundle SHA256: `12ed9816b5e65cd71233bc1290585d0fd51c3e793baf2b446c49af9d24d7c8f3`.

Grok Bot desktop 0.70.2 `dist/renderer/assets/index-CjjO5fU0.js`:
`sand-group-avatar`, `sand-group-member-row`, `sand-chat-input-dock`,
`sand-input-area`; bot details and member chip chunks. CSS `index-Dve5Ol5U.css`
contains #181818 sidebar, #F0F0F0 base, #599CE7 accent, 8% secondary surface and
20% divider, 12/16px corners. Independent members remain usable outside groups.
Desktop bundle observation does not prove an identical mobile screen layout.
JS SHA256: `632cf699dba2f74be35ba9215fbdcfae5ca36c60300936d601c185e2695a49dd`.
CSS SHA256: `7a1f78e57358cc7d1276d8fde21ab33376dd41af96a41c2ef30235c78183d3c1`.

WorkBuddy ZIP `assets/flutter_assets/assets/icons/` directly supplies neutral
`chat-bubble.svg`, `common-add.svg`, `cloud-conversation-menu.svg` and
`file-types/file-text.svg`. Their original paths/offsets are translated to Android
vector drawables `wb_chat`, `wb_add`, `wb_menu`, `wb_document`; only tint and
container sizing adapt to the shared theme. No new icon dependency is added.

No vendor logo, analytics module or provider code is imported.
The bundles do not establish an application open-source license; reuse is recorded
as user-directed reference-resource reuse, not represented as third-party open
source. Existing business components, dialogs and runtime are reused directly.

## Muse correction and Claude font resources

Muse `HatchComposer` at character38592964: radius32, inner padding12,
textarea15/24 and maxheight192, left attachment/+ and right32px action. Chat send
overrides generic blue primary: light #cbe5ff/#111112, dark #0074e8/white,
disabled40%. No provider/budget/config label belongs to this component.
Generic buttons: pill, visual heights32/36/44 and horizontal padding12/14/16.
Navigation:240px sidebar, row36px/radius12/label14/20; dialogs squircle32.
Agent management cards: white/divider/radius16/padding20/minheight256; gap16,
wide two-column grid. These are exact observed component values adapted to Android
dp and48dp touch targets; they do not establish pixel parity across platforms.

Muse dark values, `.dark` at42841932–42846220: bg#181819, fill#28292b,
divider#ffffff1f, text white, secondary#f2f7ff87.

Claude selected packaged fonts are copied into `app/src/main/res/font/`:
- `claude_sans.ttf` from `Claude.app/Contents/Resources/fonts/AnthropicSans-Romans-Variable-25x258.ttf`;
  SHA256 `4eda2c42031a090a3d01cd58ada3de00f467e3e359efad36572f26e43ecba65f`.
- `claude_serif.ttf` from `AnthropicSerif-Romans-Variable-25x258.ttf`;
  SHA256 `cb2c65e0d0d326181f2a2525ad344cacc850a41c24aeaea51cc70df8c88a3231`.

Claude `ion-dist/assets/v1/c6a992d55-C0zTICcS.css` assigns Sans to UI/user and
Serif to response; reply16px/1.5, headings20px/600/1.4, title28px/600/1.3.
The original CSS uses system Chinese fallback; these fonts do not supply CJK glyphs.
This records user-directed resource reuse and does not label the fonts open-source.

## Generated asset

`app/src/main/res/drawable/muyon_avatar.png` is a new transparent porcelain loop
avatar generated through the built-in image tool, not copied from a vendor.
SHA256: `d117edae10e75d44f7542107711e1291d73da1ddd71e0cf1b0785eb511dca8bb`.
Prompt: single centered ivory abstract folded loop, pale sky-blue reflections,
matte porcelain, transparent background, no face/text/logo, legible at 48dp.
Tool output: `exec-c3a88728-d566-4575-8135-691b27d45d4d.png`.
The tool did not expose a model selector, so the requested gpt-img2.5 version is
not independently confirmed.

## Evidence limits

Mac screenshot collection was blocked by the locked desktop. No reference account
was accessed, no terms accepted and no reference APK executed. Pixel-level parity
is unverified. Implementation screenshots and actual interaction tests are separate
evidence, not substitutes for a missing reference screenshot.
