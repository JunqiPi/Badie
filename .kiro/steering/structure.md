# Project Structure

```
BadmintonBuddy-iOS/
├── BadmintonBuddy.xcodeproj/         # synchronized groups + shared scheme
├── BadmintonBuddy/
│   ├── App/            # @main, AppState, Router, RootView, MainTabView, RouteDestination, DemoLauncher
│   ├── DesignSystem/   # Theme tokens, surfaces, buttons, identity (avatar/badges/chips), shapes, feedback, FlowLayout
│   ├── Models/         # User, Reputation, Court, TimeSlot, Game, Room, Messaging, Social, Survey, Geo
│   ├── Services/       # MatchingService, Backend/ (MockBackend + extensions), ReminderService, MapsLauncher, Persistence
│   ├── Managers/       # LocationManager, MatchManager, RoomManager, Friend/Message/Inbox/Survey managers
│   ├── Features/       # Onboarding, Home, Matching, Games, Rooms, Courts, Messages, Social, Surveys, Profile
│   └── Assets.xcassets
├── BadmintonBuddyTests/ # Models, MatchingService, MockBackend, PersistenceService
├── docs/DESIGN.md       # design process, research, tokens, IA, requirement mapping
└── scripts/             # CI helpers (simulator picker, screenshots)
```

## Conventions
- One feature folder per tab/flow; shared UI goes to DesignSystem
- Use `AppTheme` tokens only — no hard-coded colours except `onAccent` ink on accents
- Text on accent fills always uses `AppTheme.Colors.onAccent`
- Chinese comments for business rules; user-facing copy in Simplified Chinese
