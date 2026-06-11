/**
 * Drive App — Cloud Functions
 *
 * Functions:
 *   createSchoolAccount  — HTTPS callable. Provisions a school Firebase Auth
 *                          user with custom claims and writes the schools/{code}
 *                          document. Protected by an ADMIN_SECRET env var so
 *                          only your onboarding script / admin CLI can call it.
 *
 *   createSchool         — HTTPS callable. Self-service version for the web
 *                          dashboard. Called by an already-authenticated instructor
 *                          to create a school and receive custom claims.
 *
 *   syncStudentRoster    — Firestore trigger on users/{uid}. Keeps the
 *                          schools/{orgId}/students/{uid} roster entry in sync
 *                          whenever a student links or unlinks from a school.
 *
 * Deploy:
 *   cd functions && npm install
 *   firebase use <your-project-id>
 *   firebase deploy --only functions
 *
 * Set the admin secret before deploying:
 *   firebase functions:secrets:set ADMIN_SECRET
 */

'use strict';

const { onCall, HttpsError }    = require('firebase-functions/v2/https');
const { onDocumentWritten }     = require('firebase-functions/v2/firestore');
const { defineSecret }          = require('firebase-functions/params');
const admin                     = require('firebase-admin');

admin.initializeApp();

const db   = admin.firestore();
const auth = admin.auth();

// Secret stored in Firebase Secret Manager (firebase functions:secrets:set ADMIN_SECRET).
const adminSecret = defineSecret('ADMIN_SECRET');


// ── createSchoolAccount ────────────────────────────────────────────────────────
//
// Creates a Firebase Auth user for a school instructor with custom claims
// { role: "school", schoolCode: "<CODE>" } and writes the schools/{code} doc.
//
// Required payload:
//   adminSecret  — must match the ADMIN_SECRET secret
//   schoolCode   — short alphanumeric, e.g. "DRIVE123" (becomes doc ID)
//   schoolName   — display name shown to students
//   email        — school account login email
//   password     — school account login password (min 8 chars)
//
// Returns: { uid, schoolCode }
//
exports.createSchoolAccount = onCall(
  { secrets: [adminSecret] },
  async (request) => {
    const { adminSecret: providedSecret, schoolCode, schoolName, email, password } = request.data;

    // ── Auth check
    const expected = adminSecret.value();
    if (!expected || providedSecret !== expected) {
      throw new HttpsError('permission-denied', 'Invalid admin secret.');
    }

    // ── Input validation
    if (!schoolCode || !schoolName || !email || !password) {
      throw new HttpsError(
        'invalid-argument',
        'schoolCode, schoolName, email, and password are all required.'
      );
    }
    if (password.length < 8) {
      throw new HttpsError('invalid-argument', 'Password must be at least 8 characters.');
    }

    const code = schoolCode.trim().toUpperCase();
    if (!/^[A-Z0-9]{4,20}$/.test(code)) {
      throw new HttpsError(
        'invalid-argument',
        'schoolCode must be 4–20 uppercase letters/numbers (e.g. DRIVE123).'
      );
    }

    // ── Check code isn't already taken
    const existing = await db.collection('schools').doc(code).get();
    if (existing.exists) {
      throw new HttpsError('already-exists', `School code "${code}" is already registered.`);
    }

    // ── Create Firebase Auth user for the school
    let user;
    try {
      user = await auth.createUser({ email, password, displayName: schoolName });
    } catch (err) {
      if (err.code === 'auth/email-already-exists') {
        throw new HttpsError('already-exists', 'An account with that email already exists.');
      }
      throw new HttpsError('internal', `Failed to create user: ${err.message}`);
    }

    // ── Set custom claims — these appear in request.auth.token on the web dashboard
    await auth.setCustomUserClaims(user.uid, { role: 'school', schoolCode: code });

    // ── Write the school document
    await db.collection('schools').doc(code).set({
      name:               schoolName,
      email,
      ownerUid:           user.uid,
      createdAt:          admin.firestore.FieldValue.serverTimestamp(),
      active:             true,
      subscriptionActive: true,
    });

    return { uid: user.uid, schoolCode: code };
  }
);


