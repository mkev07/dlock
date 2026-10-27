# Dlock

A lightweight macOS menu bar app that prevents the Dock from following your pointer onto other displays.

## Features

- **Select a Display** — Automatically move the bottom Dock to a connected display, then protect its exposed edge
- **Prevent Dock Hopping** — Blocks the edge gesture that normally summons the Dock on non-pinned displays
- **Stationary Cursor Presentation** — Keeps the cursor visually in place during automatic placement and restores the real pointer afterward; edge protection nudges input inward by a few pixels
- **Temporary Bypass** — Hold `⌥ Option` when you intentionally want to move the Dock
- **Reconnect Memory** — Keeps the preferred display UUID when a screen disconnects and resumes protection when it returns
- **Detached Controls** — A movable window with an animated display map and compact display labels
- **Auto-hide** — Toggle Dock auto-hide from the controls window
- **Profiles** — Save and switch between named presets (screen + auto-hide)
- **Notifications** — Get notified when a screen disconnects or a profile is activated
- **Reset to Main Display** — Moves the Dock to the primary display, then clears the pin
- **Menu Bar Icon** — Choose between the default icon or the Dlock app logo
- **Show in Dock** — Optionally show Dlock in the Dock alongside the menu bar icon
- **Keyboard Shortcut** — `⌃⌥D` opens the Dlock controls
- **Launch at Login** — Start Dlock automatically on login
- **Update Check** — Checks GitHub on launch and opens the release page when a newer version is found; updates are downloaded manually

## Requirements

- Deployment target: macOS 13.0 (Ventura) or later. Compatibility across all supported versions is not yet validated.
- Two connected displays for Dock locking; Accessibility permission is required.
- Current locally tested builds are Apple Silicon. Intel support has not been validated.

## Building

1. Generate the Xcode project from `project.yml`:
   ```
   xcodegen generate
   ```
2. Open the project:
   ```
   open Dlock.xcodeproj
   ```
3. Select the **Dlock** scheme and **My Mac** destination
4. Press **⌘B** to build, or **⌘R** to build and run

> **Accessibility permission** — Dock edge protection and the global keyboard shortcut require Accessibility access. Dlock opens the Accessibility pane with a floating guide that lets you drag Dlock into the permission list. You can reopen the guide with **Grant Accessibility Access** in the controls window when access is missing.

## Usage

1. Click the menu bar icon to open the detached controls window. Select a display in the illustration or the **Displays** list.
2. Dlock automatically summons the Dock on that display and verifies its location. The cursor stays visually in place while Dlock sends a short synthetic edge gesture, then restores the real pointer. Real mouse input cancels placement safely.
3. Dlock blocks the Dock-triggering edge on other displays and attempts to restore placement after changing auto-hide or profiles, and when the preferred display reconnects.

Hold `⌥ Option` while moving against another display edge to bypass the lock temporarily.

## How It Works

Dlock cannot permanently assign the Dock to an arbitrary display through a public macOS API. Instead, it installs a Quartz `CGEventTap` and guards the exposed Dock edge of every non-pinned display. Mouse movement remains unchanged everywhere except the final few pixels of those edges, where Dlock nudges the event inward before macOS can summon the Dock.

Edges shared with another display are excluded from protection, so the pointer can still cross normally between stacked or side-by-side screens. Accessibility is also used to verify which display currently contains the Dock when changing pins or profiles.

Display preferences use the display UUID provided by macOS rather than the temporary display number assigned at connection time, so pins and profiles remain stable across normal reconnects and restarts.

The prevention approach is inspired by the public-API implementations in [DockPin](https://github.com/metikadriu/DockPin) and [DockDoor](https://github.com/ejbills/DockDoor).

## Distribution

This is a development build, not a sale-ready release. For direct distribution, archive a Release build, sign it with the intended Developer ID Application identity, enable Hardened Runtime and a secure timestamp, notarize it, and staple and verify the ticket. Test the downloaded package on a clean macOS account. Local development signing is not distribution signing.

See [release validation](docs/RELEASE_VALIDATION.md) for the acceptance checklist. Rebuilding or moving development copies can cause macOS to request Accessibility permission again.

## Keyboard Shortcut

| Shortcut | Action |
|----------|--------|
| `⌃⌥D` | Open the Dlock controls |

## Current Limits and Pending Fixes

- Automatic display relocation has been validated for the **bottom Dock** in the connected test setup. Position controls are omitted from this build. Change Dock position in macOS System Settings; left/right placement follows native macOS behavior and cannot be assigned freely to every screen.
- Quit **DockLock Lite** before switching displays with Dlock. Running both caused placement failures; Dlock detects this conflict and displays a message.
- The current “locked” status reflects an active edge guard, not continuous verification that the Dock is on the selected display. Improving this status is pending.
- Refreshing protection after external Dock-position changes, keyboard-listener event ownership/recovery, accurate Launch at Login status, update-check failure reporting, and reconnect notification text still need fixes.
- Sleep/wake, reconnects, permission revocation, and first-run installation must be validated on the final distribution build. Passing the local build or geometry checks does not establish compatibility with every display layout or macOS version.

## Validation

Run the offline checks using [Tests/README.md](Tests/README.md). They cover Dock geometry and exposed-edge placement points; they do not exercise the live pointer guard or prove release readiness.

See [the placement investigation](docs/DOCK-PLACEMENT-INVESTIGATION.md) for implementation evidence and known side-placement limits.
