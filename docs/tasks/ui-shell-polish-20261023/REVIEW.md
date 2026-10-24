# Independent review

Base: `7aa852ab8134545c6312cd71de5c12cd49f66b5b`.
Initial implementation: `ef24ce11ed1b99e2be6938b18ff5f195cc8253b1`.
Final production source: `d61be4b50c3f4877022008e5493ade1ba78a96ad`.

An independent reviewer inspected the complete owned-source/test diff, then the menu-card and neutral-content-color increments. The reviewer made no edits and did not run device actions.

One test issue was identified and corrected before final validation: popup and activity `boundsInWindow` use different origins. The anchor assertion now records both positions using `positionOnScreen()`, checks finite values and compares in the same coordinate system.

Final static disposition: no remaining Important or Minor findings. Configuration confirmation, input filters, credential clearing, host revision/action gates and real conversation callbacks are preserved. No Reader, Service, native, shared-theme or public-interface files changed. Card titles retain full accessibility descriptions, selected semantics and distinct 48dp pin controls.

The neutral-ink regression is deliberately an activity/composer test: API26 Compose `captureToImage` cannot capture Dialog nodes. The failed Dialog attempt is retained locally and is not evidence of a product failure. The supported test observes actual rendered pixels against the existing foundation text token; its behavioral RED is preserved. It proves the tested composer action, not every theme/window/control.

Remaining acceptance: complete-product APK integration, full visual comparison, multi-card scrolling with large text, 200% font, TalkBack/focus traversal and device keyboard/back behavior. Component fixture execution does not establish backend availability or end-to-end product acceptance.

Final one-line attachment-guidance `onSurfaceVariant` fix was independently reviewed with no Important/Minor: no business, authorization, callback or availability change. It was then compiled/linted and its local-menu rendering fixture rerun successfully.
