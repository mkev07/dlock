# Dlock

A lightweight macOS menu bar app to pin the Dock to a specific screen. Automatically falls back to the main display if the pinned screen is disconnected.

## Features

- **Pin to Screen** — Keep the Dock on any connected display
- **Auto Fallback** — If the pinned screen disconnects, the Dock returns to the main display automatically
- **Orientation** — Switch between Bottom, Left, and Right dock positions
- **Auto-hide** — Toggle Dock auto-hide from the menu
- **Profiles** — Save and switch between named presets (screen + orientation + auto-hide)
- **Notifications** — Get notified when a screen disconnects or a profile is activated
- **Reset to Main Display** — Instantly return the Dock to the main display and clear the pinned screen
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

> **Accessibility permission** — The global keyboard shortcut requires Accessibility access. macOS will prompt you the first time you use it.

## Keyboard Shortcut

| Shortcut | Action |
|----------|--------|
| `⌃⌥D` | Open the Dlock menu |
