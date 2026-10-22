# Independent shell review

Non-author agent `review_shell` read the actual working tree without editing files
or making service/network/model calls. Review covered authored MainActivity,
ChatScreen, shell sources and test targets; final configuration-host changes received
a separate follow-up review. This is static review, not Android acceptance.

Initial issues found and fixed:

1. Custom overlay did not isolate hardware-keyboard focus. Replaced with full-screen
   modal Dialog, left78% panel, dismiss scrim and unified onDismissRequest.
2. Opened-menu preference write failure was immediately cleared. Kept its error.
3. Returning to Main Agent unnecessarily required a readable optional catalog.
   Default now resolves independently of the catalog.
4. Accumulated draft/submitted text could overflow Activity Bundle. Drafts moved to
   isolated local preferences; single actual submitted-message display metadata is
   stored separately. SaveableStateHolder no longer retains these large strings.
5. Menu-retention test overlaid its edit button with the header. Test now uses a
   Column and real input draft, avoiding a false click target.
6. Generic connection errors could clear draft-save failure warning. Separate
   draftSaveError now clears only after a successful local draft write.

Final source conclusion: these six issues code-level closed; no new business
confirmation/intent/original-request authority regression or obvious Kotlin syntax
issue identified. File ownership respected. Final configuration-host review found
no blocking issue: same editor retained per local scope in Activity ViewModel,
process loss explicitly disclosed, IME-first Back and child step navigation, all
unsupported execution/query capabilities closed, no FFI or old cancel signature.

Residual: inherited FoundationTheme leaves some used Material roles at defaults,
including workflow chip secondaryContainer and research surfaceContainerLow.
New shell/user bubble uses surfaceVariant. Follow-up belongs to foundation owner.

Build/device evidence must come from actual subsequent runs. The review did not
independently execute Android compilation, IME/Back/rotation, TalkBack, screenshot,
200% font or inherited Kotlin tests. Those tests' actual integrator-run evidence is
listed separately in REPORT.md. No static approval is called runtime acceptance.

Final public-document/notice review: only existing project navigation is enabled;
common reader/edit actions disabled, no new engine/FFI/file authority. Menu failure
notice visible inside the modal. One low feedback issue was identified and fixed:
a successful pin commit now clears its specific previous failure message. Card and
contract merges contain no production card call and are not described as adoption.

Final fixed dependency review: exact cards0a8c9fede203ecb5f3a65fb3bd01bd104e429838
correctly describes recorded cancellation intent with no dispatch/remote-success claim.
No production cards call exists in Main/ChatScreen/shell. Pin success feedback fix
confirmed. No new static blocker. Actual Gradle final suite failed at AGP resolution;
SDK filesystem refusal stopped without bypass. Android acceptance remains open.
