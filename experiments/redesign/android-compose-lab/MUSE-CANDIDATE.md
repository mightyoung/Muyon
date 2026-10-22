# Muse conversation candidate — 2026-10-18

Bounded native Compose UI change from F2 `3f1be180bb009a91e659c113ba5b1916e5360332`. The assistant/tasks/data/settings information architecture remains intact. This is a candidate based on static evidence, not a pixel-verified Muse reproduction.

## Ownership

This branch owns `conversation/`, `MuyonLabShell.kt`, the UI-only `ConversationSnapshot.kt`, UI tests and this handoff. No Service, JNI, Rust, generated bridge, Gradle or production host changes. LeaderB remains the sole integrator. No merge into develop/main, force push, deployment or release.

## Evidence and decisions

Fixed research commits: `190ddd88359a4f1a8f21f8d62d9186eb474137e9`, parent `3c9ac395ac8424e9e43b58381fb5001bd1f30821`. PR69 is closed/unmerged; its current head differs from the fixed evidence.

The authorized Muse original `base(1).apk` was downloaded again privately: 42,279,886 bytes, SHA256 `c7e788b5df855912dffbefc4c017f2e621b54aaeef954424f56339bd994fcefa`. Fixed manifest/badging identify `com.facebook.aura`, version `11.0.0.8.164`, code1061601403, min29, arm64-v8a; required splits empty, optional split inventory unknown. No Muse account, runtime or paid model was used. The denied Library research file was never read.

Direct DEX method inspection establishes compact sidebar width `layoutWidth−80`, capped to360 on noncompact windows; opening drag thresholds `.45×width` and `.6×width/second`; search/new-thread bottom-bar calls; active/archived/search branches; composer attachment previews; keyboard-scroll callbacks. Sidebar radius24 and several spacing constants exist in alternative branches. APK, bytecode extracts and tools remain private scratch files.

The candidate uses the evidenced width with Android's600dp compact breakpoint as an explicit local assumption. Material3 supplies scrim/back/drag mechanics; its drag thresholds are **not** a Muse reproduction. Message bubble geometry, typography, colors, top avatar position, history grouping, automatic scrolling and restoration are original candidate choices because direct visual evidence remains missing. Search/new are available in the sidebar; their arrangement differs from the identified Muse bottom-bar component. No timestamps are invented: the group is “本次使用”. Archive/cloud history are unavailable.

## Pages and state

| Surface | Candidate behavior |
| --- | --- |
| Conversation | Compact title/avatar, full-length user records, fixed rounded multiline composer, IME padding, explicit disconnected status; save means local save, send disabled |
| Sidebar | Left sheet, scrim, back, selected session, local search, new, rename, draft markers, settings entry; original four product destinations preserved |
| Offline visual sample | Explicitly labeled user/assistant typography, fenced code, link, collapsed unknown tool, stopped/failed states; read-only input, save/send/retry disabled |
| Other pages | Existing task/data/settings pages and native diagnostics retained |

One UI state owns conversations, exact drafts, notes, search, theme and selection. Independent per-session lists retain scroll across page switches. Samples use a separate list. ViewModel retains full text across configuration changes; platform saved-instance payload is capped at96KB. Oversized process-restoration payload is omitted whole and visibly reported, never silently truncated. There is no durable repository or server conversation history. System restoration and device IME require runtime validation.

No mascot/frame decides execution success, authority or tool use. This offline conversation port still exposes only NOT_CONNECTED. Real Rust run projections and provider wiring remain an explicit LeaderB integration boundary, not simulated UI behavior.

## Resources

The approved original puppy ready cutout is included as `drawable-nodpi/muyon_ready.png`, SHA256 `1e5840b5a9caf9711ee3db83b9be0511b1a84ea312bf54bd2f3d4d34c6d66ff8`, Library `libfile_db2c777171808191b1a93ae1d587f47a`. Header displays it at32dp with padding; it conveys only local-mode identity. The approved welcome cutout `libfile_ef6aefaaf8cc819185cca1ad6cd0ae83` is displayed at128dp in the empty conversation, preserving the supplied square transparent composition (SHA256 `a6b94360c85f3aa6be7399accfbcffadf4a57ca7341d6a5ccdc27c66074b1688`). Six-state concept sheets are not production sprites. Function glyphs are original tintable Canvas vectors. Separate state sprites and adaptive my icon are follow-ups rather than improvised identity changes.

## Validation and remaining gates

Independent test author and independent reviewer checked this candidate. Review found unbounded saved-state payload, sample scroll pollution and width mismatch; all received targeted changes. Pure JVM suite includes Unicode/exact draft retention, invalid snapshot rejection and oversized-state controls. Android tests cover sidebar/back/search/rename, local draft isolation, long content, fixture safety, saved-instance harness and semantic names.

Raw commands, exact source hashes, tool checksums and results are retained privately in `/workspace/scratch/ui-tools/logs/`. Do not equate JVM tests or source review with visual improvement. Until a signed installable APK is built and actually rendered, Android/IME/TalkBack/rotation/screenshot gates remain NOT_RUN. No generated illustration is evidence of an APK screen.

Declared ordinary app identity remains `com.mightyoung.muyon.androidlab`, `0.0.1-lab`, minSDK24; no native libraries are added by this UI branch. Installed ABI/signature/hash must be inspected from the produced APK rather than inferred from Gradle declarations. Delivery target is a private Library APK attachment, never an androidTest APK or public release.
