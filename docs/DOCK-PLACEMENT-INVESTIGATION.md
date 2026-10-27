# Dock placement investigation — 2026-10-26

Target: the user-supplied DockLock Lite 1.5.2 (631), bundle `pro.docklock.lite`.
Original application was inspected without modifying its bundle or receipt.

## Evidence and limits

REA 6.7.0 `inspect-macho` inspected the original universal Mach-O, selecting arm64.
Evidence ID: `ev_ff89b81dca73e5462f6f2ef219bdf2ba3aaed1f4324f6e6b7fdfbf4457d1e6ca`.
Binary SHA-256: `75c20e10a0bd5ce780890abca3248c71afc154a4e7d4874d8ae75286e13639cd`.
Full local evidence is retained in `/tmp/docklock-rea-macho.json`.

REA's deep-analysis route was unavailable because no supported decompiler engine
was configured. Native inspection remained available. Xcode's `llvm-objdump`
provided the following additional static call-site evidence; this is disassembly,
not recovered original source or observation of the original app running:

- At arm64 address `0x100003dc0`, a helper has two paths: one tail-calls
  `CGWarpMouseCursorPosition`; the other creates a mouse event, sets field 42
  (`eventSourceUserData`) to a marker, and posts to tap 1 (`cgSessionEventTap`).
- At `0x100003e7c`, a restoration helper warps the cursor and conditionally
  re-associates the mouse and cursor.
- At `0x10003aa64`, relocation code selects the event helper's behavior using
  a per-step flag. At `0x100038614`, cleanup calls the restoration helper.
- At `0x10003a000`, placement logic checks a half-second interval and mouse
  buttons before proceeding.
- The artifact also contains `CursorPresentation` and `JUI::MouseCursor` type
  metadata. This establishes cursor-presentation machinery exists; the exact
  visual experience of Lite was not dynamically observed.

These observations support synthetic placement with tagged events, placement
sequencing, and explicit restoration. They do not establish a private API for
assigning the Dock to arbitrary displays. Lite evidence does not establish Pro's
implementation or its support for additional display layouts.

## Dlock implementation

Dlock's previous implementation treated changes to the global pointer location
as real user input. Its own synthetic events could trigger that cancellation;
the cancellation path explicitly skipped restoring the pointer. It also rejected
selection while WindowServer still reported the selection click as held.

The replacement is independently implemented in Swift:

- Wait briefly for the selection click to release.
- Use an operation-specific event marker and a scoped input tap, so synthetic
  placement is distinguished from hardware input.
- Keep a cursor image at the original screen position while the system cursor
  services the Dock. Pair cursor hiding with restoration on every exit.
- Cancel on real input, rebase that input to the original pointer position, and
  restore the pointer before forwarding a click or scroll.
- Restore pointer location, cursor visibility, event tap, overlay, and temporary
  auto-hide changes on success, cancellation, timeout, and display loss.
- Verify the destination through Dock Accessibility geometry; after turning
  auto-hide back off, verify the visible Dock again.

This remains synthetic Dock placement. It is not a direct display-assignment
API, and side-edge placement remains constrained by macOS/display geometry.
No DockLock source code, resources, or binary implementation is incorporated.

## Validation

Native probes compiled the actual Dlock controller, guardian, screen manager,
and related production sources. On the connected Built-in Retina Display and
HP E233 with the bottom Dock:

- Auto-hide off/on/off: each placement reported HP E233 through Accessibility.
- Selection of Built-in Retina Display, then HP E233: both destinations verified.
- Pointer returned to its original coordinates; Dock PID stayed unchanged.
- Presentation probe: own tagged movement did not cancel placement.
- Injected untagged hardware-path movement cancelled placement, rebased the
  movement to the original pointer, and removed the cursor overlay.
- Repeated cleanup was safe.

These probes are integration evidence, not proof of every layout or macOS
version. Installed-app menu checks and build results are recorded separately
below as they are performed.

## Installed-app checks

The rebuilt application was signed with the existing local Apple Development
identity and installed at `/Applications/Dlock.app`. Signature verification
passed. The app's real menu controls were exercised through Accessibility:

- Selected HP E233, Built-in Retina Display, then HP E233. Both the persisted
  pin and actual Dock display matched after every selection.
- Auto-hide off/on/off matched the saved setting and kept the Dock on HP E233.
- Pointer coordinates remained identical before and after every operation.
- Dock PID remained unchanged throughout.

An initial temporary integration runner used a trapping assertion and generated
a crash report when hidden-Dock detection returned unknown. This was the runner,
not Dlock. It exposed a production detection bug: a hidden bottom Dock's AX
rectangle started at HP E233's bottom edge, outside the screen. Detection now
uses the rectangle's inward edge instead of its center. Seven offline regression
checks cover visible/hidden bottom, left and right geometry and a stacked
neighbour. The final installed-app run passed with the corrected detection.

Debug build succeeded. `git diff --check` and strict signature verification
passed. Runtime checks cover the connected bottom-Dock arrangement, not every
side-edge arrangement, sleep/wake scenario, or future macOS release.

## Right edge on the built-in display (2026-10-26)

With built-in bounds (0, 0, 2056, 1329) and HP E233 bounds
(2056, -210, 1920, 1080), the built-in right midpoint is a shared seam.
Placement now chooses the longest exposed edge segment instead; here that
point is (2055, 1099.5). A native probe still could not move the right Dock
from HP E233 to the built-in display at this point. This method therefore
does not establish support for arbitrary side placement in this arrangement.

Orientation changes now restore the previous orientation and pinned display
when relocation fails. Profile activation restores the previous settings and
display on failure as well. Placement waits for Dock accessibility geometry
after restart before attempting the auto-hide shortcut.

The installed, development-signed app was exercised through its real AX menu:
starting at Bottom on Built-in Retina Display, requesting Right returned to
Bottom on Built-in Retina Display, kept the stored pin, and restored the
pointer coordinates. Nine offline geometry checks pass, including choosing
an exposed segment and rejecting a fully covered edge. Profile rollback has
build validation but has not been exercised through the installed profile UI.
