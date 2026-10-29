# Dlock product opportunities

Research date: October 29, 2026. Reviewed the competitor's [homepage](https://docklockpro.com/),
[FAQ](https://docklockpro.com/faq/) and [important notes](https://docklockpro.com/important-notes/).
Competitor statements below are their published claims, not independently tested
capabilities. The user's successful stacked-display test is useful local evidence,
not certification across all arrangements.

## What the research changes

The FAQ describes offsets for stacked screens, saved preferences per display
setup, modifier bypass and automation. The notes describe Separate Spaces,
interrupted placement, and focus/system-version constraints. Their future Pro
edition is advertised with broader edge-placement capabilities. Those future
claims are not an implementation recipe or evidence that Dlock can safely offer
the same behavior. The notes also attribute disappearing-Dock behavior to a macOS
bug; we have not independently confirmed that diagnosis or a universal workaround.

Do not base pricing copy on a blanket “the competitor is expensive” claim. Its
FAQ currently describes free core locking in Lite. Dlock needs to sell its own
coherent experience and clear one-time offer, with accurate limits.

## First milestone implemented

- The native display map has contextual help when another display covers a
  screen's entire bottom edge. It uses the same edge calculation as placement.
- The help depicts the actual connected screens and can animate a suggested
  sideways offset. It preserves a stacked arrangement when possible, rejects
  suggestions that overlap another screen, and does not modify macOS's layout.
- A blocked placement opens the relevant explanation before sending any pointer
  gesture. A Displays shortcut and retry action help finish the setup.
- A read-only Separate Spaces check points to Desktop & Dock when disabled.
- An original [Dlock FAQ](FAQ.md) documents the current app rather than copying
  another product's claims. The landing-page FAQ gets a shorter subset.

## Highest-value next additions

### 1. Recover patiently after interruption

Queue a preferred-display restoration when real pointer activity interrupts it.
Wait for a short idle period, coalesce wake/reconnect events, and retry with a
deadline and a small maximum attempt count. Cancel if the user changes the pin,
disables locking, loses permission or licensing, or disconnects the target. A
single owner should control placement and license-operation state. Explain
“Waiting for pointer to stop” instead of immediately reporting failure. Menus
need live investigation; do not assume a fixed delay solves menu tracking.

Acceptance: moving the pointer never fights Dlock; stopping it permits one
verified restoration; failed attempts never loop forever or leave the pointer
in a synthetic position.

### 2. Remember a preference for each display setup

Use a sorted set of stable display UUIDs as the setup identity. Save the preferred
screen and auto-hide independently for desk, travel and lid-closed configurations.
Do not use transient display numbers or resolution alone. Default to a prior
explicit preference when a setup reappears; ask once for unfamiliar setups.
Keep manual Profiles as named presets. Avoid treating every small arrangement
offset as a new setup, since the guidance intentionally asks users to offset.

Acceptance: connecting and removing an iPad or closing the laptop restores the
right explicitly chosen screen without overwriting another setup's preference.

### 3. A compact setup health view

Extend the first milestone with permission status, observed Dock screen,
Separate Spaces, running competing utilities, mirroring and known unsupported
edge placement. Keep checks read-only; never reset Dock tweaks, change Spaces,
or quit another utility automatically. Offer one relevant action at a time.

Acceptance: distinguish a blocked edge, failed permission, unavailable display,
unobserved Dock and conflicting input guard. “Locked” remains an observed state.

### 4. A deliberate presentation mode

Start with a temporary explicit “Keep Dock off this shared screen” action that
chooses an available alternative and restores the previous selection afterward.
When there is no alternative screen, explain that hiding the Dock permanently is
a separate feature. Do not pretend auto-hide prevents every reveal or infer
screen-sharing activity from an app merely being open.

### 5. Shortcuts and safe automation

Expose Select display, Activate profile, Toggle locking and Read status through
App Intents first. Validate display identifiers and honor license, Accessibility
and placement-busy checks. A URL scheme or CLI can follow with the same action
router; URL-triggered actions need explicit abuse/privacy consideration.

### 6. Configurable bypass

Keep Option as the default and allow None or a deliberate modifier combination.
Explain accidental activation risks for common typing modifiers. Test key-down,
key-up, event forwarding and rapid changes. This is polish, not a reason to
fragment the app into subscriptions and editions.

## Defer until there is evidence

- Any-screen vertical placement or fully covered bottom edges without changing
  layout: requires an independently understood mechanism and native acceptance.
- A permission-free engine: research public APIs in isolation; the current event
  tap and placement engine requires permission. Do not remove permission gating
  based on a competitor's advertised behavior.
- Dock follows pointer or active window: optional at most; it conflicts with the
  core “stay on my chosen display” promise.
- Window tracking, icon layout freezing and a permanent Dock overlay: broaden the
  product and testing surface without solving the user's primary problem.
- Automatically disabling screensavers or deleting autohide-delay settings:
  competitor troubleshooting is not sufficient evidence for personal-setting
  changes or a confirmed macOS bug diagnosis.

## A stronger offer without a crowded page

Lead with a direct demonstration of the Dock staying on the selected screen,
then three steps, requirements, a simple one-time price and a short FAQ. “Your
Dock. Locked to your preferred screen.” remains the core message. Present setup
guidance as a benefit: “Shows you how to make your display layout work.” Keep
advanced troubleshooting in the full FAQ. Publish tested compatibility, licensing
terms, support and refund policy before activating sales. Do not advertise the
roadmap or the unvalidated size-lock behavior as a proven release feature.
