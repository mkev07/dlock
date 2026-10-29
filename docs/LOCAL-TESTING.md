# Local Dlock testing

Open `/Applications/Dlock.app`, then click its menu bar icon. The installed app
is a development-signed Debug build of the current checkout.

The licensing simulator must be running for activation and online validation:

```sh
cd '/Users/kevin/Vibe Code/Dlock/Backend'
npm start
```

It listens only on `127.0.0.1:8787`. If already running, do not start a second
copy. Settings → License accepts the public fixture `DLOCK-LOCAL-TEST-ONLY`.
Use Check Validity for a saved activation. This simulator accepts no payments.

The website preview is at http://localhost:3002. To restart it if needed:

```sh
cd '/Users/kevin/Vibe Code/Dlock/Website/nextjs'
npm run dev
```

## Window and app icons

Opening Dlock from Applications, Spotlight, or the app launcher opens the
controls and shows the Dock icon. Closing the controls hides the Dock icon;
Dlock continues running and protecting the selected display.

Settings → Show Menu Bar Icon controls whether the menu bar icon is visible.
When hidden, reopen Dlock from the launcher to reach the controls and Settings.
The choice survives quitting and relaunching. The old Show Dlock in Dock toggle
is replaced by automatic visibility while the controls are open.

## Hands-on checks

1. Select the built-in screen. Confirm the actual Dock appears there and the
   app reports protection. Hold the pointer against another screen's exposed
   bottom edge; the Dock should stay on the selected screen.
2. With the HP E233 directly above the built-in screen, select HP E233. Its
   fully covered bottom edge should open the layout explanation.
3. Switch between Current arrangement / Suggested layout tabs. Only the diagram should
   move. Check that Open Displays opens System Settings.
4. In System Settings, manually offset the upper screen sideways enough to
   expose part of its bottom edge. Return to Dlock and use Retry display.
   Confirm the Dock moves to HP E233 and the status matches its real location.
5. Try auto-hide, profiles, Option bypass, and disconnect/reconnect. Confirm
   the Dock stays usable on the selected screen and warnings match reality.
6. Try the diagram with macOS Reduce Motion enabled. Restore your preferences
   and display arrangement when finished.

See [release validation](RELEASE_VALIDATION.md) for the full manual checklist
and [automated checks](../Tests/README.md) for repeatable offline checks.
Automated checks do not establish live Dock behavior or distribution readiness.
