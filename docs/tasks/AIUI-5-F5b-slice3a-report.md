# F5b slice 3a: explicit library-2 catalog

Status proposed; native Codex, not covered by the earlier Claude source review.

The independent library2UiCatalog retains all 33 names and adds collection shapes/typed event payloads, Heading and Chart allowed values, Tabs Section child restriction and optional controlled state, readonly Checklist with optional checked selection. Choice custom entry and model min/max/step are removed from this catalog. Old catalog objects are unchanged. supportedUiCatalogs contains minimal, dynamic and library-2, excludes library-1.

Shared validator checks host spec classes even for readonly widget bindings. Choice/Checklist selection must reference the same collection, explicit Choice multiple must agree with the host, Tabs and Disclosure are view specs, Tabs selected ID must be a child, and Slider step divisions must be integral 1..10000. The generic validator remains the single admission path.

Three real RED groups fail against the interface-only 927bc79 catalog; all three pass after implementation. Full API 159 passed after these shared validator additions. The 33 renderer test still fails because library-2 has not yet been enabled in the surface; this is handled by the next slice rather than reporting a catalog map as complete rendering.
