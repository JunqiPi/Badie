# Implementation Plan: BadmintonBuddy v2.0 Upgrade

## Overview

This implementation plan breaks down the BadmintonBuddy v2.0 upgrade into discrete, incremental coding tasks. Each task builds on previous work and includes property-based tests where applicable. The plan follows the existing SwiftUI architecture with @StateObject/@EnvironmentObject state management.

## Tasks

- [x] 1. Set up project infrastructure and core protocols
  - [x] 1.1 Add SwiftCheck dependency to Package.swift for property-based testing
    - Add SwiftCheck 0.14.0+ via SPM
    - Configure test target to include SwiftCheck
    - _Requirements: Testing Strategy_
  
  - [x] 1.2 Create core service protocols in new Services/ directory
    - Create `Services/Protocols/LocationServiceProtocol.swift`
    - Create `Services/Protocols/MatchingServiceProtocol.swift`
    - Create `Services/Protocols/MessageServiceProtocol.swift`
    - Create `Services/Protocols/SurveyServiceProtocol.swift`
    - Create `Services/Protocols/RoomServiceProtocol.swift`
    - Create `Services/Protocols/PersistenceServiceProtocol.swift`
    - _Requirements: Architecture design_
  
  - [x] 1.3 Create feature manager stubs in Managers/ directory
    - Create `Managers/LocationManager.swift` with @Published properties
    - Create `Managers/FriendManager.swift` with @Published properties
    - Create `Managers/MessageManager.swift` with @Published properties
    - Create `Managers/RoomManager.swift` with @Published properties
    - Create `Managers/SurveyManager.swift` with @Published properties
    - Wire managers into AppState as @StateObject
    - _Requirements: Architecture design_

- [x] 2. Implement enhanced data models
  - [x] 2.1 Update User model with 9-tier skill system and reputation
    - Add `selfReportedLevel: Int` (1-9)
    - Add `calculatedLevel: Double` for weighted average
    - Add `verificationStatus: VerificationStatus` enum
    - Add `reputation: ReputationScore` struct
    - Add `location: Coordinate?` and `lastLocationUpdate: Date?`
    - Implement `displayLevel` computed property (30% self + 70% peer)
    - _Requirements: 2.1, 2.6, 2.7_
  
  - [ ]* 2.2 Write property test for skill level calculation
    - **Property 3: Weighted Skill Level Calculation**
    - Generate users with 5+ evaluations, verify formula: 0.3 * self + 0.7 * peerAvg
    - **Validates: Requirements 2.6**
  
  - [x] 2.3 Implement Coordinate model with Haversine distance calculation
    - Create `Coordinate` struct with latitude/longitude
    - Implement `distance(to:)` method using Haversine formula
    - Return distance in miles
    - _Requirements: 1.3_
  
  - [ ]* 2.4 Write property test for distance calculation accuracy
    - **Property 27: Distance Calculation Accuracy**
    - Generate random coordinate pairs, verify within 0.1% of expected
    - **Validates: Requirements 1.3**
  
  - [x] 2.5 Implement ReputationScore and MatchSurvey models
    - Create `ReputationScore` struct with averageSkillAccuracy, punctualityPercentage, averageCharacterRating, evaluationCount
    - Create `MatchSurvey` struct with skillRating (1-9), wasPunctual (Bool), characterRating (1-5)
    - Create `PendingSurvey` struct with expiration logic
    - Implement `isNewPlayer` computed property (< 5 evaluations)
    - _Requirements: 6.2, 6.3, 6.4_
  
  - [ ]* 2.6 Write property test for survey structure completeness
    - **Property 19: Survey Structure Completeness**
    - Generate surveys, verify all three fields present and in valid ranges
    - **Validates: Requirements 6.2**

- [x] 3. Checkpoint - Verify model layer
  - Ensure all model tests pass
  - Verify Codable conformance for all models
  - Ask the user if questions arise

