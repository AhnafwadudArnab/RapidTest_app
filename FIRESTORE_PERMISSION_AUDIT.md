# Firestore permission audit

Date: 2026-06-30

## Collections used by the app

- `users/{uid}`
  - Reads: profile screens, admin login bootstrap, result submission profile lookup.
  - Writes: signup batch, profile create/update, profile photo update, configured admin bootstrap.
  - Rule expectation: owner can read/write validated user profile fields; configured admin can bootstrap its own `admin` role; admins can manage users.

- `usernames/{usernameLower}`
  - Reads: unauthenticated username-to-email lookup during login and username availability during signup.
  - Writes: signup batch creates username reservation.
  - Rule expectation: public `get` is required for username login; `list` is blocked.

- `dataset_records/{recordId}`
  - Writes: signed-in users create their own submitted test records.
  - Reads: owner reads own records; admin reads all records and exports.
  - Updates/deletes: admin only.
  - Rule expectation: create payload must match strict schema and string length limits.

- `qr_kits/{kitId}`
  - Reads: signed-in users/admins scan and resolve kit metadata.
  - Writes/deletes: admin only.
  - Rule expectation: strict kit schema and string length limits.

## Storage paths used by the app

- `rapid_test_reports/{uid}/{fileName}`: owner writes report images; owner/admin reads.
- `profile_photos/{uid}/{fileName}`: owner writes profile photos; owner/admin reads.
- `qr_kit_images/{kitId}/{fileName}`: admin writes QR kit images; signed-in users read.

## Fixes applied

- `DatabaseService.submitDatasetRecord` now coerces/caps every field that must be a Firestore string before writing `dataset_records`.
- Nested QR data is sanitized before writing to `qrParsedData`.
- `DatabaseService.saveQrKit` now coerces/caps QR kit fields to match `qr_kits` rules.
- Admin QR kit images are stored as size-limited Firestore `data:image/...;base64` values in `qrImageUrl`, avoiding Firebase Storage billing for kit images.
- User result submission no longer requires a photo; users can scan a kit QR, choose Positive/Negative, and submit. Optional result photos are also stored as size-limited Firestore data URLs when small enough.
- `firestore.rules` validates configured-admin profile bootstrapping instead of allowing a raw `role == admin` write.
- `storage.rules` now recognizes the configured admin email the same way Firestore rules do, fixing admin QR image upload permission mismatch.
- Admin login now shows Firebase/Auth errors instead of swallowing them as a generic invalid-admin response.

## Verification

- `flutter analyze`: passed.
- `npx firebase-tools deploy --only firestore:rules --dry-run`: passed.
- `npx firebase-tools deploy --only firestore:rules`: deployed successfully.
- `npx firebase-tools deploy --only firestore:rules,storage --dry-run`: blocked because Firebase Storage is not set up for project `faculty-purpose-bb50a`.
- `POST https://firebasestorage.googleapis.com/v1alpha/projects/faculty-purpose-bb50a/defaultBucket`: blocked with `403 PERMISSION_DENIED` for the currently logged-in Firebase CLI account.

## Devil's advocate checks

- Public unauthenticated reads are still blocked except `usernames/{usernameLower}` single-document `get`, which is required for username login before sign-in.
- Users cannot create `dataset_records` for another UID because `userId` must equal `request.auth.uid`.
- Users cannot update or delete `dataset_records`; only admins can review/update/delete.
- Normal users cannot create/update their own `role` to `admin`; only the configured admin email has the admin bootstrap path.
- `users`, `dataset_records`, and `qr_kits` reject unknown top-level fields.
- App writes now cap strings to the same sizes enforced by rules for result submissions and QR kit admin writes.
- Embedded QR kit images are limited to 500 KB before base64 encoding to stay under Firestore's document size limit.
- Optional result photos are limited to 500 KB before base64 encoding; oversized photos are skipped while the result still saves.

## Security notes

- `usernames/{usernameLower}` allows public `get` because the login screen supports username login before Firebase Auth sign-in. `list` remains blocked.
- Admin access is still bootstrapped by the configured email `admin_cse@rptest.com`; this is a project-specific trust decision.
- Firebase Storage is not required for admin QR kit images after the free-mode change. It is still used for user report photos/profile photos; those uploads fail gracefully or show an error when Storage is not enabled.