// ── createSchool ───────────────────────────────────────────────────────────────
//
// Self-service school creation for instructors who sign up via the web dashboard.
// The caller must already be authenticated (request.auth is required).
// Generates a unique school code, writes the school document, and sets
// custom claims { role: "school", schoolCode: "<CODE>" } on the calling user.
//
// Required payload:
//   schoolName  — display name for the school
//
// Returns: { schoolCode }
//
exports.createSchool = onCall(async (request) => {
  // Must be authenticated
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'You must be signed in to create a school.');
  }

  const uid = request.auth.uid;

  // Prevent creating a second school if they already have one
  const existingClaims = request.auth.token;
  if (existingClaims.role === 'school') {
    return { schoolCode: existingClaims.schoolCode };
  }

  const { schoolName } = request.data;
  if (!schoolName || typeof schoolName !== 'string' || !schoolName.trim()) {
    throw new HttpsError('invalid-argument', 'schoolName is required.');
  }

  // Get the user's email for the school document
  let email = '';
  try {
    const authUser = await auth.getUser(uid);
    email = authUser.email ?? '';
  } catch (_) {}

  // Generate a unique 8-character alphanumeric school code
  let schoolCode = '';
  let attempts = 0;
  while (attempts < 10) {
    const candidate = Array.from({ length: 8 }, () =>
      'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'[Math.floor(Math.random() * 32)]
    ).join('');
    const snap = await db.collection('schools').doc(candidate).get();
    if (!snap.exists) {
      schoolCode = candidate;
      break;
    }
    attempts++;
  }
  if (!schoolCode) {
    throw new HttpsError('internal', 'Could not generate a unique school code. Please try again.');
  }

  // Write the school document (Admin SDK bypasses Firestore rules)
  await db.collection('schools').doc(schoolCode).set({
    name:               schoolName.trim(),
    email,
    ownerUid:           uid,
    createdAt:          admin.firestore.FieldValue.serverTimestamp(),
    active:             true,
    subscriptionActive: true,
  });

  // Set custom claims on the calling user
  await auth.setCustomUserClaims(uid, { role: 'school', schoolCode });

  return { schoolCode };
});


// ── syncStudentRoster ──────────────────────────────────────────────────────────
//
// Triggered whenever a users/{uid} document is written.
// Keeps the schools/{orgId}/students/{uid} roster entry in sync:
//
//   orgId set (student joins school)  → create/update roster entry
//   orgId removed (student leaves)    → delete roster entry
//   orgId changed (switched schools)  → remove from old, add to new
//
exports.syncStudentRoster = onDocumentWritten('users/{uid}', async (event) => {
  const uid    = event.params.uid;
  const before = event.data?.before?.data() ?? null;
  const after  = event.data?.after?.data()  ?? null;

  // Document deleted entirely — remove from any school they were in
  if (!after) {
    const prevOrgId = before?.orgId ?? null;
    if (prevOrgId) {
      await db.collection('schools').doc(prevOrgId)
        .collection('students').doc(uid)
        .delete()
        .catch(() => {});
    }
    return;
  }

  const prevOrgId = before?.orgId ?? null;
  const newOrgId  = after?.orgId  ?? null;

  // No change in school linkage — nothing to do
  if (prevOrgId === newOrgId) return;

  // Student left or switched school — remove old roster entry
  if (prevOrgId) {
    await db.collection('schools').doc(prevOrgId)
      .collection('students').doc(uid)
      .delete()
      .catch(() => {});
  }

  // Student joined a school — create roster entry
  if (newOrgId) {
    // Resolve display name: prefer Firestore field, fall back to Auth record
    let displayName = after.displayName ?? '';
    if (!displayName) {
      try {
        const authUser = await auth.getUser(uid);
        displayName = authUser.displayName ?? authUser.email ?? '';
      } catch (_) {}
    }

    // Verify the school still exists before adding the entry
    const schoolDoc = await db.collection('schools').doc(newOrgId).get();
    if (!schoolDoc.exists) {
      console.warn(`[syncStudentRoster] school "${newOrgId}" not found — skipping roster write for uid ${uid}`);
      return;
    }

    await db.collection('schools').doc(newOrgId)
      .collection('students').doc(uid)
      .set({
        displayName,
        linkedAt: admin.firestore.FieldValue.serverTimestamp(),
        active:   true,
      });
  }
});
