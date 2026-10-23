package com.mightyoung.muyon.product.development

fun main() {
    var passed = 0
    fun test(name: String, body: () -> Unit) { body(); println("PASS $name"); passed++ }
    test("conversation, project and draft changes invalidate late responses") {
        val scope = DevelopmentCallbackScope()
        scope.select("conversation-a", "project-a", "draft-a")
        val first = scope.capture()
        scope.select("conversation-a", "project-a", "draft-a")
        check(scope.accepts(first))
        scope.select("conversation-b", "project-a", "draft-a")
        check(!scope.accepts(first))
        val second = scope.capture()
        scope.select("conversation-b", "project-b", "draft-a")
        check(!scope.accepts(second))
        val third = scope.capture()
        scope.select("conversation-b", "project-b", "draft-b")
        check(!scope.accepts(third))
    }
    test("unmounted editor rejects callbacks even for the last selection") {
        val scope = DevelopmentCallbackScope()
        scope.select("conversation", null, "draft")
        val token = scope.capture()
        scope.close()
        check(!scope.accepts(token))
        scope.select("conversation", null, "draft")
        check(!scope.accepts(scope.capture()))
    }
    test("durable identities do not collide at delimiter or null boundaries") {
        val keys = listOf(
            developmentScopeKey("a:b", "c"), developmentScopeKey("a", "b:c"),
            developmentScopeKey("a", null), developmentScopeKey("a", "none"),
            developmentScopeKey("a", ""), developmentScopeKey("", "a"),
        )
        check(keys.toSet().size == keys.size)
    }
    test("A to B to A cannot revive a callback from the first A") {
        val scope = DevelopmentCallbackScope()
        scope.select("conversation", "project-a", "draft", 7)
        val firstA = scope.capture()
        scope.select("conversation", "project-b", "draft", 8)
        scope.select("conversation", "project-a", "draft", 9)
        check(!scope.accepts(firstA))
        val current = scope.capture()
        check(scope.accepts(current))
        scope.select("conversation", "project-a", "draft", 10)
        check(!scope.accepts(current))
    }
    test("project review freezes the displayed command and scope instead of inheriting a new scope") {
        val review = DevelopmentProjectReview("shown-plan", "shown-native-binding", 7, "shown-draft", "5")
        check(review.canConfirm(7, "shown-draft", "5"))
        check(!review.canConfirm(9, "shown-draft", "5"))
        check(!review.canConfirm(null, "shown-draft", "5"))
        check(!review.canConfirm(7, "another-draft", "5"))
        check(!review.canConfirm(7, "shown-draft", "6"))
        check(!review.copy(bindingDigest = "").canConfirm(7, "shown-draft", "5"))
        check(!review.copy(planId = "").canConfirm(7, "shown-draft", "5"))
        check(review.planId == "shown-plan" && review.bindingDigest == "shown-native-binding")
    }
    test("scope generation accepts only native nonnegative integer JSON values") {
        check(developmentScopeGeneration(0) == 0L)
        check(developmentScopeGeneration(Long.MAX_VALUE) == Long.MAX_VALUE)
        check(developmentScopeGeneration(-1) == null)
        check(developmentScopeGeneration(-1L) == null)
        check(developmentScopeGeneration("7") == null)
        check(developmentScopeGeneration(7.0) == null)
        check(developmentScopeGeneration(null) == null)
    }
    println("$passed/6 PASS")
}
