# Project Structure

```
BadmintonBuddy-iOS/
├── BadmintonBuddy.xcodeproj/     # Xcode project config
├── BadmintonBuddy/
│   ├── BadmintonBuddyApp.swift   # @main entry + AppState (global state)
│   ├── ContentView.swift         # Root view router (screen switching)
│   ├── Models.swift              # Data models (User, SkillLevel, GameMode)
│   ├── Theme.swift               # Design system tokens (colors, fonts, spacing)
│   ├── Components.swift          # Reusable UI components
│   ├── Package.swift             # SPM dependencies
│   ├── Views/
│   │   ├── SplashView.swift      # Launch animation
│   │   ├── AuthView.swift        # Login/registration
│   │   ├── HomeView.swift        # Main screen (map + mode selection)
│   │   ├── MatchingView.swift    # Matching in progress
│   │   ├── MatchSuccessView.swift# Match result with effects
│   │   └── ProfileView.swift     # User profile
│   └── Assets.xcassets/          # Images, colors, app icon
└── README.md
```

## Architecture Pattern
- **State Management**: `@StateObject` + `@EnvironmentObject` (AppState)
- **Navigation**: Enum-based screen routing in ContentView
- **UI**: Declarative SwiftUI with design token system

## Key Files

### AppState (BadmintonBuddyApp.swift)
Central state manager with `@Published` properties:
- `currentScreen`: Navigation state
- `currentUser`: Logged-in user
- `selectedMode`: Singles/Doubles
- `matchedOpponent`: Match result
- `isMatching`: Matching status

### Theme.swift
Design tokens organized as enums:
- `Colors`: Primary (#00D4AA), Secondary (#6C5CE7), backgrounds
- `Typography`: Font sizes and weights
- `Spacing`: xs(4) → xxl(48)
- `Radius`: Corner radius values
- `Animation`: Duration constants

### Components.swift
Reusable components:
- `PrimaryButton`, `SecondaryButton`
- `AppTextField`
- `AvatarView`, `CardView`
- `PlayerCard`, `ModeCard`
- Animation components (`PulseDot`, `SearchingRing`)

## Conventions
- Views in `/Views` folder
- One view per file
- Chinese comments for business logic
- Preview providers at bottom of view files
