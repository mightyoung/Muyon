# F5b slice 2b: frozen render callbacks

Status proposed; native Codex implementation, not in the completed Claude b0bb717 review scope.

UiRenderCapture freezes the validated plan, catalog, surface and revision and belongs to its generating controller. dispatchCaptured synchronously checks controller ownership, disposal, current plan/catalog identity, surface/revision, exact node identity and event presence before reaching dispatch. Existing wire events and controller dispatch remain unchanged. Every current renderer callback captures the build invocation, including detail back and business confirm/cancel; render no longer calls eventFor.

Two real widget RED failures: save the actual Field and ConfirmCard callbacks, accept a valid next revision, invoke before any rebuild: old code enters bottom dispatch once. GREEN: old callbacks reach zero bottom dispatch and zero sink; rebuilt callbacks work. Additional pure controller checks reject foreign owner, copied node, unknown event and disposal. F5c snapshot publish is not implemented here; this is acceptPlan coverage, not proof of the future publisher's monotonic revision/token/rebase behavior.
