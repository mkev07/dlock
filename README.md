# Dlock

A lightweight macOS menu bar app that prevents the Dock from following your pointer onto other displays.

## Features

- **Pin to Screen** — Keep the Dock on any connected display
- **Prevent Dock Hopping** — Blocks the edge gesture that normally summons the Dock on non-pinned displays
- **No Cursor Warping** — Nudges the pointer inward by only a few pixels at guarded Dock edges
- **Temporary Bypass** — Hold `⌥ Option` when you intentionally want to move the Dock
- **Reconnect Memory** — Keeps the preferred display UUID when a screen disconnects and resumes protection when it returns
- **Orientation** — Switch between Bottom, Left, and Right dock positions
- **Auto-hide** — Toggle Dock auto-hide from the menu
- **Profiles** — Save and switch between named presets (screen + orientation + auto-hide)
- **Notifications** — Get notified when a screen disconnects or a profile is activated
- **Reset to Main Display** — Guides you to place the Dock on the primary display, then clears the pin
- **Menu Bar Icon** — Choose between the default icon or the Dlock app logo
- **Show in Dock** — Optionally show Dlock in the Dock alongside the menu bar icon
- **Keyboard Shortcut** — `⌃⌥D` opens the Dlock menu from anywhere
- **Launch at Login** — Start Dlock automatically on login
- **Auto Update Check** — Silently checks GitHub for a new release on launch; "Check for Updates..." in the menu always reports the result

## Requirements

- macOS 13.0 (Ventura) or later

## Building

1. Open the project:
   ```
   open Dlock.xcodeproj
   ```
2. Select the **Dlock** scheme and **Debug** configuration
3. Press **⌘R** to build and run

> **Accessibility permission** — Dock edge protection and the global keyboard shortcut require Accessibility access. Dlock opens the Accessibility pane with a floating guide that lets you drag Dlock into the permission list. You can reopen the guide from the menu bar under **Grant Accessibility Access**.

## Usage

1. Open **Pin to Screen** and select your preferred display.
2. If the Dock is currently elsewhere, Dlock pauses protection and asks you to move the pointer to the chosen display's Dock edge once.
3. Click **Verify** after the Dock appears there.
4. Dlock then blocks the Dock-triggering edge on every other display.

Hold `⌥ Option` while moving against another display edge to bypass the lock temporarily.

## How It Works

Dlock cannot permanently assign the Dock to an arbitrary display through a public macOS API. Instead, it installs a Quartz `CGEventTap` and guards the exposed Dock edge of every non-pinned display. Mouse movement remains unchanged everywhere except the final few pixels of those edges, where Dlock nudges the event inward before macOS can summon the Dock.

Edges shared with another display are excluded from protection, so the pointer can still cross normally between stacked or side-by-side screens. Accessibility is also used to verify which display currently contains the Dock when changing pins or profiles.

Display preferences use the display UUID provided by macOS rather than the temporary display number assigned at connection time, so pins and profiles remain stable across normal reconnects and restarts.

The prevention approach is inspired by the public-API implementations in [DockPin](https://github.com/metikadriu/DockPin) and [DockDoor](https://github.com/ejbills/DockDoor).

## Distribution

For reliable Accessibility permission and Launch at Login behavior, archive and sign a Release build with a stable Developer ID identity. Rebuilding or moving unsigned development copies can cause macOS to request Accessibility permission again.

## Keyboard Shortcut

| Shortcut | Action |
|----------|--------|
| `⌃⌥D` | Open the Dlock menu |