- [x] 4. Implement Room and Friend models
  - [x] 4.1 Implement Room model with code generation
    - Create `Room` struct with id, code, ownerId, mode, participants, timestamps
    - Implement `generateCode()` static method (6-char alphanumeric, exclude 0OIL1)
    - Implement `requiredPlayerCount` computed property
    - Implement `isReady` computed property
    - Implement `isExpired` computed property (30 min timeout)
    - _Requirements: 3.4, 3.6, 3.8_
  
  - [ ]* 4.2 Write property test for room code uniqueness
    - **Property 7: Room Code Uniqueness and Format**
    - Generate 1000 codes, verify all unique, 6 chars, valid charset
    - **Validates: Requirements 3.4**
  
  - [ ]* 4.3 Write property test for room ready state
    - **Property 8: Room Ready State**
    - Generate rooms with various participant counts, verify isReady logic
    - **Validates: Requirements 3.6**
  
  - [ ]* 4.4 Write property test for room expiration
    - **Property 9: Room Expiration**
    - Generate rooms with various lastActivityAt times, verify isExpired
    - **Validates: Requirements 3.8**
  
  - [x] 4.5 Implement Friend models
    - Create `FriendRequest` struct with status enum
    - Create `Friendship` struct for bidirectional relationships
    - Create `RoomParticipant` struct
    - _Requirements: 3.1, 3.2_
  
  - [ ]* 4.6 Write property test for bidirectional friendship
    - **Property 6: Bidirectional Friend Relationship**
    - Generate accepted requests, verify both users have each other in lists
    - **Validates: Requirements 3.2**

- [x] 5. Implement Message and TimeSlot models
  - [x] 5.1 Implement Message models
    - Create `MessageThread` struct with participantIds, lastMessage, unreadCount
    - Create `Message` struct with delivery/read timestamps
    - Create `BlockedUser` struct
    - Implement `otherParticipantId(currentUserId:)` method
    - _Requirements: 5.3, 5.5, 5.7_
  
  - [ ]* 5.2 Write property test for message character limit
    - **Property 16: Message Character Limit**
    - Generate messages 0-2000 chars, verify acceptance for 1-1000
    - **Validates: Requirements 5.7**
  
  - [x] 5.3 Implement TimeSlot models
    - Create `TimeSlot` struct with date, startTime, endTime
    - Implement `duration` computed property
    - Implement `overlaps(with:)` method returning overlapping TimeSlot or nil
    - Create `RecurringTimeSlot` struct for saved preferences
    - _Requirements: 4.2, 4.3_
  
  - [ ]* 5.4 Write property test for time slot overlap calculation
    - **Property 13: Time Slot Overlap Calculation**
    - Generate random time slot pairs, verify overlap >= 30 min or nil
    - **Validates: Requirements 4.3**
  
  - [ ]* 5.5 Write property test for time slot duration validation
    - **Property 12: Time Slot Duration Validation**
    - Generate durations 0-10 hours, verify acceptance for 1-8 hours
    - **Validates: Requirements 4.2**
  
  - [x] 5.6 Implement MatchCandidate model
    - Create `MatchCandidate` struct with user, distance, skillDifference, overlappingTimeSlot
    - Implement `matchScore` computed property (skill * 10 + distance)
    - _Requirements: 4.4, 4.5_
  
  - [ ]* 5.7 Write property test for match candidate ordering
    - **Property 14: Match Candidate Ordering**
    - Generate candidates, sort by matchScore, verify skill-first then distance ordering
    - **Validates: Requirements 4.4, 4.5**

- [x] 6. Checkpoint - Verify all models and properties
  - Run all property tests (minimum 100 iterations each)
  - Ensure all unit tests pass
  - Ask the user if questions arise

- [x] 7. Implement JSON persistence layer
  - [x] 7.1 Implement PersistenceService
    - Create `Services/PersistenceService.swift` implementing protocol
    - Implement `save<T: Encodable>(_ object: T, key: String)` using JSONEncoder
    - Implement `load<T: Decodable>(key: String, type: T.Type)` using JSONDecoder
    - Implement `delete(key: String)`
    - Store in UserDefaults or FileManager (Documents directory)
    - _Requirements: 9.1, 9.2_
  
  - [ ]* 7.2 Write property test for serialization round-trip
    - **Property 22: Data Serialization Round-Trip**
    - Generate valid User, Room, Message, Survey objects
    - Encode to JSON, decode back, verify equality
    - **Validates: Requirements 9.4**
  
  - [ ]* 7.3 Write property test for JSON parse error location
    - **Property 23: JSON Parse Error Location**
    - Generate invalid JSON strings, verify error includes position info
    - **Validates: Requirements 9.5**

