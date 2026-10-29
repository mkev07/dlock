# Dlock regression checks

## About flag tooltip checks

These offline checks verify Mauritius time formatting without opening a window:

```sh
xcrun swiftc -parse-as-library Sources/App/AboutFlagTooltip.swift \
  Tests/AboutFlagTooltipChecks.swift -o /tmp/dlock-about-tooltip-checks
/tmp/dlock-about-tooltip-checks
```

Instant hover behavior and placement above the flag still need native UI validation.

## Licensing checks

Run `npm ci --prefix Backend` and `npm --prefix Backend test` for local server,
provider-fixture, one-Mac transfer/concurrency, webhook verification/replay, and
pricing-boundary tests. These do not make Dodo API calls or accept payments.

```sh
license_sources=(Sources/App/Licensing/LicenseManager.swift Sources/App/Licensing/LicenseEntitlement.swift)
xcrun swiftc -D DEBUG -parse-as-library "${license_sources[@]}" \
  Tests/LicenseResponseChecks.swift -o /tmp/dlock-license-response-checks
/tmp/dlock-license-response-checks
xcrun swiftc -D DEBUG -parse-as-library "${license_sources[@]}" \
  Tests/LicenseTestSupport.swift Tests/LicenseManagerChecks.swift -o /tmp/dlock-license-manager-checks
/tmp/dlock-license-manager-checks
xcrun swiftc -D DEBUG -parse-as-library "${license_sources[@]}" \
  Tests/LicenseTestSupport.swift Tests/LicenseOfflineChecks.swift -o /tmp/dlock-license-offline-checks
/tmp/dlock-license-offline-checks
xcrun swiftc -parse-as-library "${license_sources[@]}" \
  Tests/LicenseReleaseChecks.swift -o /tmp/dlock-license-release-checks
/tmp/dlock-license-release-checks
node Tests/LicenseInteropFixture.mjs > /tmp/dlock-entitlement-interop.json
xcrun swiftc -D DEBUG -parse-as-library "${license_sources[@]}" \
  Tests/LicenseInteropChecks.swift -o /tmp/dlock-license-interop-checks
/tmp/dlock-license-interop-checks /tmp/dlock-entitlement-interop.json
```

The client tests inject memory storage and responses: they do not change real
Keychain items, activate licenses, or change installed-app settings. See
`Backend/README.md` for running the explicit local simulator and production gates.
Offline checks cover daily scheduling, restart caching, exact expiry, HTTP and
network outages, tampering, signature/key/binding failures, nonce replay, clock
rollback and storage failures. Release checks compile without `DEBUG` and
assert that test configuration never sends a licensing request. Tests advance
an injected clock; they do not change your Mac's clock or wait for 30 real days.

These checks are offline: they do not move the pointer, launch Dlock, or change
Dock settings. Run from the repository root:

```sh
xcrun swiftc -parse-as-library \
  Sources/App/DockController.swift \
  Sources/App/DockGuardian.swift \
  Sources/App/ScreenManager.swift \
  Sources/App/ProfileManager.swift \
  Sources/App/DockProfile.swift \
  Sources/App/DockOrientation.swift \
  Sources/App/AccessibilityPermission.swift \
  Tests/DockGeometryChecks.swift \
  -o /tmp/dlock-geometry-checks
/tmp/dlock-geometry-checks
```

Connected-display validation is documented in `docs/RELEASE_VALIDATION.md`.

## Keyboard shortcut checks

These offline checks exercise modifier matching, event forwarding, disabled-tap
notifications, and repeat suppression without registering a live event tap or
posting keyboard input. Actual tap recovery still requires a live test.

```sh
xcrun swiftc -parse-as-library Sources/App/HotkeyManager.swift \
  Tests/HotkeyChecks.swift -o /tmp/dlock-hotkey-checks
/tmp/dlock-hotkey-checks
```

## Reconnect notification checks

These check notification text without requesting permission or delivering notifications:

```sh
xcrun swiftc -parse-as-library Sources/App/NotificationManager.swift \
  Tests/ReconnectMessageChecks.swift -o /tmp/dlock-reconnect-checks
/tmp/dlock-reconnect-checks
```

## Inline updater checks

These use release fixtures and an injected transport, without network requests,
browser launches, downloads, or installation:

```sh
xcrun swiftc -parse-as-library UpdateChecker.swift Tests/UpdateChecks.swift \
  -o /tmp/dlock-update-checks
/tmp/dlock-update-checks
```

## Login item checks

Login item checks use an injected service and do not register or remove real login items:

```sh
xcrun swiftc -parse-as-library Sources/App/LaunchAtLoginManager.swift \
  Tests/LaunchAtLoginChecks.swift -o /tmp/dlock-login-checks
/tmp/dlock-login-checks
```

## Lock status checks

These offline checks verify that an active guard alone cannot produce a locked
status. They cover matched, mismatched and unknown Dock locations, missing
permission, no pin, disconnected displays, and single-display mode.

```sh
xcrun swiftc -parse-as-library \
  Sources/App/Views/DlockPanelModel.swift \
  Sources/App/DockOrientation.swift \
  Tests/LockStatusChecks.swift -o /tmp/dlock-lock-status-checks
/tmp/dlock-lock-status-checks
```
