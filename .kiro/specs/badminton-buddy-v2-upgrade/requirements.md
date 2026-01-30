# Requirements Document

## Introduction

This document specifies the requirements for BadmintonBuddy v2.0, a major upgrade to the iOS badminton partner matching application. The upgrade introduces six core feature sets: real map integration with geolocation-based matching, an enhanced 9-tier skill rating system with peer evaluation, a friend system with custom game rooms, time-slot based matching, a direct messaging system, and a post-match survey system for player reputation tracking.

## Glossary

- **User**: A registered player using the BadmintonBuddy application
- **Skill_Level**: A numeric rating from 1-9 representing a player's badminton proficiency
- **Match**: A scheduled badminton game between 2 players (singles) or 4 players (doubles)
- **Room**: A custom game lobby created by a user to invite friends for a match
- **Survey**: A post-match questionnaire for evaluating opponent's skill, punctuality, and character
- **Reputation_Score**: A composite score derived from survey responses (skill accuracy, punctuality, character rating)
- **Message_Thread**: A private conversation between two users
- **Time_Slot**: A date and time range during which a user is available to play
- **Geofence**: A 50-mile radius boundary for matching eligible players
- **Map_Service**: The MapKit framework providing real map data and location services

## Requirements

### Requirement 1: Real Map Integration with Geolocation

**User Story:** As a user, I want to see real maps with actual player locations, so that I can find nearby badminton partners within a reasonable distance.

#### Acceptance Criteria

1. WHEN the home screen loads, THE Map_Service SHALL display a real map centered on the user's current GPS location
2. WHEN location permission is denied, THE System SHALL display a prompt explaining why location access is needed and provide a button to open Settings
3. THE System SHALL only display other users who are within a 50-mile (80.47 km) radius of the current user's location
4. WHEN a user's location changes by more than 100 meters, THE Map_Service SHALL update the displayed position within 5 seconds
5. THE Map_Service SHALL display player markers with skill level indicators on the map
6. WHEN a user taps on a player marker, THE System SHALL display a popup with that player's nickname, skill level, and reputation score
7. IF location services become unavailable, THEN THE System SHALL display the last known location with a "Location unavailable" indicator

### Requirement 2: Enhanced 9-Tier Skill Rating System

**User Story:** As a user, I want a detailed skill rating system that accurately reflects player abilities, so that I can find opponents of similar skill level.

#### Acceptance Criteria

1. THE System SHALL support skill levels from 1 to 9, where levels 1-7 are self-assignable during registration
2. WHEN a user attempts to set their skill level to 8 or 9 during registration, THE System SHALL reject the selection and display a message explaining verification requirements
3. THE System SHALL require regional championship verification for level 8 designation
4. THE System SHALL require national championship verification for level 9 designation
5. WHEN a match is completed, THE System SHALL send a skill evaluation survey to both participants
6. THE Survey_System SHALL calculate the user's displayed skill level as the weighted average of self-reported level (30%) and peer evaluations (70%)
7. WHEN a user has fewer than 5 peer evaluations, THE System SHALL display only the self-reported level with a "New Player" badge
8. THE System SHALL update the calculated skill level within 1 minute of receiving a new survey response

### Requirement 3: Friend System and Custom Game Rooms

**User Story:** As a user, I want to add friends and create custom game rooms, so that I can easily organize matches with people I know.

#### Acceptance Criteria

1. WHEN a user sends a friend request, THE System SHALL deliver a notification to the recipient within 3 seconds
2. WHEN a friend request is accepted, THE System SHALL add both users to each other's friend lists immediately
3. THE System SHALL allow users to create a custom room with a specified game mode (singles or doubles)
4. WHEN a room is created, THE System SHALL generate a unique 6-character alphanumeric room code
5. THE Room_Owner SHALL be able to invite friends from their friend list to the room
6. WHEN all required players have joined (2 for singles, 4 for doubles), THE System SHALL enable the "Start Match" button
7. WHEN the room owner starts the match, THE System SHALL transition all room participants to the match confirmation screen
8. IF a room has no activity for 30 minutes, THEN THE System SHALL automatically close the room and notify all participants
9. THE System SHALL allow the room owner to kick players from the room before the match starts
10. WHEN a user is kicked from a room, THE System SHALL immediately remove them and display a notification

### Requirement 4: Time-Slot Based Matching

**User Story:** As a user, I want to specify when I'm available to play, so that the system can match me with players who have compatible schedules.

#### Acceptance Criteria

