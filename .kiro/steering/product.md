# Product Overview

**羽毛球搭子 (Badie / Badie)** — iOS app for finding badminton partners nearby by skill level, time slot and distance.

## Core Value
Get a reliable game tonight: matched skill, overlapping free time, a court you can reach, transparent AA cost, and visible trust (check-in based attendance + double-blind peer reviews).

## Key Features (v3)
- Phone + code login with privacy consent; onboarding with behavioural 1–7 self-assessment (8–9 require verification)
- Quick match (singles/doubles, 14 days, 1–8h slot, ≤3 courts, skill tolerance) with relaxation suggestions
- Open games ("我有场地缺人") with level range, vibe tags, waitlist; private rooms with 6-char code
- Game ticket: reminders, calendar, navigation (Apple/Amap/Baidu), check-in, AA split, late-cancel policy
- Double-blind post-game surveys feeding reputation and the 30/70 weighted level
- Friends, direct messages (receipts, typing, invites), block/report, inbox notifications
- Profile: reputation, attendance standing, recurring slots, travel radius, favourites, appearance, account deletion

## Target Users
Badminton players in mainland China (zh-CN), especially those organising via WeChat groups today.

## Backend
No production backend yet. `MockBackend` simulates the server locally (JSON persistence + simulated nearby players) behind an event stream.
