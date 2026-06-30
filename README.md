# ResearchPaper — Flutter data collection & QR submission app

ResearchPaper is a Flutter application that uses Firebase to collect,
store, and manage dataset records. It includes user registration and
authentication, QR-based submission flows, an admin console for data
management, export tools, and ready-to-run Firebase rules and scripts.

## Quick Start

- Install Flutter: https://docs.flutter.dev/get-started
- Configure Firebase for Android/iOS and add the generated `google-services.json` / `GoogleService-Info.plist` files.
- From the project root run:

```bash
flutter pub get
flutter run
```

## Project structure (high level)

- `android/`, `ios/` — platform folders and build configs
- `lib/` — main Flutter source (models, services, widgets, screens)
- `assets/` — bundled assets
- `firestore.rules`, `storage.rules` — security rules for Firebase
- `reset-password.js` — helper script for password reset flows
- `pubspec.yaml` — Dart/Flutter dependencies and metadata

## A–Z Features (English)

- **A — Admin Console:** A web/mobile admin interface to review and manage dataset records (`lib/All in one/ADMIN/adminConsole.dart`).
- **B — Backup & Export:** Export data to common formats (CSV/Excel) using the export service (`lib/services/export_service.dart`).
- **C — Cloud Firestore Integration:** Primary persistent datastore with provided security rules (`firestore.rules`).
- **D — Dataset Model:** Central data model for records in `lib/models/dataset_record_model.dart`.
- **E — Email & Auth:** Firebase Authentication for sign-up, login, and protected flows (`lib/All in one/Registrations`).
- **F — Forms & Validation:** User-facing forms for registration and dataset entry (various `lib/All in one/*` screens).
- **G — Google/Firebase Configuration:** Project includes `firebase_options.dart` and sample `google-services.json` for quick setup.
- **H — Hosting Support:** `firebase.json` is included for optional Firebase Hosting configuration and deployment.
- **I — Image & QR Decoding:** Services to decode images and parse QR codes (`lib/services/qr_image_decoder_*`, `lib/services/qr_parser_service.dart`).
- **J — JSON Import/Export:** Import and export helpers support JSON as an interchange format.
- **K — Kotlin Android Tooling:** Android module configured with Kotlin build files under `android/`.
- **L — Login & Signup Screens:** User flows implemented at `lib/All in one/Registrations/login.dart` and `signup.dart`.
- **M — Mobile Scanner Integration:** QR scanning using mobile scanner libraries (see `mobile_scanner` dependencies in `pubspec.yaml`).
- **N — Navigation & Routing:** Standard Flutter navigation patterns used across screens and widgets.
- **O — Onboarding Screens:** First-run onboarding flows located in the `OnBoard/` folder.
- **P — Password Reset Script:** `reset-password.js` helper script to trigger password resets or related admin tasks.
- **Q — QR Submission Flow:** QR result submission UI (`lib/All in one/qr_result_submission_page.dart`) and parsing services.
- **R — Rules (Security):** Firestore and Storage security rules included and ready for review (`firestore.rules`, `storage.rules`).
- **S — Firebase Storage:** Support for storing assets and submission media (storage rules provided).
- **T — Tests:** Basic widget test scaffold in `test/widget_test.dart` to start test coverage.
- **U — Utilities:** Reusable utility functions in `lib/utils/` for common tasks.
- **V — Versioned Dependencies:** `pubspec.lock` and `pubspec.yaml` track packages and versions used.
- **W — Widgets Library:** Reusable UI components in `lib/Widgets/` for consistent design.
- **X — eXport Formats:** Export service supports common export formats (CSV/Excel/JSON) for reporting and backup.
- **Y — YAML Configuration:** Analysis and dependency configuration via `analysis_options.yaml` and `pubspec.yaml`.
- **Z — ZIP / Archive Support:** Export tools can package export files into archives for download or transfer.

## Deployment notes

- Review and adapt `firestore.rules` and `storage.rules` before deploying to production.
- Set real Firebase project values in the platform config files and `firebase_options.dart`.

## Contributing

If you want to contribute, please:

1. Fork the repository and create a feature branch
2. Make changes and add tests where appropriate
3. Open a pull request describing your changes

## Contact / Support

If you run into issues, open an issue on the GitHub repository with steps to reproduce and relevant logs.

---
Updated README: concise project description and full A–Z features list.