1. WHEN starting a match search, THE System SHALL allow users to select a date within the next 14 days
2. THE System SHALL allow users to specify a time range with minimum duration of 1 hour and maximum of 8 hours
3. WHEN matching players, THE System SHALL only consider users whose time slots overlap by at least 30 minutes
4. THE Matching_Algorithm SHALL prioritize players with the closest skill level among those with compatible time slots
5. WHEN multiple players have identical skill levels, THE System SHALL prioritize by geographic proximity
6. THE System SHALL display the matched time slot (the overlapping period) in the match confirmation screen
7. IF no compatible players are found within 60 seconds, THEN THE System SHALL suggest expanding the time range or skill tolerance
8. THE System SHALL allow users to save up to 5 recurring time slot preferences

### Requirement 5: Direct Messaging System

**User Story:** As a user, I want to send private messages to other players, so that I can coordinate match details and communicate with potential partners.

#### Acceptance Criteria

1. WHEN a user opens a conversation, THE Message_System SHALL load the most recent 50 messages within 2 seconds
2. THE System SHALL deliver sent messages to the recipient within 3 seconds under normal network conditions
3. THE Message_System SHALL display read receipts showing when a message was delivered and read
4. WHEN a new message is received, THE System SHALL display a notification badge on the messages tab
5. THE System SHALL allow users to block other users, preventing them from sending further messages
6. WHEN a user is blocked, THE System SHALL not notify the blocked user of the block action
7. THE Message_System SHALL support text messages up to 1000 characters
8. THE System SHALL persist all messages locally and sync with the server when connectivity is restored
9. WHEN a user deletes a conversation, THE System SHALL remove it from their view but preserve it for the other participant

### Requirement 6: Post-Match Survey System

**User Story:** As a user, I want to rate my opponents after matches, so that I can help maintain a trustworthy community and make informed decisions about future matches.

#### Acceptance Criteria

1. WHEN a match is marked as completed, THE System SHALL send a survey notification to both participants within 1 minute
2. THE Survey SHALL include three evaluation categories: skill level accuracy (1-9), punctuality (yes/no), and character rating (1-5)
3. THE System SHALL require users to complete the survey within 48 hours of match completion
4. IF a user does not complete the survey within 48 hours, THEN THE System SHALL mark the survey as expired and exclude it from calculations
5. THE System SHALL calculate and display a composite reputation score based on: average skill accuracy deviation, punctuality percentage, and average character rating
6. WHEN viewing a potential match, THE System SHALL display the opponent's reputation metrics (skill accuracy, punctuality %, character rating)
7. THE System SHALL allow users to decline a match based on reputation data before final confirmation
8. THE Survey_System SHALL prevent users from submitting multiple surveys for the same match
9. WHEN a survey is submitted, THE System SHALL update the recipient's reputation score within 30 seconds

### Requirement 7: Performance and Reliability

**User Story:** As a user, I want the app to be fast and reliable, so that I can have a smooth experience while finding badminton partners.

#### Acceptance Criteria

1. THE System SHALL maintain 60 FPS for all animations including card collision effects
2. THE System SHALL consume less than 50MB of memory during card collision animations
3. THE System SHALL consume less than 30MB of memory during pulse search animations
4. THE Map_Service SHALL render map tiles within 500ms of a pan or zoom gesture
5. THE System SHALL support offline mode for viewing cached friend lists and message history
6. WHEN network connectivity is restored, THE System SHALL sync pending data within 10 seconds
7. THE System SHALL implement automatic retry with exponential backoff for failed API requests (max 3 retries)

### Requirement 8: Accessibility and Localization

**User Story:** As a user, I want the app to be accessible and in my language, so that I can use it comfortably regardless of my abilities.

#### Acceptance Criteria

1. THE System SHALL maintain WCAG 2.1 AA compliance with color contrast ratio ≥ 4.5:1 for all text
2. THE System SHALL support VoiceOver for all interactive elements
3. THE System SHALL provide Chinese (zh-CN) localization for all user-facing text
4. THE System SHALL support Dynamic Type for text scaling
5. WHEN a user enables reduced motion, THE System SHALL disable non-essential animations

### Requirement 9: Data Persistence and Serialization

**User Story:** As a developer, I want reliable data persistence, so that user data is safely stored and can be recovered.

#### Acceptance Criteria

1. WHEN storing user data locally, THE System SHALL encode it using JSON format
2. THE System SHALL validate all incoming JSON data against the expected schema before parsing
3. THE Pretty_Printer SHALL format User, Room, and Message objects back into valid JSON
4. FOR ALL valid data objects, serializing then deserializing SHALL produce an equivalent object (round-trip property)
5. WHEN parsing fails, THE System SHALL return a descriptive error with the failure location
