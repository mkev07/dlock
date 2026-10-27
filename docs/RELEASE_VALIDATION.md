# Dlock release validation

Run this checklist on the exact Release app intended for distribution. Record the macOS version, Dlock version, display models, Dock edge, and result for each row. A Debug build or synthetic pointer probe is useful engineering evidence, but does not replace these user-level checks.

## Before each run

1. Connect at least two displays and grant Dlock Accessibility access.
2. In Dlock, pin the display that should keep the Dock.
3. Open **Live Lock Diagnostics**. Confirm it says **ACTIVE**, names the pinned display, and lists the other display's guarded edge.
4. Confirm the Dock is currently on the pinned display.

## Scenarios

For each connected display, move the pointer to the middle of each listed exposed guarded edge and hold it there briefly. Avoid edge portions where displays touch; those are not exposed edges and should not be guarded. Confirm the diagnostics counter increases and the Dock remains on the pinned display. Then move to the pinned display's Dock edge and confirm the Dock remains usable there.

| Scenario | Expected result | Observed / notes |
| --- | --- | --- |
| Select another display | Dock moves automatically; pointer returns; no Verify dialog | |
| Current layout, exposed edge(s) | Counter increases; Dock stays pinned | |
| Dock position | No position control; profile activation preserves the macOS orientation; left/right use native macOS placement | |
| Auto-hide On, then Off | Switch matches macOS after each change; Dock stays on the preferred external display; Dock returns to visible when Off; no screen-placement prompt appears | |
| Displays arranged side by side | Only exposed portions of the trigger edge are protected | |
| Displays vertically offset | Exposed trigger edge portions are protected | |
| Sleep, then wake with displays connected | Guard returns active; Dock stays pinned | |
| Disconnect and reconnect the pinned display | Clear inactive state while absent; guard resumes after reconnect | |
| Disconnect and reconnect an unpinned display | Guard zones refresh to match the new layout | |
| Accessibility permission revoked and restored | Clear inactive state; guard resumes after relaunch/permission flow | |

Repeat the key edge checks with Option held; Dlock intentionally bypasses its guard while Option is held.

## Release gate

- No scenario leaves diagnostics saying ACTIVE when no edge zones are guarded or the event tap is unavailable.
- No tested unpinned edge moves the Dock away from the pinned display.
- The pinned display's Dock edge remains usable.
- App bundle is built in Release configuration, signed with the intended Developer ID, notarized, stapled, and verified on a clean macOS user account.
- Version, support contact, privacy disclosures, license, and update delivery are set for the sale channel.
