# Actual additive presentation Kotlin binding

Single generated-file commit:
01e1c019501c30a4c2c9ff532b2e82035f3e2442

File apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/productbridge/muyon_android_product.kt
SHA256 c71b8062e07da7ee07059557acba768a7193b680fb20bc193a359b919d7dacdb
Locked actual UniFFI0.32.2 native build/generate/repeatcmpPASS. ktlint absentwarning;
Android generated source compilation and Service use NOT_RUN, never a fabricatedABI.

New actual generated records:
- DocumentPresentationOpenRequest(access:DocumentAccessRequest, selectionId:String)
- DocumentPresentationUseRequest(scope:DocumentReaderScope, presentationId:String,
  frameGeneration:String)
- DocumentPresentationChunkResult(offset:String,bytes:ByteArray,eof:Boolean,
  sessionActive:Boolean,frameGeneration:String)

New interface methods1807..1825:
- documentPresentationBeginSelection(scope) -> String
- documentPresentationOpen(request) -> String
- documentPresentationChunk(request,maxBytes:UInt) -> DocumentPresentationChunkResult
- documentPresentationCheck(request) -> String
- documentPresentationAdvanceFrame(request) -> String
- documentPresentationClose(request) -> Unit
- documentPresentationTakeInvalidations() -> String (trusted Service admin only)

Five draft signatures/checksums and LocalDraftPrepareRequest constructor match
old db40a794fb4b903142c3d0c20a7c3c2d157d9623 exactly. Checksums respectively resolve
29826/read65349/prepare63893/save4781/lookup33659. Thirteen raw/evidence method
signatures unchanged. Proof five-abi-proof.json; never use olddb40 as newbinding.

Host must derive actual principal/scope/existinggrant first. Serialize begin_selection
at authentic current selection event BEFORE asynclookup, retain original scope/token;
never callbegin on latecallback. Native token is opaque/singleuse/notgrant. Carry
original framegeneration through everycallback; stale error discards only oldresult,
never clears newerframe. Explicitadvance only afterEOF, no implicitlatestticket.
RawEOF still closes; presentationEOF retains same genuine lease/pin/snapshot ticket.
Ready means bytes complete, never PDF parse/render proof.

Anchor valid_for_ms/check_after_ms to REQUEST START monotonic time; check before
render and asyncpublish, poll <=check_after_ms<=1000, dispose actual PFD/cache/bitmap
on currentdenial/expiry/background/scopechange/terminalevent/clear_all. Drain native
invalidations after success ANDerror, route only matching scope/generation. Lost or
failed drain is uncertainty requiring clear_all. Oldcallbacklocalrefusal is not a
terminal event. No nativeOSrevocation/timer or Androiddisposal fabricated.

Hosteb853 reauth/Activity/principal and PFD/longreading acceptance remain ownerwork;
not imported or verified here. verified=false and publication hardrefusal unchanged.
