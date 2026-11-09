# Accessibility Checklist — UpFleet Arena

Phase 8 deliverable (PLAN.md §15) and usability requirements (PLAN.md §5.5).
Automated coverage lives in `upfleet_arena/test/core/accessibility_test.dart`
and the per-screen widget tests; the device-only items are tracked in
`PHASE8_DEVICE_TEST.md` §5.

## Implemented and covered by automated tests

- **Not color-alone.** Hit / miss / sunk use distinct shapes (cross / dot /
  ring) plus a written feedback card; ready / connected / eliminated states
  use icons and text labels, never color by itself.
- **Screen-reader labels.** The target board and the own board expose a
  localized `Semantics` label describing their dimensions
  (`targetBoardSemantics`, `ownBoardSemantics`). Avatar choices are announced
  as labeled buttons and report their selected state.
- **Localized semantics.** Board labels follow the active locale (verified for
  English and Vietnamese).
- **Reduced motion.** The player toggle and the OS `disableAnimations` setting
  both shorten tab and feedback-card animations to zero
  (`useReducedMotion`, covered in `feedback_settings_test.dart`).
- **Independent feedback toggles.** Sound and haptics can be silenced
  separately; neither is required to play (`match_feedback_test.dart`).
- **Clear failure feedback.** Invalid placement, duplicate shots, expired
  timers, denied permissions, failed discovery and Host loss each surface a
  readable message (asserted across the host-runtime and screen tests).

## Device-only checks (see PHASE8_DEVICE_TEST.md §5)

- [ ] System large-text / font scaling keeps every screen readable, no overflow.
- [ ] TalkBack / VoiceOver announces the boards, avatar buttons and Fire action.
- [ ] Touch targets remain usable on a small phone.
- [ ] Safe areas are respected on notched devices.
- [ ] Reduced-motion toggle visibly shortens animations on device.

## Known limitations / future work

- Boards are drawn with a single `CustomPainter`; individual cells are not yet
  exposed as separate screen-reader focus targets. Cell-level navigation is a
  post-MVP enhancement.
- Controller- and protocol-generated messages remain English (see the
  localization scope note in the Phase 8 commit).