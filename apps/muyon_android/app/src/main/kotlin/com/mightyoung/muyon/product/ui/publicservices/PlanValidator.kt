package com.mightyoung.muyon.product.ui.publicservices

class ValidatedPlan private constructor(val plan: UIPlan, val context: ValidationContext)
fun validatePlan(request: PresentationRequest, plan: UIPlan, context: ValidationContext): PresentationResult =
    PresentationResult(Decision.TextOnly, "unavailable", null, listOf(request.requestId, plan.surfaceId, context.scopeGeneration))
fun validateEncodedPlan(request: PresentationRequest, raw: String, context: ValidationContext): PresentationResult =
    PresentationResult(Decision.TextOnly, "unavailable", null, listOf(request.requestId, raw.length.toString(), context.scopeGeneration))