- [x] 8. Implement LocationManager with MapKit integration
  - [x] 8.1 Implement LocationManager
    - Create `Managers/LocationManager.swift` as ObservableObject
    - Implement CLLocationManagerDelegate
    - Add `currentLocation: CLLocation?` @Published property
    - Add `authorizationStatus: CLAuthorizationStatus` @Published property
    - Add `nearbyPlayers: [User]` @Published property
    - Implement `requestAuthorization()`, `startUpdatingLocation()`, `stopUpdatingLocation()`
    - _Requirements: 1.1, 1.2, 1.4_
  
  - [x] 8.2 Implement geofence filtering
    - Add `filterNearbyPlayers(allUsers: [User], radiusMiles: Double) -> [User]`
    - Filter users within 50-mile radius using Coordinate.distance(to:)
    - Update nearbyPlayers when location changes
    - _Requirements: 1.3_
  
  - [ ]* 8.3 Write property test for geofence filtering
    - **Property 1: Geofence Filtering**
    - Generate random user locations, verify all returned users within 50 miles
    - **Validates: Requirements 1.3**

- [x] 9. Implement RealMapView with player markers
  - [x] 9.1 Create RealMapView component
    - Create `Views/RealMapView.swift` using MapKit's Map view
    - Bind to LocationManager's currentLocation for centering
    - Display MKCoordinateRegion with appropriate span
    - Handle location permission states
    - _Requirements: 1.1, 1.2, 1.7_
  
  - [x] 9.2 Create PlayerAnnotationView
    - Create `Components/PlayerAnnotationView.swift`
    - Display player avatar with skill level badge
    - Show selection state with border highlight
    - _Requirements: 1.5_
  
  - [x] 9.3 Implement player marker tap handling
    - Add `onPlayerTapped: (User) -> Void` callback
    - Display popup sheet with nickname, skill level, reputation
    - _Requirements: 1.6_
  
  - [x] 9.4 Update HomeView to use RealMapView
    - Replace mock map gradient with RealMapView
    - Wire up LocationManager via @EnvironmentObject
    - Display nearby players from LocationManager.nearbyPlayers
    - _Requirements: 1.1, 1.3, 1.5_

- [x] 10. Checkpoint - Verify map integration
  - Test location permission flow
  - Verify player markers display correctly
  - Test geofence filtering with mock data
  - Ask the user if questions arise

- [x] 11. Implement skill level system UI
  - [x] 11.1 Create SkillLevelPicker component
    - Create `Components/SkillLevelPicker.swift`
    - Display levels 1-9 with icons and descriptions
    - Disable levels 8-9 for self-selection (show verification message)
    - Add `maxSelectableLevel: Int = 7` parameter
    - _Requirements: 2.1, 2.2_
  
  - [ ]* 11.2 Write property test for skill level validation
    - **Property 2: Skill Level Self-Assignment Validation**
    - Generate levels 1-9, verify 1-7 accepted, 8-9 rejected for self-assignment
    - **Validates: Requirements 2.1, 2.2**
  
  - [x] 11.3 Create ReputationBadgeView component
    - Create `Components/ReputationBadgeView.swift`
    - Display skill accuracy, punctuality %, character rating
    - Show "New Player" badge when evaluationCount < 5
    - Support compact mode for list views
    - _Requirements: 2.7, 6.5, 6.6_
  
  - [ ]* 11.4 Write property test for new player badge
    - **Property 4: New Player Badge Display**
    - Generate users with 0-10 evaluations, verify badge shows for < 5
    - **Validates: Requirements 2.7**
  
  - [x] 11.5 Update AuthView with new SkillLevelPicker
    - Replace old SkillLevel enum picker with SkillLevelPicker
    - Update User creation to use Int skill level
    - _Requirements: 2.1_

