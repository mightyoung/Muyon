# Android recovery and component preview independent review

Scope: read-only static review of owned_emulator_adb.py, preview source provenance,
actual installation/instrumentation logs and final screenshot evidence. No device
operation, Gradle run, production/tool edit, network request or new installation
by this reviewer during this review. Only this report is written.

## Transport and authorization boundary

The client connects only to127.0.0.1:5559, sends ordinary CNXN and proceeds only
if the guest responds CNXN. AUTH or any other greeting closes the socket and raises
PermissionError. It contains no key generation/configuration, credential input,
authentication disabling, HOME override, SELinux/network/permission changes or
fallback after AUTH. This is direct normal transport to the already accepting,
task-owned guest, not an authentication bypass. The SDK adb host-home filesystem
failure is not recharacterized as permission to write that protected directory.

The implementation is a narrow local utility, not a hardened general ADB client:
received payload checksum and stream IDs are not verified; write_service has no
aggregate output bound (read_service does). Single fixed local guest, one stream
per connection, socket timeouts, frame/output bounds on reads and explicit closure
in capture.py limit current use. These robustness gaps must not be advertised as
production protocol validation or a guarantee for arbitrary peers.

Reviewed transport SHA256:
`7185f2c15bfc04b9a9871442210198b5661a61c9cd2fcc10c657cc0730e9a9c0`.

## Preview provenance and actual execution evidence

All12 source-manifest files were independently checked against fixed production
043bed97e218bc25202a803aff3c0de1a5da031f git objects, current production files and
preview copies: all hashes match exactly. This includes the original six-method
ConversationShellTest. Preview-only Activity declares a component preview/synthetic-fixture/source
label (visibility limitations for dark/modal captures are recorded below), uses local rendering only and supplies no
ProductClient, Service, transport or trusted business binding. Its card example
passes null actual snapshot and unavailable notice, not fabricated business facts.
Group governance is all unknown; the Bot editor is local preview without host save.
The product MainActivity/ChatScreen/Host/service chain is not running in this APK.

Independently ran aapt2 dump permissions on the already built preview APK (static
artifact inspection only). Package is com.mightyoung.muyon.uicomponentpreview;
only its own DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION is declared/used, no INTERNET.
This does not establish isolation of an arbitrary complete product APK.

Both install-main.log and install-test.log contain Success. instrumentation.log
contains six distinct test names, each completing STATUS_CODE0, then OK(6 tests)
and normal terminal INSTRUMENTATION_CODE -1. No failed/skipped test appears.
This is actual instrumentation output for the component preview test APK, not a
full-product test-suite pass or a newly rerun test by this reviewer. The two new
accessibility tests now have real runtime results in this preview scope; assertions
still do not certify actual TalkBack speech. Prior blocked Android attempts remain
historical, not retroactively successful.

Stable evidence SHA256:

- source-manifest.json: `742cc28453855865b4da8e5e8bfdbe6ccdaa0bc255232a765bb107d772909bb7`
- instrumentation.log: `c77d179de0352a6cd8aa2c31c7a2ac04a0b174016dd5364aed7ab8815bdc641b`
- install-main.log and install-test.log (each): `7fc0023a6402c7bd7abd98bb3e580968de4833eed07d88d1cc8d70819d69c7a0`

The actual two-APK assemble result and binary hashes are separately recorded in
maven-offline-restore/PREVIEW-RESULT.json and preview-gradle-003.log. This reviewer
previously performed that build as the dependency restorer; that build is not
presented as an independently reproduced build in this review.

## Capture status

Capture script uses normal shell navigation, pre-capture UI hierarchy surface
assertions, ANR rejection and raw exec:screencap PNG bytes. SHA and PNG dimensions
are computed from the received bytes. Metadata source/API/font are labels, not
values inferred from image pixels; raw device-property evidence must accompany
those claims. A pre-capture XML check alone cannot rule out a new overlay between
inspection and screenshot; final images require visual inspection. Rejected ANR
captures must remain excluded from delivery. Capture collection was still running
at initial review; final image disposition follows below after source is stable.


## Final eight-image verification

Author declared capture complete/exit0 before this final check. Independently
verified all8 unique manifest rows and actual PNGs: SHA256 matches, PNG signature
and IHDR dimensions match, Pillow verify and full pixel load succeed. All are
1080x1920. Visually inspected all8 images (chat light/dark, menu light/dark, Bot
light/dark, cards light, group light); no System UI ANR dialog appears. No byte
editing or device interaction performed by reviewer.

The rejected System UI ANR image is separately under evidence/rejected-captures,
absent from the8 delivery manifest rows. It is not a passing/captured UI deliverable.
Read archived evidence/preview-device-runtime.txt: boot_completed1, API26, x86_64,
physical1080x1920,420dpi,font1.0, consistent with final metadata. These are raw
reported guest properties, not independently re-queried device state. Archived
preview-six-source-tests.log matches the original instrumentation output.

