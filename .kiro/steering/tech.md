# Tech Stack

## Platform
- **Language**: Swift 5.9
- **UI Framework**: SwiftUI
- **Minimum iOS**: 17.0
- **IDE**: Xcode 15+

## Dependencies
| Package | Version | Purpose |
|---------|---------|---------|
| Lottie (Airbnb) | 4.4.0+ | Animation library |

## Package Management
Swift Package Manager (SPM) - dependencies auto-download on first build.

### Manual Dependency Addition
1. Xcode → File → Add Package Dependencies
2. Enter package URL
3. Select version

## Build & Run
```bash
# Open project
open BadmintonBuddy-iOS/BadmintonBuddy.xcodeproj

# Build: Cmd + B
# Run: Cmd + R
# Test: Cmd + U
```

## Performance Targets
| Animation | FPS | Memory |
|-----------|-----|--------|
| Card collision | 60 | < 50MB |
| Pulse search | 60 | < 30MB |
| Page transitions | 60 | < 20MB |

## Animation Timing Constants
- Fast (button feedback): 0.2s
- Normal (page transitions): 0.3s
- Slow (complex animations): 0.5s
- Collision effect: 0.7s

## Accessibility
- WCAG 2.1 AA compliant
- Color contrast ratio ≥ 4.5:1 (primary/background)
- Dark mode only (`.preferredColorScheme(.dark)`)