- [ ] 12. Implement Friend system
  - [x] 12.1 Implement FriendManager
    - Create `Managers/FriendManager.swift` as ObservableObject
    - Add `friends: [User]` @Published property
    - Add `pendingRequests: [FriendRequest]` @Published property
    - Implement `sendFriendRequest(to:)`, `acceptRequest(_:)`, `declineRequest(_:)`
    - Implement `removeFriend(_:)`
    - _Requirements: 3.1, 3.2_
  
  - [x] 12.2 Create FriendListView
    - Create `Views/FriendListView.swift`
    - Display friends with avatar, nickname, skill level
    - Add search/filter functionality
    - Support selection mode for room invitations
    - _Requirements: 3.5_
  
  - [x] 12.3 Create FriendRequestView
    - Create `Views/FriendRequestView.swift`
    - Display pending incoming requests
    - Accept/decline buttons with confirmation
    - _Requirements: 3.1, 3.2_
  
  - [x] 12.4 Add friend-related screens to navigation
    - Add `friends` and `friendRequests` cases to AppScreen enum
    - Update ContentView router
    - Add friends tab/button to HomeView header
    - _Requirements: 3.1_

- [ ] 13. Implement Room system
  - [x] 13.1 Implement RoomManager
    - Create `Managers/RoomManager.swift` as ObservableObject
    - Add `currentRoom: Room?` @Published property
    - Add `roomCode: String?` @Published property
    - Implement `createRoom(mode:)` with code generation
    - Implement `joinRoom(code:)`, `leaveRoom()`, `kickPlayer(_:)`
    - Implement `inviteFriend(_:)`, `startMatch()`
    - Add 30-minute expiration timer
    - _Requirements: 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9, 3.10_
  
  - [ ]* 13.2 Write property test for kick removes participant
    - **Property 10: Kick Removes Participant**
    - Generate rooms with participants, kick one, verify removal
    - **Validates: Requirements 3.10**
  
  - [x] 13.3 Create RoomLobbyView
    - Create `Views/RoomLobbyView.swift`
    - Display room code prominently (shareable)
    - Show participant list with skill levels
    - Show "Start Match" button (enabled when room.isReady)
    - Show invite friends button (opens FriendListView in selection mode)
    - Room owner controls: kick player, close room
    - _Requirements: 3.5, 3.6, 3.7, 3.9_
  
  - [x] 13.4 Create JoinRoomView
    - Create `Views/JoinRoomView.swift`
    - 6-character code input field
    - Join button with validation
    - Error handling for invalid/expired codes
    - _Requirements: 3.4_
  
  - [x] 13.5 Add room screens to navigation
    - Add `createRoom`, `roomLobby`, `joinRoom` cases to AppScreen
    - Update ContentView router
    - Add "Custom Room" option to HomeView mode selection
    - _Requirements: 3.3_

- [x] 14. Checkpoint - Verify friend and room systems
  - Test friend request flow end-to-end
  - Test room creation and joining
  - Verify room expiration timer
  - Ask the user if questions arise

- [x] 15. Implement Time-Slot matching
  - [x] 15.1 Create TimeSlotPicker component
    - Create `Components/TimeSlotPicker.swift`
    - Date picker for next 14 days
    - Start/end time pickers
    - Duration validation (1-8 hours)
    - Visual feedback for invalid durations
    - _Requirements: 4.1, 4.2_
  
  - [ ]* 15.2 Write property test for date selection validation
    - **Property 11: Date Selection Validation**
    - Generate dates -7 to +21 days, verify acceptance for 0-14 days
    - **Validates: Requirements 4.1**
  
  - [x] 15.3 Implement MatchingService with time-slot logic
    - Create `Services/MatchingService.swift` implementing protocol
    - Implement `findMatches(mode:skillLevel:location:timeSlot:radiusMiles:)`
    - Filter by geofence (50 miles)
    - Filter by time slot overlap (>= 30 min)
    - Sort by matchScore (skill difference * 10 + distance)
    - Return top candidates
    - _Requirements: 4.3, 4.4, 4.5_
  
  - [x] 15.4 Create RecurringTimeSlotView
    - Create `Views/RecurringTimeSlotView.swift`
    - Display saved time slot preferences (max 5)
    - Add/edit/delete functionality
    - Day of week selection
    - _Requirements: 4.8_
  
  - [ ]* 15.5 Write property test for recurring slot limit
    - **Property 15: Recurring Time Slot Limit**
    - Attempt to save 1-10 slots, verify max 5 accepted
    - **Validates: Requirements 4.8**
  
  - [x] 15.6 Update MatchingView with time slot selection
    - Add TimeSlotPicker before starting match
    - Display "No matches found" with suggestions after 60s timeout
    - Show matched time slot in results
    - _Requirements: 4.6, 4.7_