Delivery limitations: the modal menu hides the preview banner, leaving only the
conversation's “预览” suffix; dark chat/Bot have a near-unreadable light-on-white
preview banner. Do not claim that all8 images visibly embed a readable full scope
label. Each published image must carry the explicit source/component-preview/
synthetic-data/not-full-product scope in its title or accompanying description.
The banner issue is in the isolated preview wrapper, not proof of a production
theme regression. Group is a scroll viewport, not the entire flow. The card image
shows unavailable, disabled query with no facts; it does not validate real card
producers or actions. Bot images show initial local editor state, not successful
host persistence, creation or execution. No bubbles/transcript/history behavior
is established by these empty-chat preview captures.

Final manifest SHA256: `bddd257a19c5848905774562ea5cc08d22e7ae9eb63db9938fbcb7a7e9eb0a04`.

| Surface/theme | Actual PNG SHA256 |
| --- | --- |
| chat/light | `2f4efd0184140f498b1e31fcbdec3e7daef5c7833a5968365588f9a2ff6119c9` |
| menu/light | `a803981d9c5e5ee1f88f56bc9fed266ea17c460f92a5d2971d186fdf729a9ea7` |
| cards/light | `d2c0ea50747bd9129d829e92d8b716c69fffd51017312eab30d24b37b00fc301` |
| bot/light | `768887f7b2840b7bc386be7a7ea64a895ac291ed4364f44fec40993da41d63da` |
| group/light | `2e87824cb10c76cd5e4cc3fa60f922979c250e8ed9a69c80a449da21ed9679fb` |
| chat/dark | `47c1bbea58909e1c11adf7d8f246a730af5f9b4a51329e8a233da8979db029a7` |
| menu/dark | `f2475a85764528c191bf22b4dbee8412378f8092754034485bd68615ad3c627e` |
| bot/dark | `652f59759e86374eb138284b2c033f0b006cd34cbcb77a0003223ced24babd05` |

## Final conclusion

Evidence supports real Android Compose component-preview rendering, installation
results and6/6 copied source instrumented tests on the task-owned software guest.
No remaining blocker to describing these images with the explicit limitations
above. It does not support complete product APK/device acceptance: native/model
inputs and full application integration remain separate; actual product AndroidTest
compilation currently fails at three PdfDocument.use calls in DocumentReaderPlatformTest.
Library upload/create/finalize results are outside this review and are not asserted.

No production or tool source changed by reviewer; no commit, Gradle rerun, device
operation, network request or agreement acceptance during this review.


## Final Library delivery and report cross-check

Reread ANDROID-RECOVERY-PREVIEW.md and preview-screens-043bed/README.md. They
explicitly distinguish full-product main compile success, full-product test compile
failure, successful isolated preview assembly,6 copied tests and8 component preview
images. They preserve unavailable real Host/cards/group/Reader execution, native/
model APK inputs and banner contrast/occlusion limits. No new full-product runtime
or screenshot claim was found. The earlier “no Library result asserted” conclusion
applied before this final supplementary check and is superseded only as below.

Locally cross-checked the supplied original successful API responses in
library-preview-confirmed.json and library-preview-rename-confirmed.json:
8 unique IDs, each create_library_file status=succeeded and rename status=succeeded,
matching file_id/library_file_id pairs; each returned byte count equals its original
local PNG; final CAPTURES metadata maps the same exact IDs and renamed filenames.
Each remote filename explicitly contains COMPONENT-PREVIEW-NOT-PRODUCT-APK and
synthetic. All8 PNG SHA256 remain identical to the previously inspected bytes.
All8 local user.library-file-version xattrs read as0, consistent with returned
current_version_number0. README's eight Library IDs match this metadata.

This is local verification against provided API response records, **not an
independent remote Library re-read or re-download**. No Library action performed
by reviewer. Per-transfer HTTP201 is the author's recorded tool outcome; the two
retained response JSONs independently show create/finalization success and rename
success, not raw HTTP transfer headers. No signed URLs are present in these files.
These records support reporting8 confirmed API-created and scope-renamed Library
items while retaining the component-preview limits. No remaining blocking finding
in this evidence-only delivery report.

Final supplementary input SHA256:

- `ANDROID-RECOVERY-PREVIEW.md`: `7efd19a21f3c43f94f536ee98bfdf5374e5d7fbf4e2d16dd845d3b127dec899b`
- `preview-screens-043bed/README.md`: `df4e379957a2682b6184a2700b6daf2e77a0690256328702034d1e766b79abe5`
- `preview-screens-043bed/CAPTURES.json`: `86d6e632f419d714f25a4443204e79ffb11d76f59078edd78b54473012ae866b`
- `evidence/library-preview-confirmed.json`: `d770d9357e748db313258a46e77759f2a8a0e8901c823fb16956e5ce68773ab4`
- `evidence/library-preview-rename-confirmed.json`: `52f4b3cbe0bb078e118fa2551bd8892870d85e414e66efd9acf955b6fd3ef169`
