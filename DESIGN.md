# Design

## Source of truth
Active · 2026-10-21 · native Android workbench. The latest user instruction assigns
WorkBuddy to layout, Muse to individual agent management, and Grok Bot to chat and
group organization. This overrides the earlier original-only reference brief.
Observed packages: WorkBuddy 2.6.1 (`com.tencent.workbuddy.app`), Muse
11.0.0.8.164 (`com.facebook.aura`), Grok Bot 1.14.1 (`ai.x.grok.bot`). Desktop
Muse hatch and Grok Bot 0.70.2 renderer supply readable component evidence.
Static evidence establishes component structures, not measured screen parity.

## Brand
Quiet, precise, personal. Use Muyon identity and system typography. Reuse neutral
reference geometry and icons; retain their provenance. Do not transplant vendor
logos, credentials, analytics or proprietary fonts into the app.

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
Four stable destinations: supplier, research, assistant, agent library. Compact
windows use bottom navigation plus a drawer; expanded windows use a left sidebar.
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
Neutral white / light-gray surfaces; dark sidebar #181818 and text #F0F0F0 in dark
mode, Muse primary text #111112, Grok blue accent #599CE7. 4dp rhythm; 16–24dp
content margins; 12/16dp corners; restrained one-pixel dividers; no ornamental
gradients or fake activity. System body typography with clear title hierarchy.

## Components
Shared Material3 tokens, adaptive workbench shell, reusable neutral SVG-derived
icons, identity tiles, member composite avatars, outlined identity/review cards,
scrolling chat content and bottom composer. Supplier/research screens and all
business approval dialogs keep their real actions and semantics.

## Accessibility
48dp minimum interactive targets, descriptive labels, visible selection, readable
contrast and scrollable forms. Essential unknown/approval information cannot be
hidden only in secondary metadata. Respect system dark mode and font scaling.

## Responsive behavior
Below 840dp use compact navigation. Above it show a 240dp sidebar and bounded
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
