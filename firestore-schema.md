# Firestore Schema — Drive App

## Existing collections

### `users/{uid}`
| Field | Type | Notes |
|-------|------|-------|
| displayName | string | |
| avatarURL | string? | |
| schoolCode | string? | Set when student links to a school; null when unlinked |
| schoolLinkedAt | timestamp? | |

### `users/{uid}/drives/{driveId}`
| Field | Type | Notes |
|-------|------|-------|
| score | number | 0–100 |
| duration | number | seconds, 0–86400 |
| date | timestamp | |
| videoURL | string? | |
| route | array | RoutePoint objects |
| routeTag | string? | |
| metrics | map? | braking, acceleration, cornering, smoothness (0–100 each) |
| coachTips | array? | CoachTip objects |

### `users/{uid}/public_profile/{...}`
Readable by everyone — used for leaderboard badge display.

### `gc_users/{gcId}`
| Field | Type | Notes |
|-------|------|-------|
| uid | string | Firebase UID for this Game Center player |

---

## New collections (Driving School)

### `schools/{schoolCode}`
Written by Admin SDK only at school account creation.

| Field | Type | Notes |
|-------|------|-------|
| name | string | School display name |
| email | string | School contact / login email |
| createdAt | timestamp | |
| active | bool | Can be suspended without deleting |

`schoolCode` is a short alphanumeric string (e.g. `DRIVE123`) used as the document ID.

---

### `schools/{schoolCode}/students/{uid}`
Written by Cloud Function (`linkStudentToSchool`) when a student submits a school code.

| Field | Type | Notes |
|-------|------|-------|
| displayName | string | Copied from user profile at link time |
| linkedAt | timestamp | |

---

### `schools/{schoolCode}/students/{uid}/drives/{driveId}`
Mirror of `users/{uid}/drives/{driveId}`. Written by Cloud Function (`mirrorDriveToSchool`) on each new drive write — only when the user has a `schoolCode` set.

Same fields as `users/{uid}/drives/{driveId}`.

---

### `schools/{schoolCode}/assignments/{assignmentId}`
Created and managed by school instructors via the web dashboard.

| Field | Type | Notes |
|-------|------|-------|
| title | string | max 120 chars |
| description | string? | |
| type | string | e.g. `complete_drives`, `smooth_braking`, `low_braking` |
| targetCount | number | e.g. 3 drives, score ≥ 80 |
| targetStudentUID | string? | null = assigned to all linked students |
| dueDate | timestamp? | |
| createdAt | timestamp | |

---

## Cloud Functions required

| Function | Trigger | What it does |
|----------|---------|--------------|
| `linkStudentToSchool` | HTTPS callable | Validates schoolCode exists, writes `schools/{code}/students/{uid}`, updates `users/{uid}.schoolCode` |
| `unlinkStudentFromSchool` | HTTPS callable | Removes student roster entry, clears `users/{uid}.schoolCode` |
| `mirrorDriveToSchool` | Firestore `users/{uid}/drives/{driveId}` onCreate | Checks user's `schoolCode`; if set, copies drive to `schools/{code}/students/{uid}/drives/{driveId}` |
| `createSchoolAccount` | HTTPS callable (admin-gated) | Creates Firebase Auth user with custom claims `{ role: "school", schoolCode }`, writes `schools/{code}` doc |

---

## Custom Auth Claims (school accounts)

Set via Admin SDK in `createSchoolAccount` function:

```json
{
  "role": "school",
  "schoolCode": "DRIVE123"
}
```

Student accounts have no custom claims — school linkage lives in Firestore only.
