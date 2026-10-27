# Dock geometry regression checks

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
