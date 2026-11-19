# Android development on Windows

This fork starts from the upstream Flutter app and reuses the existing backend.
The first milestone is Android Google sign-in and text chat. No local database,
Cloud Run deployment or provider API key is needed for this milestone.

## Repository and tools

- `origin` is your fork; `upstream` is the original repository. Work on
  `feat/android-chat` and open pull requests against your own fork's `main`.
- Keep Flutter at **3.44.6**, matching CI and Dart 3.12.2. Run
  `flutter pub get --enforce-lockfile` from `app/`; do not upgrade dependencies as
  part of setup.
- Install Android Studio, Android SDK 36 and its command-line/platform tools, and
  use Android Studio's bundled JDK. CI uses its preinstalled JDK 17.
- Run `flutter doctor -v` and `flutter doctor --android-licenses`. Use a Google
  Play-enabled emulator or an Android phone with Google Play services.
- Kotlin incremental compilation is disabled because a Windows pub cache and
  checkout on different drives otherwise fail while writing incremental caches.
- The backend deploy workflow is restricted to the upstream repository. This
  fork must not be given the upstream deployment credentials.

Git's Credential Manager handles push authentication. GitHub CLI may also use a
browser login with `gh auth login --hostname github.com --git-protocol https --web`;
verify that its active account is your fork's owner before using it.

To bring in upstream fixes later, first commit your work, then run from the root:

```powershell
git fetch upstream
git switch feat/android-chat
git merge upstream/main
```

This is a deliberate merge, not an automatic replacement of Android changes.

## Information needed from the backend owner

Ask the owner for these together:

1. The HTTPS API base URL, with no route appended.
2. The Firebase **Project ID** used by the API. A numeric Google Cloud project
   number is not the Project ID.
3. An Android app registration in that same Firebase project, using exactly
   `com.xiaoen0205.wobot`.
4. The development signing certificate's SHA-1 and SHA-256 registered on that app.
5. Google sign-in enabled, and the downloaded Android `google-services.json`
   containing a web OAuth client (`client_type: 3`).
6. Your verified Google login email added to the backend's `app.allowed_emails`.

The API accepts this project's Firebase ID tokens, not tokens from an unrelated
Firebase project. `/health` is public and proves only that the service is alive;
it does not prove authentication or chat access.

Get the development fingerprints without sharing the keystore itself:

```powershell
& "$env:JAVA_HOME\bin\keytool.exe" -list -v -alias androiddebugkey `
  -keystore "$env:USERPROFILE\.android\debug.keystore" `
  -storepass android -keypass android
```

If `JAVA_HOME` is unset, use the full path to Android Studio's `jbr/bin/keytool.exe`.
A debug build creates the default debug keystore if it does not exist yet.

## Configure Firebase

Install the Firebase CLI and FlutterFire CLI:

```powershell
npm install -g firebase-tools
dart pub global activate flutterfire_cli
firebase login
```

Add the npm global bin directory and Dart's pub-cache `bin` directory to PATH if
the commands are not found. The signed-in Firebase account needs access to the
owner's project. If it does not have access, ask the owner to provide the Android
client configuration; do not request a service-account key.

From `app/`, after the owner has registered the signing fingerprints:

```powershell
flutterfire configure --project=<PROJECT_ID> --platforms=android --android-package-name=com.xiaoen0205.wobot
```

Check that `android/app/google-services.json` and `lib/firebase_options.dart` name
the owner's project and the correct Android app. The Google Services Gradle plugin
reads the web OAuth client from the JSON; do not pass an iOS client ID on Android.
Both configuration files are gitignored. Keep any iOS Firebase configuration when
configuring additional platforms in the future.

## Configure and run the app

Create `.local/android.json` at the repository root, using a real URL locally:

```json
{
  "API_BASE_URL": "<API URL>"
}
```

`.local/` is ignored by Git. The backend URL is compiled into the APK, so rebuild
after changing it. Keep the real URL and Firebase configuration out of public
commits, following this repository's convention.

From `app/`:

```powershell
flutter devices
flutter run -d <ANDROID_DEVICE_ID> --dart-define-from-file=../.local/android.json
```

Use `flutter emulators` to list emulators and `flutter emulators --launch <ID>` to
start one. Do not reuse a different project's Firebase configuration.

## Checks without owner configuration

On a fresh checkout, `dart run tool/prepare_ci.dart` from `app/` creates clearly
marked fake Firebase configuration. It refuses to overwrite either existing file.
These files let checks and an APK build run; they cannot sign in. Do not use the
result as proof of integration with the real backend.

```powershell
flutter pub get --enforce-lockfile
dart run tool/prepare_ci.dart
flutter analyze
flutter test
flutter build apk --debug
```

Before generating real configuration, remove only these two files **after
confirming they still contain `wobot-ci-placeholder`**:
`lib/firebase_options.dart` and `android/app/google-services.json`. Then configure
the real project. Never replace real configuration with the placeholders.

App CI runs formatting, analysis, tests and the Android debug build using the fake
configuration. It cannot verify Google sign-in or the backend. Its APK has no API
URL. The upstream iOS camera channel is not opened on Android, and Robot lab shows
face tracking as unavailable.

## Text-chat acceptance

Use your own test account and test conversations against the owner's service:

- Sign in, sign out, and cancel sign-in without getting stuck.
- Verify account access and opening the conversation list.
- Send Chinese and English messages; replies appear incrementally.
- Stop a reply, retain the shown text, and retry stopped or failed replies.
- Create, reopen and delete test conversations; check titles and history after
  restarting the app.
- Lose the network and restore it; confirm the app reports the error and recovers.
- Confirm unauthorized accounts remain refused; never bypass the allowlist.

An HTTP 401 usually means token/project validation failed; a 403 with
`ACCOUNT_NOT_ALLOWED` means the verified email is not allowed. Check the Firebase
project, package name, signing SHA and web OAuth client if Google sign-in fails.

Voice, avatar generation, Bluetooth, Android face tracking, release signing and
Play distribution are later milestones. The release build no longer falls back to
the debug signing key. iOS changes require a separate macOS/Xcode verification.
