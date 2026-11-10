# Sign language video prediction

The app retains its camera and recognition home screen. Use **Upload** on the
camera screen to choose a video, upload its raw bytes to `POST /predict`, and
display only the returned Korean sentence. Uploads use
`application/octet-stream` and are limited to 90 MiB.

## Local API configuration

Copy `config/dev.json.example` to `config/dev.json`, then replace the
placeholder API token with your local token. The development file is excluded
from Git.

```json
{
  "API_BASE_URL": "https://interactive-anderson-scope-lang.trycloudflare.com",
  "API_TOKEN": "your-local-api-token"
}
```

In PowerShell:

```powershell
Copy-Item config/dev.json.example config/dev.json
notepad config/dev.json
```

The URL is configurable and defaults to the current tunnel URL. Use the local
file when running the app:

```powershell
flutter run --dart-define-from-file=config/dev.json
```

You can also configure `API_BASE_URL` and `API_TOKEN` with individual
`--dart-define` values. If the token is not configured, the app asks you to
configure it before uploading.

**Security:** A token compiled into a distributed mobile app can be extracted.
Do not use a long-lived or privileged API token in a production app. Use a
secure authentication flow and a server-side proxy that keeps API credentials
off the device.

## Run on a phone

Install Flutter and the Android SDK, enable developer options and USB debugging
on an Android phone, connect it, then run:

```powershell
flutter devices
flutter run --dart-define-from-file=config/dev.json
```

For iPhone, use a Mac with Xcode installed, open the project there, select a
signed iOS device, and run the same `flutter run` command with the local config.
The iOS document picker does not require photo-library access permission.
Android uses the system video picker and requires only the `INTERNET` permission
for API access; no broad media/storage permission is needed.

## Check the project

```powershell
dart format lib test
flutter analyze
flutter test
```