- [x] 16. Implement Messaging system
  - [x] 16.1 Implement MessageManager
    - Create `Managers/MessageManager.swift` as ObservableObject
    - Add `threads: [MessageThread]` @Published property
    - Add `unreadCount: Int` @Published property
    - Implement `sendMessage(_:to:)`, `loadMessages(threadId:limit:)`
    - Implement `markAsRead(threadId:)`, `deleteThread(_:)`
    - Implement `blockUser(_:)`, `unblockUser(_:)`
    - Local persistence with sync on reconnect
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.8, 5.9_
  
  - [ ]* 16.2 Write property test for block prevents delivery
    - **Property 17: Block Prevents Message Delivery**
    - Generate blocked relationships, verify messages not delivered
    - **Validates: Requirements 5.5**
  
  - [ ]* 16.3 Write property test for conversation soft delete
    - **Property 18: Conversation Soft Delete**
    - Delete conversation for user A, verify still visible for user B
    - **Validates: Requirements 5.9**
  
  - [x] 16.4 Create MessageListView
    - Create `Views/MessageListView.swift`
    - Display thread list sorted by lastActivityAt
    - Show unread badge per thread
    - Swipe to delete
    - _Requirements: 5.4, 5.9_
  
  - [x] 16.5 Create MessageThreadView
    - Create `Views/MessageThreadView.swift`
    - Display messages with timestamps
    - Show delivery/read receipts
    - Text input with 1000 char limit
    - Block user option in menu
    - _Requirements: 5.1, 5.3, 5.7_
  
  - [x] 16.6 Add messaging screens to navigation
    - Add `messages`, `messageThread` cases to AppScreen
    - Update ContentView router
    - Add messages tab with unread badge to main navigation
    - _Requirements: 5.4_

- [x] 17. Checkpoint - Verify messaging system
  - Test message send/receive flow
  - Verify read receipts update
  - Test block functionality
  - Ask the user if questions arise

- [x] 18. Implement Survey system
  - [x] 18.1 Implement SurveyManager
    - Create `Managers/SurveyManager.swift` as ObservableObject
    - Add `pendingSurveys: [PendingSurvey]` @Published property
    - Add `completedSurveys: [MatchSurvey]` @Published property
    - Implement `submitSurvey(_:)` with duplicate prevention
    - Implement `getPendingSurveys()` filtering expired
    - Implement `calculateReputationScore(userId:)`
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.8, 6.9_
  
  - [ ]* 18.2 Write property test for survey deadline enforcement
    - **Property 20: Survey Deadline Enforcement**
    - Generate surveys with various ages, verify 48h expiration
    - **Validates: Requirements 6.3, 6.4**
  
  - [ ]* 18.3 Write property test for survey uniqueness
    - **Property 21: Survey Uniqueness Per Match**
    - Attempt duplicate submissions, verify rejection
    - **Validates: Requirements 6.8**
  
  - [ ]* 18.4 Write property test for survey generation on match completion
    - **Property 5: Survey Generation on Match Completion**
    - Complete matches with N participants, verify N surveys created
    - **Validates: Requirements 2.5**
  
  - [x] 18.5 Create SurveyFormView
    - Create `Views/SurveyFormView.swift`
    - Skill rating picker (1-9)
    - Punctuality toggle (yes/no)
    - Character rating (1-5 stars)
    - Submit button with validation
    - _Requirements: 6.2_
  
  - [x] 18.6 Create PendingSurveysView
    - Create `Views/PendingSurveysView.swift`
    - List pending surveys with opponent info and expiration countdown
    - Navigate to SurveyFormView on tap
    - _Requirements: 6.1, 6.3_
  
  - [x] 18.7 Update match flow with reputation display
    - Show opponent's ReputationBadgeView in match confirmation
    - Add "Decline" button based on reputation
    - Trigger survey creation on match completion
    - _Requirements: 6.6, 6.7_

