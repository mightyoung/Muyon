# Design

## Source of truth
Active · 2026-10-21 · native Android workbench. The latest user correction assigns
Muse to the complete UI (components, interactions, colors, buttons and corner
geometry), Claude to typography, and requires a quiet conversation without
permanent configuration controls. Earlier WorkBuddy/Grok references remain only
where compatible with this correction; they no longer determine visual styling.
Observed packages: WorkBuddy 2.6.1 (`com.tencent.workbuddy.app`), Muse
11.0.0.8.164 (`com.facebook.aura`), Grok Bot 1.14.1 (`ai.x.grok.bot`). Desktop
Muse hatch and Grok Bot 0.70.2 renderer supply readable component evidence.
Static evidence establishes component structures, not measured screen parity.

## Brand
Quiet, precise, personal. Use Muyon identity, the selected Claude Sans/Serif font
resources with system Chinese fallback, and Muse component geometry. Retain
provenance. Do not transplant vendor logos, credentials or analytics.

## Product goals
Make the existing supplier/research functions reachable in one workbench. Make
individual agents and member groups manageable and durable. Keep real business
receipts and explicit approvals visible. No automatic multi-agent orchestration
or unverified provider availability is introduced by the visual work.

## Personas and jobs
One researcher manages papers, business records, assistants and organized chats
on a phone or larger Android window. New local records survive restart; historical
Flutter data migration remains out of scope.

## Information architecture
Four stable destinations: supplier, research, assistant, agent library. Start in
the conversation. Compact windows use a menu drawer; expanded windows use a left
sidebar. There is no permanent bottom tab bar competing with the composer.
Agent library has agents and groups. Agent details separate identity, role and
instructions; group details show independent member identities. Opening either
selects a durable conversation namespace. Original unresolved receipts stay global
and reachable across namespace changes.

## Design principles
Reproduce observed reference patterns where supported by evidence. Reuse the
existing business screens and approval controls. A decorative profile does not
grant tool permission or silently alter a model prompt. Group membership does not
create independent model executors. Group archival never deletes its members.

## Visual language
Muse light: background #fcfcfc, surface white, secondary #f3f4f5, divider
#0000001a, primary text #111112, primary action #0064d4. Muse dark: background
#181819, surface #28292b, divider #ffffff1f, primary text white. 4dp rhythm;
navigation radius12, cards16, composer/dialogs32; pill action buttons. Composer
send tile32 inside48 touch target, #cbe5ff/#111112 light and #0074e8/white dark.
Claude Sans for interface/user text, Claude Serif16/24 for assistant replies;
Chinese follows system fallback as in the reference CSS.

## Components
Shared Muse tokens over native Compose primitives, 240dp sidebar, 36dp visual
navigation rows inside48dp targets, reusable SVG-derived icons, member avatars,
agent directory cards16dp/padding20/minheight256 with two columns when wide.
The32dp composer has a plain textarea, left plus menu, right compact send action.
Settings, budget, new chat, local reads and history live in the plus menu. Pending
unknown recovery and consequential approvals remain explicit. Supplier/research
screens and business dialogs retain their real actions and semantics.

## Accessibility
48dp minimum interactive targets, descriptive labels, visible selection, readable
contrast and scrollable forms. Essential unknown/approval information cannot be
hidden only in secondary metadata. Respect system dark mode and font scaling.

## Responsive behavior
Below 840dp use compact drawer navigation. Above it show a240dp sidebar and bounded
content. Insets follow system bars and IME; composer remains reachable. Test a
compact device and larger/font-scaled window rather than inferring usability.

## Interaction states
Empty directories show creation actions. Storage corruption is a recoverable
error, never silently reset. Profiles/groups reflect local saved metadata, not
provider readiness. Connection, price-proof blockers and unresolved receipts
remain distinct. No sample conversation is rendered as real history.

## Content voice
Concise Chinese labels. Say “智能体”“群组”“成员”“职责”“指令”; distinguish local
organization from actual execution. Retain explicit request preview and receipt
query wording at consequential controls.

## Implementation constraints
Compose / Kotlin with existing dependencies and Rust/Binder boundaries. Reference
React bundles cannot run as native Compose components, so translate their observed
structure and tokens. No new network or pricing path. Local agent metadata contains
no credential. Retain existing test tags and targeted recovery regression tests.

## Open questions
- [ ] Runtime screenshots of authenticated reference states are unavailable while
  the Mac is locked. Owner: design verification. Pixel parity remains unverified.
- [ ] Real multi-agent scheduling is outside this visual change and requires its
  own execution/budget contract. Owner: core runtime.
- [ ] Image generation tool does not expose a model selector; requested
  gpt-img2.5 version cannot be independently asserted. Owner: asset provenance.

## Execution and verification plan
1. Preserve the existing accepted source and record reference package identities.
2. Build shared tokens/icons and responsive shell around existing business pages.
3. Add durable agent/group management and adapt chat presentation/namespaces.
4. Compile/lint; test persistence, invalid writes, navigation and recovery on API26;
   capture actual resulting screens. Keep old source-sealed evidence immutable.
