# Dlock

A simple macOS menu bar app to pin the Dock to a specific screen. Automatically falls back to the main display if the pinned screen is disconnected.

## Features

- **Pin to Screen** — Keep the Dock on any connected display
- **Auto Fallback** — If the pinned screen disconnects, the Dock returns to the main display
- **Orientation** — Switch between Bottom, Left, and Right dock positions
- **Auto-hide** — Toggle Dock auto-hide from the menu
- **Profiles** — Save and switch between named screen + orientation presets
- **Keyboard Shortcut** — `⌃⌥D` opens the Dlock menu from anywhere
- **Launch at Login** — Start Dlock automatically on login

## Requirements

- macOS 13.0 (Ventura) or later

## Building

1. Open the project:
   ```
   open Dlock.xcodeproj
   ```
2. Select the **Dlock** scheme and **Debug** configuration
3. Press **⌘R** to build and run

> Note: The keyboard shortcut requires **Accessibility permission** — macOS will prompt you the first time you use it.

## Keyboard Shortcut

- `⌃⌥D` — Open the Dlock menu
