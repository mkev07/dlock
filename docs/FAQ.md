# Dlock questions and troubleshooting

Dlock is a development build. These answers describe the current implementation;
they are not a claim of compatibility with every Mac or display arrangement.

## Can I keep the Dock on an upper, stacked display?

The bottom Dock needs an exposed part of that display's bottom edge. If another
display covers the entire edge in macOS's arrangement, Dlock cannot summon the
Dock there with its current placement method. A wider upper display or an upper
display offset sideways can already have a usable edge.

Open Dlock's layout tip beneath the display map. It checks your actual screen
geometry and can illustrate a left or right offset. Open System Settings →
Displays → Arrange and move the upper display sideways until part of its bottom
edge is exposed, then retry that screen in Dlock. You do not need to abandon a
stacked arrangement. The illustration does not rearrange your screens for you.

## Why does Dlock mention Separate Spaces?

Dlock reads macOS's Separate Spaces status without changing it. If it is off,
per-display Dock placement may not work as expected. Check System Settings →
Desktop & Dock → Mission Control → Displays have separate Spaces. Follow any
macOS sign-out instruction after changing it. Behavior with this setting disabled
has not been validated; Dlock does not promise to bypass that limitation.

## Can I put a vertical Dock on any screen?

You can change the Dock's position to Left, Bottom, or Right. These actions change
the macOS setting and restart the Dock. Bottom placement is the tested locking
path. Left and right display selection still follows macOS's rules; Dlock cannot
promise to place a vertical Dock on an interior edge of any arbitrary screen.

## Why does it need Accessibility access?

Dlock uses Accessibility and an input event tap to guard the Dock-triggering
edges and verify the Dock's display. Automatic placement sends a short synthetic
pointer gesture, keeps the cursor visually in place, and restores it afterward.
Real pointer input cancels placement. Current Dlock locking requires permission;
it is not a permission-free implementation.

## Can I move the Dock temporarily?

Hold Option while moving to another screen's Dock edge to bypass the guard.
Turn Dock Lock off to clear the pin and resume normal behavior. These are
different from changing the saved preferred screen in Dlock.

## What happens after disconnecting a monitor or closing the laptop?

Dlock retains the preferred display's UUID and attempts to restore placement
when that screen returns. It does not yet store a separate automatic preference
for every combination of monitors or laptop-lid state. Profiles are manually
selected presets for a screen and auto-hide setting. Reconnect and sleep/wake
behavior still need acceptance checks on the final distribution build.

## What if the Dock does not move?

Check Accessibility access, whether the selected screen is still connected, and
the layout tip. Quit another Dock-locking utility before retrying. Close macOS
menus and leave the pointer still briefly, then select the display again.
Dlock cancels placement when real input interrupts it; it does not yet queue an
automatic retry after every interruption. A selected screen is not proof of
success: Dlock only reports Locked after observing the Dock on that display and
confirming that its guard is active.

## Does auto-hide work?

Dlock can change macOS auto-hide and saves it in profiles. Keep a reachable
display selected. It is not currently a hide-everywhere presentation mode, and
it should not be advertised as a guarantee that the Dock can never appear while
screen sharing or using full-screen apps.

## Can I prevent accidentally resizing the Dock?

Use Lock Dock size below Auto-hide. Changing it saves macOS's size-lock
preference, restarts the Dock, and attempts to restore its preferred display.
The setting remains after Dlock quits; turn it off before resizing again. This
does not freeze icon magnification, app counts, screen scaling, or the Dock's
overall visible width. Live divider-drag validation is still pending.

## Does Dlock work with Sidecar, AirPlay, DisplayLink or a docking station?

Dlock uses displays that macOS exposes through its screen APIs. Those setups are
candidates for testing, not certified compatibility claims. Mirroring does not
provide independent extended desktops. Validate the exact adapter, driver,
display mode and macOS version before relying on them.

## Will Cmd-Tab always appear on the pinned screen?

Dlock manages the Dock, not the system app switcher. Cmd-Tab display selection
is controlled by macOS and can vary by system version and focus. Pinning the Dock
is not a promise to relocate Cmd-Tab.

## Is it offline? Is there a trial?

There is no trial. Activation and periodic validation require a connection to the
configured licensing service. A verified signed entitlement permits up to 30 days
offline, with daily rechecks while online. The current backend is a local test or
Dodo sandbox service; production activation and checkout are not launched.

## Can I transfer a license?

Each license is intended for one active Mac. Deactivate it on the old Mac before
activating the other. The transfer interface is implemented against the test
licensing service; production provider acceptance is still pending.

## What remains after I quit Dlock?

The pointer guard stops, so ordinary Dock switching resumes. Native Dock
preferences you changed, including position, auto-hide and size lock, remain.
Disable size lock before removing Dlock if you want divider resizing restored.

## Does it modify system files or require disabling SIP?

Dlock does not patch system files or require disabling System Integrity
Protection. It does write normal Dock preferences for controls such as position
and size lock. Its Accessibility and input-monitoring implementation is distinct
from its licensing network requests; do not describe the app as having no network
access.

## Which Macs are supported?

The project targets macOS 13 and later. Current local builds are tested on Apple
Silicon; Intel, other macOS versions, display drivers, full-screen workflows and
final signed distribution still need their own validation. Build success is not
a compatibility certification.
