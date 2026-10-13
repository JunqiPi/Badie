# Tech Stack

- Swift 5 language mode, SwiftUI, iOS 17.0+
- Xcode 16+ (project uses file-system synchronized groups — new files are picked up automatically)
- Frameworks: SwiftUI, MapKit, CoreLocation, UserNotifications, EventKitUI, PhotosUI
- No third-party dependencies

## Build & Test
```bash
open BadmintonBuddy-iOS/BadmintonBuddy.xcodeproj   # ⌘R run, ⌘U test
```
CI: `.github/workflows/ios.yml` builds, runs unit tests and captures light/dark screenshots via the DEBUG launch argument `-BBDemoScreen <screen>`.

## State
- `@MainActor` `ObservableObject` managers injected with `@EnvironmentObject`
- `MockBackend` is the single source of truth; managers subscribe to `BackendEvent`s
- Pure, testable `MatchingService`

## Accessibility
- WCAG 2.1 AA contrast (see docs/DESIGN.md), Dynamic Type via text styles / `@ScaledMetric`
- Reduce Motion respected; 44pt minimum targets; VoiceOver labels/traits
- Light and dark appearance (user can override in Settings)
