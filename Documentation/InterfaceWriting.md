# Interface writing

These are Ode’s canonical interface-copy rules for native Mac, iPhone and iPad
surfaces. Use them when writing strings and reviewing the rendered interface.
Concise copy removes repetition, not information needed to make a choice.

## Default view

- Lead with the action or state: “Open Email”, “Copied”, or a specific failure.
  Do not introduce a slogan, eyebrow or promotional subtitle. No ornamental
  leading-zero numbering: actual counts, versions, progress and ordered steps
  remain appropriate.
- Do not paraphrase a label in helper text. A heading, control and subtitle
  should not all explain the same thing. Remove the duplicate rather than
  shortening each version.
- Show one message per event. A success status reports the result; it does not
  repeat the instructions beside the action. Never claim delivery, saving or
  completion when only a handoff has occurred.
- Keep necessary consequences visible **before** the action or choice. Privacy,
  permissions, remote data use, destructive scope, cost and capability limits
  must remain understandable where the person decides. Brevity is not a reason
  to hide consent or a meaningful warning.
- Preserve meaningful empty states, specific errors, accessibility labels and
  search keywords. A subtitle can be useful when it distinguishes an unfamiliar
  feature or explains a non-obvious consequence; length alone is not a reason
  to remove it.

## Guidance and recovery

- Put optional guidance where people intentionally seek it: a specifically named
  native disclosure, contextual help or an existing help destination. Reuse Ode’s
  design-system and platform patterns. Do not add a generic “Details” control to
  every row, invent a help framework or replace redundant prose with footers.
- Make help discoverable and usable with pointer, keyboard, touch and VoiceOver.
  Do not rely on hover-only help for a choice people must understand on mobile.
- Keep errors short and specific: what failed and the next useful action.
  Preserve the draft or other recoverable work; do not imply it was lost or
  promise a recovery the product cannot perform.
- Keep required credits, license links and legal notices accessible in About’s
  Credits and Licenses area. Preserve exact upstream notices and copyright.
  Mention Arc or another browser only for a useful, truthful migration or
  familiarity reference, never as invented code provenance or endorsement.
- Localize user-facing strings through the existing catalog. Keep semantic
  labels even when decorative or duplicate visible text is removed.

## Review gate

Review the actual default screen, then its expanded help and failure/recovery
states. Ask of each text block: does it name an action/state, distinguish a
choice, disclose a necessary consequence, or offer useful recovery? Otherwise
remove it or move genuinely optional guidance on demand. There is no hard word
count: the information need determines the length.

Capture screenshots of the default **and** relevant help/error states on the
affected desktop/mobile surfaces, including larger text or accessibility paths
when relevant. Keep evidence outside the checkout. Source inspection, a build,
formatting or passing tests alone cannot establish copy or visual acceptance.
For web surfaces, scan the rendered DOM across **all classes** for
`eyebrow`/`kicker`/`overline` patterns, standalone ornamental leading zeros, and
visible tiny uppercase tracked text. Inspect computed styles and semantic
placement, not just one selector or class-name search. Any allowlist must be
narrow, documented and limited to genuine functional states; it must not exempt
whole components from review.

Native SwiftUI has no DOM; a web DOM scan does not review the native interface.
Apply the same anti-slop review through screenshots and the accessibility tree
on native screens. Neither a source-string grep nor an accessibility dump alone
proves that the rendered default/help/error states are clear.

Do not add permanent tests solely for wording or layout. Existing behavioral
assertions should protect meaningful states, privacy, data preservation and
recovery rather than pinning a sentence. Never weaken those contracts or delete
a failing test just to make a copy change pass.
