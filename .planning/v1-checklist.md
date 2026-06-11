# Drive v1 — Pre-Launch Checklist

Last updated: Mar 2026

## Core (ship-blocking)
- [x] Live Activity / Dynamic Island — score on lock screen while driving
- [x] Push Notifications — streak reminders, badge unlocks, weekly summary
- [x] Empty States — Weekly Trend, Latest Drive, Leaderboard, Routes
- [x] AI Scoring Model — DrivingEval.mlpackage on camera frames + sensor fallback
- [x] Video Playback — video saved on record, playback in DriveReportView with event chips
- [x] Onboarding Flow — first-launch experience: explain the app, request permissions in context, set up profile

## Polish (high value, pre-v1)
- [x] Home Screen Widget — avg score, current streak, last drive at a glance (needs App Group ID configured)
- [x] Individual Drive Share Card — share button in Drive Report, exports styled card as PNG

## Post-v1 / Nice-to-Have
- [ ] Route History Map — overlay all driven routes on one map
- [ ] Monthly / All-time Trends — weekly trends exist, longer views missing
- [ ] iCloud Backup — currently local JSON + Firestore; CloudKit for redundancy
- [ ] CarPlay — ambitious, post-v1
