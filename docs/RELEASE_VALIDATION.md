# Dlock release validation

Run this checklist on the exact Release app intended for distribution. Record the macOS version, Dlock version, display models, Dock edge, and result for each row. A Debug build or synthetic pointer probe is useful engineering evidence, but does not replace these user-level checks.

## Before each run

1. Connect at least two displays and grant Dlock Accessibility access.
2. In Dlock, pin the display that should keep the Dock.
3. Confirm the Dock is currently on the pinned display.

## Scenarios

For each connected display, move the pointer to the middle of each exposed guarded edge and hold it there briefly. Avoid edge portions where displays touch; those are not exposed edges and should not be guarded. Confirm visually that the Dock remains on the pinned display. Then move to the pinned display's Dock edge and confirm the Dock remains usable there.

| Scenario | Expected result | Observed / notes |
| --- | --- | --- |
| Dock location differs from selection | Warning replaces locked status; selection stays saved; Dock bar shows detected location | |
| Dock location cannot be read | Warning; no confirmed lock badge and no invented Dock bar | |
| Select another display | Dock moves automatically; pointer returns; no Verify dialog | |
| Current layout, exposed edge(s) | Dock stays pinned; controls show confirmed protection | |
| Dock position | Position controls reflect macOS; profile activation preserves orientation; left/right use native macOS placement | |
| Auto-hide On, then Off | Switch matches macOS after each change; Dock stays on the preferred external display; Dock returns to visible when Off; no screen-placement prompt appears | |
| Displays arranged side by side | Only exposed portions of the trigger edge are protected | |
| Displays vertically offset | Exposed trigger edge portions are protected | |
| Sleep, then wake with displays connected | Guard returns active; Dock stays pinned | |
| Disconnect and reconnect the pinned display | Clear inactive state while absent; guard resumes after reconnect | |
| Disconnect and reconnect an unpinned display | Guard zones refresh to match the new layout | |
| Accessibility permission revoked and restored | Clear inactive state; guard resumes after relaunch/permission flow | |

Repeat the key edge checks with Option held; Dlock intentionally bypasses its guard while Option is held.

## Window and icon acceptance

- Launch Dlock from Applications or Spotlight: the detached controls and Dock
  icon appear. Opening Dlock again brings the existing controls forward.
- Close the controls with the close button: the Dock icon disappears, the app
  keeps running, and Dock protection continues. Repeat via the menu bar icon.
- Disable Settings → Show Menu Bar Icon: the menu bar icon disappears while
  the open controls and Dock icon remain. Close controls, then reopen Dlock
  from the launcher; controls and Dock icon return without the menu bar icon.
- Quit and launch with the menu bar icon hidden: controls open and the setting
  stays hidden. Re-enable the menu bar icon through Settings.
- Launch at Login should keep the controls and Dock icon hidden for a valid
  saved activation. This still requires a real logout/login acceptance check.

## Display layout guidance acceptance

- With aligned stacked displays, selecting the blocked upper display opens its
  layout explanation without moving the real pointer.
- The popover arrow lines up with the layout-tip chevron.
- Current arrangement and Suggested layout tabs animate only the diagram.
  The edge-colour key is centred inside the illustration box below the screens,
  with no overlap in either tab. Screen numbers
  match the main Displays list without repeating its names in the popover.
  The selected tab uses a glass pill and the popover hides background content.
  The indicated exposed edge must match the suggested left/right offset.
- With Reduce Motion enabled, the diagram changes without sliding screens.
- Open Displays opens the settings pane without changing the arrangement.
  After a manual offset, retry selects the intended display and verifies it.
- Already offset and wider upper displays do not receive a false blocked-edge
  warning. A third display must not overlap a suggested position.
- Disconnecting a display or changing arrangement while help is open must not
  leave stale controls or an incorrectly sized panel.
- With Separate Spaces off, the app offers the Desktop & Dock settings shortcut
  without claiming it has changed or worked around the setting.

These checks are pending live acceptance; automated layout checks cover the
geometry and never change actual screen arrangements.

## Release gate

- No scenario reports confirmed protection when no edge zones are guarded or the event tap is unavailable.
- No tested unpinned edge moves the Dock away from the pinned display.
- The pinned display's Dock edge remains usable.
- App bundle is built in Release configuration, signed with the intended Developer ID, notarized, stapled, and verified on a clean macOS user account.
- Version, support contact, privacy disclosures, license, and update delivery are set for the sale channel.

## Verified-status development check (2026-10-27)

The development-signed installed app was exercised through its real controls
on the connected Built-in Retina Display / HP E233 setup with the bottom Dock:

- Selected HP E233 and confirmed the locked status.
- Moved the actual Dock to the built-in screen without changing the saved pin.
- The visible controls refreshed to a wrong-screen warning, kept HP E233
  selected, labeled the built-in screen as the actual Dock location, and
  removed the false locked row label.
- Selected HP E233 again; placement and confirmed status returned. The pointer
  was restored.

Nine offline status cases also cover an unreadable Dock location and an
inactive guard. Those cases do not replace live Accessibility-permission
revocation or final-release acceptance. Illustration timing and drawing are
unchanged; only its Dock-location input now uses the observed screen.
