package com.mightyoung.muyon.product.documents.host

fun readerContinuationChecks() {
    // Native initial idle TTL is 15s; waiting 30s would already be expired.
    val deadline = ReaderPresentationDeadline.fromNative(1_000, 15_000, 1_000)
    check(deadline.expiresAtMillis == 16_000L && deadline.renewAtMillis == 14_000L)
    check(deadline.nextWakeAtMillis(1_000) == 2_000L)
    // A check does NOT touch or extend idle/absolute/grant deadline.
    val checked = deadline.checked(2_000, 14_000, 1_000)
    check(checked.expiresAtMillis == deadline.expiresAtMillis && checked.renewAtMillis == 14_000L)
    check(deadline.checked(2_000, 30_000, 1_000).expiresAtMillis == 16_000L)
    val shortGrant = ReaderPresentationDeadline.fromNative(1_000, 600, 100)
    check(shortGrant.renewAtMillis == 1_000L && shortGrant.isExpired(1_600))
    check(runCatching { ReaderPresentationDeadline.fromNative(Long.MAX_VALUE, 100, 10) }.isFailure)
    check(runCatching { ReaderPresentationDeadline.fromNative(0, 0, 1) }.isFailure)
    check(runCatching { ReaderPresentationDeadline.fromNative(0, 15_000, 1_001) }.isFailure)

    val domain = ReaderDocumentBatchDomain()
    var nativeOwnerPresent = true
    var clientGone = false
    val original = ReaderAdministrativeOwner(domain, "epoch", "session-A", { clientGone }) { nativeOwnerPresent }
    val other = ReaderAdministrativeOwner(domain, "epoch", "session-B", { false }) { nativeOwnerPresent }
    var permit: ReaderAdministrativePermit? = null
    var calls = 0; var drains = 0; var globals = 0
    domain.runAdministrativeBatch(original, { admitted ->
        admitted.requireOwner(original, domain); permit = admitted; calls++
        check(runCatching { admitted.requireDisconnected(original, domain) }.isFailure)
        clientGone = true; admitted.requireDisconnected(original, domain)
        check(runCatching { admitted.requireOwner(other, domain) }.isFailure)
        check(runCatching { admitted.requireOwner(original, ReaderDocumentBatchDomain()) }.isFailure)
    }, { admitted -> admitted.requireOwner(original, domain); drains++; false }, { globals++ })
    check(calls == 1 && drains == 1 && globals == 0)
    check(runCatching { checkNotNull(permit).requireOwner(original, domain) }.isFailure)
    val businessB = LocalWorkspaceReaderPrincipal("workspace", "epoch", "session-B", "project", 1, Any()) { true }
    val admissionB = ReaderAdmissionRegistry(businessB, domain)
    val selectedB = admissionB.acceptSelection(businessB, 1, ExactReaderSource("workspace", "project", "docB", "1", "pdf", "b".repeat(64)))
    val beforeFailureDrains = drains
    check(runCatching { domain.runAdministrativeBatch(original, { error("synthetic old A failure") },
        { drains++; false }, { globals++ }) }.isFailure)
    check(admissionB.isCurrent(businessB, selectedB) && globals == 0) // old A failure/CLEAN drain cannot stop B
    check(drains == beforeFailureDrains + 1)
    // No active business scope is required. Poison also cannot block real cleanup.
    domain.poisoned = true
    domain.runAdministrativeBatch(original, { it.requireOwner(original, domain); calls++ }, { drains++; false }, { globals++ })
    check(calls == 2 && drains == 3 && globals == 0)
    nativeOwnerPresent = false
    check(runCatching { domain.runAdministrativeBatch(original, { calls++ }, { drains++; false }, { globals++ }) }.isFailure)
    check(calls == 2 && drains == 3) // cannot reopen a new owner
    println("PASS reader continuation: native earliest deadlines/no check renewal; retained-owner administration independent of live scope/poison, exact owner/domain/expired permits; synthetic fixtures only")
}
