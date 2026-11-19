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

Use a dedicated debug key for this checkout when the machine-wide default key
was already registered with the same package in a different Firebase project.
Google requires each package and SHA-1 pair to be unique across projects; using
another signing key avoids deleting the older project's OAuth client.

From the repository root, create the key once (never overwrite an existing key):

```powershell
New-Item -ItemType Directory -Path .local -Force
& "$env:JAVA_HOME\bin\keytool.exe" -genkeypair `
  -keystore .local/android-debug.keystore -storepass android -keypass android `
  -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 `
  -dname "CN=Android Debug,O=Android,C=TW"
```

Gradle automatically uses this file for debug signing when present; otherwise it
uses the machine-wide default debug key. CI uses that default key with fake Firebase
configuration. The `android` password is the standard debug-only password; this
keystore must never be used for a published release.

From the repository root, get its fingerprints without sharing the key itself:

```powershell
& "$env:JAVA_HOME\bin\keytool.exe" -list -v -alias androiddebugkey `
  -keystore .local/android-debug.keystore `
  -storepass android -keypass android
```

If `JAVA_HOME` is unset, use the full path to Android Studio's `jbr/bin/keytool.exe`.
Back up the dedicated key securely so Firebase registration remains stable across
development sessions. If you change keys, the owner must register the new SHA.
A build signed with a different key cannot update an installed build of the same
package: use a fresh emulator or remove only your disposable smoke-test install.

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

On Windows, use `flutter test --concurrency=1` if the existing voice setup tests
race while removing temporary files in parallel. CI runs the suite on Linux.
App CI can also be started manually from the fork's Actions page.

## Text-chat acceptance

### Optional signed-in integration test

The opt-in test in `app/integration_test/live_chat_test.dart` exercises the real
Android app and backend. It uses the Firebase SDK's existing signed-in session;
sign in manually in the normal app first, using the same package and debug key.
It never automates Google authentication or exports an ID token.

Add `LIVE_TEST_EMAIL` to the ignored `.local/android.json`, alongside `API_BASE_URL`:

```json
{
  "API_BASE_URL": "<API URL>",
  "LIVE_TEST_EMAIL": "<TEST_EMAIL>"
}
```

From `app/`, run against the owner's configured backend and a signed-in device:

```powershell
.\tool\test_live_chat.ps1 -DeviceId <ANDROID_DEVICE_ID>
```

The Windows helper always preserves the installed app. The equivalent direct
command, also suitable for other development platforms, is:

```powershell
flutter test integration_test/live_chat_test.dart -d <ANDROID_DEVICE_ID> `
  --no-uninstall `
  --dart-define-from-file=../.local/android.json `
  --dart-define=RUN_LIVE_CHAT_TESTS=true --reporter expanded
```

This makes real model requests. It checks English and Chinese replies, a title,
stopping after the first streamed text, the server's saved partial reply, retry
without duplicating the turn, history reopening and deletion. It creates its own
conversation, removes that conversation in cleanup, and leaves existing chats
alone. Without `RUN_LIVE_CHAT_TESTS=true`, the test is skipped. Standard CI uses
fake configuration and does not run this live test.

Keep `--no-uninstall`: Flutter otherwise removes the test app after the run and
clears its local sign-in state. The test replaces the native keyboard channel
with Flutter's test input while entering text; check native keyboard behavior
separately on a device.

After the test, launch the normal app again with the run command above to replace
the test runner build. A process restart and any native sign-in prompts still need
their separate device checks.

### Device checklist

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

### Speech input and microphone permission

In a debug build, open **Settings > Developer > Voice lab**. Select `zh-TW` or
`en-US`, tap the microphone, and allow microphone access when Android asks. Speech
input also uses the same engine in Avatar mode; the lab needs no avatar or voice
generation and sends no recognized text to the backend.

Android speech input requires Android 12 or newer and an available on-device
recognition service. The app checks this before requesting access and again before
listening. The plugin otherwise permits a default-recognizer fallback; Wobot blocks
that path to preserve local speech recognition. Text chat remains available on
unsupported devices. A service can exist without a model for the selected language:
download its offline model if offered in the phone's speech-service settings, or
try another language or phone. Device/OEM language support varies; an available
recognizer does not imply support for either lab language.

An unsupported language and a missing model have separate messages. On Android 13
or newer, a missing model offers **Download offline model** in Voice lab and Avatar
mode. It requests the selected language from the on-device service; Android 14+
reports readiness, scheduling or failure when the service supports download events.
A scheduled/requested download is not reported as ready. Keep the device online
and retry after completion. The service may require its own download confirmation;
this flow records no speech and has no cloud-recognition fallback.

Only microphone permission is requested for speech input; Bluetooth microphone
support is disabled for this milestone. A denial shows **Open Settings**, which
opens Wobot's Android app settings. Allow microphone access, return to the app, and
tap again. No microphone request occurs at sign-in or during text chat. Recording
stops when the app is hidden. Recognition errors never submit partial questions in
Avatar mode.

Run the read-only native capability smoke test on a connected Android device:

```powershell
flutter test integration_test/android_voice_test.dart -d <ANDROID_DEVICE_ID> `
  --no-uninstall --dart-define-from-file=../.local/android.json
```

This checks native channels and, on unsupported devices, the real lab's guidance
without granting permission or recording audio. Reinstall the normal debug APK
afterward with `adb install -r` to preserve sign-in.

The following still require a person on a suitable physical Android phone:

- Deny microphone permission; verify **Open Settings**, allow access, then retry.
- Speak two consecutive questions in both supported languages and check their text.
- Stop manually, wait for silence, and leave the app while listening.
- With downloaded models, repeat in airplane mode to verify offline recognition.
- Disable system microphone access and check the error/recovery message.

Avatar generation, Bluetooth, Android face tracking, release signing and
Play distribution are later milestones. The release build no longer falls back to
the debug signing key. iOS changes require a separate macOS/Xcode verification.