- [x] 19. Implement accessibility features
  - [x] 19.1 Add accessibility labels to all interactive elements
    - Audit all buttons, text fields, toggles
    - Add `.accessibilityLabel()` modifiers
    - Add `.accessibilityHint()` for complex actions
    - _Requirements: 8.2_
  
  - [ ]* 19.2 Write property test for accessibility label coverage
    - **Property 25: Accessibility Label Coverage**
    - Enumerate interactive elements, verify non-empty labels
    - **Validates: Requirements 8.2**
  
  - [x] 19.3 Verify color contrast compliance
    - Audit all color pairs in Theme.swift
    - Ensure contrast ratio >= 4.5:1
    - Document any exceptions with justification
    - _Requirements: 8.1_
  
  - [ ]* 19.4 Write property test for color contrast
    - **Property 24: Color Contrast Compliance**
    - Test all text/background color pairs, verify >= 4.5:1 ratio
    - **Validates: Requirements 8.1**
  
  - [x] 19.5 Add Dynamic Type support
    - Use `.font()` modifiers that scale with Dynamic Type
    - Test with accessibility sizes
    - _Requirements: 8.4_
  
  - [x] 19.6 Add reduced motion support
    - Check `UIAccessibility.isReduceMotionEnabled`
    - Disable particle effects and complex animations when enabled
    - _Requirements: 8.5_

- [x] 20. Implement localization
  - [x] 20.1 Create Localizable.strings for zh-CN
    - Extract all user-facing strings
    - Create `zh-CN.lproj/Localizable.strings`
    - Use `NSLocalizedString` or String(localized:) for all text
    - _Requirements: 8.3_
  
  - [ ]* 20.2 Write property test for localization coverage
    - **Property 26: Localization Coverage**
    - Enumerate all string keys, verify zh-CN translations exist
    - **Validates: Requirements 8.3**

- [x] 21. Checkpoint - Verify accessibility and localization
  - Run VoiceOver testing
  - Verify all strings are localized
  - Test with Dynamic Type
  - Ask the user if questions arise

- [x] 22. Wire all components together
  - [x] 22.1 Update AppState with all managers
    - Add all managers as @StateObject properties
    - Inject via @EnvironmentObject in ContentView
    - Update AppScreen enum with all new screens
    - _Requirements: Architecture_
  
  - [x] 22.2 Update ContentView router
    - Add switch cases for all new screens
    - Implement navigation transitions
    - _Requirements: Architecture_
  
  - [x] 22.3 Update HomeView with new features
    - Add tabs/buttons for Friends, Messages, Surveys
    - Integrate RealMapView
    - Add Custom Room option
    - Add Time Slot selection before matching
    - _Requirements: All features_
  
  - [x] 22.4 Update ProfileView with reputation
    - Display user's own reputation score
    - Show pending surveys count
    - Add friends count
    - _Requirements: 6.5_

- [x] 23. Implement offline support and sync
  - [x] 23.1 Implement offline data caching
    - Cache friend list to local storage
    - Cache message threads to local storage
    - Cache pending surveys to local storage
    - _Requirements: 7.5_
  
  - [ ]* 23.2 Write property test for offline data availability
    - **Property (offline)**: Cached data available without network
    - Save data, simulate offline, verify retrieval
    - **Validates: Requirements 7.5**
  
  - [x] 23.3 Implement network retry with exponential backoff
    - Create `NetworkClient` with retry logic
    - Max 3 retries with exponential backoff (1s, 2s, 4s)
    - _Requirements: 7.7_

- [x] 24. Final checkpoint - Full integration testing
  - Run all property tests (100+ iterations each)
  - Run all unit tests
  - Verify all user flows work end-to-end
  - Test offline mode
  - Verify memory usage during animations (< 50MB card collision, < 30MB pulse)
  - Ask the user if questions arise

## Notes

- Tasks marked with `*` are optional property-based tests that can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties (minimum 100 iterations)
- Unit tests validate specific examples and edge cases
- All strings must be localized to Chinese (zh-CN)
- All interactive elements must have accessibility labels
- Performance targets: 60 FPS animations, < 50MB memory for card collision
