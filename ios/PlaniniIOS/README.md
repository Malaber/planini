# Planini iOS app

This folder contains a universal SwiftUI iPhone and iPad client for Planini plus a Swift package with automated tests for the app's core logic.

## Folder layout

- `Package.swift` builds the reusable `PlaniniCore` module and its test suite
- `Sources/PlaniniCore/` contains the backend URL persistence, passkey scaffolding, and authentication view model logic
- `App/` contains the SwiftUI application shell and the Apple passkey bridge for Xcode app targets
- `Tests/PlaniniCoreTests/` contains high-coverage tests for the app's core behavior

## Run tests locally

```bash
.venv/bin/inv check-ios-e2e
```

Useful native iOS Invoke targets:

- `.venv/bin/inv install-xcodegen`
- `.venv/bin/inv configure-ios-app --backend-url=https://your.domain --bundle-id=com.example.yourapp`
- `.venv/bin/inv start-ios-backend --backend-url=https://your.domain`
- `.venv/bin/inv check-ios-package`
- `.venv/bin/inv run-ios-e2e`
- `.venv/bin/inv check-ios-e2e`
- `.venv/bin/inv check-ios-marketing-screenshots`
- `.venv/bin/inv generate-ios-project`
- `.venv/bin/inv build-ios-simulator`
- `.venv/bin/inv run-ios-simulators-fresh`
- `.venv/bin/inv check-ios-ci`

### Common configure commands

Use the same `configure-ios-app` target in two common ways:

1. Normal live app build against the main hosted backend:
```bash
.venv/bin/inv configure-ios-app \
  --backend-url=https://planini.malaber.de \
  --bundle-id=de.malaber.planini \
  --development-team=VWKG94374J
```

2. Review-host build against one PR app while still using the shared review passkey host:
```bash
.venv/bin/inv configure-ios-app \
  --backend-url=https://pr-49.pr.planini.malaber.de \
  --passkey-domain=pr.planini.malaber.de \
  --bundle-id=de.malaber.planini \
  --development-team=VWKG94374J
```

The first form is the normal production-style configuration. The second form is
for native review testing, where the app talks to a specific PR deployment but
Apple passkeys still validate against the shared review host.

## Project setup in Xcode

1. Open Xcode 16 or newer on macOS.
2. Open `ios/PlaniniIOS/PlaniniApp.xcodeproj`.
3. Use the `Planini` scheme to build and run the native app on an iPhone or iPad simulator or device.
4. Open `ios/PlaniniIOS/Package.swift` in Xcode as needed to inspect or run the Swift package tests for `PlaniniCore`.

The app target supports both iPhone and iPad natively. The CI UI e2e matrix runs the same XCTest
suite on both device families and verifies that iPad uses the full native canvas instead of iPhone
compatibility mode.

## Included app flow

- build-time configured backend URL with `https://planini.malaber.de` as the default
- passkey login against `/api/v1/auth/login/options` and `/api/v1/auth/login/verify`
- bearer-token authenticated loading of households, lists, and list items
- list switching plus add, remove, check/uncheck, and edit item details
- liquid-glass inspired SwiftUI styling using material cards and gradients

## Local testing workflow

1. **Swift package checks (Linux/macOS):**
   ```bash
   .venv/bin/inv check-ios-package
   ```
2. **Live backend integration checks with the seeded passkey fixture (macOS):**
   ```bash
   .venv/bin/inv check-ios-e2e
   ```
   This Invoke target:
   - starts the FastAPI backend with `app/fixtures/review_seed_e2e.json`
   - keeps the backend session cookie for `/auth/login/options` and `/auth/login/verify`
   - signs a real WebAuthn assertion from the seeded private key fixture
   - verifies passkey login, list loading, add/edit/check/uncheck/delete item flows
3. **Generate the Xcode project if you need to regenerate it (macOS):**
   ```bash
   .venv/bin/inv generate-ios-project
   ```
4. **Build and run in Simulator (macOS):**
   ```bash
   .venv/bin/inv build-ios-simulator
   ```
5. **Reinstall and launch both paired simulators from scratch (macOS):**
   ```bash
   .venv/bin/inv run-ios-simulators-fresh
   ```
   This target:
   - boots the configured iPhone and Apple Watch simulators
   - uninstalls old app copies from both simulators
   - deletes a dedicated derived-data folder
   - rebuilds the app from scratch
   - installs the iPhone app and watch app
   - launches the iPhone app with the local backend/bootstrap env vars
   - launches the watch app after the iPhone app starts
6. **Capture repeatable App Store screenshots (macOS):**
   ```bash
   .venv/bin/inv check-ios-marketing-screenshots
   ```
   This uses a fresh polished fixture and an iPhone 14 Plus simulator to capture
   matching English and German sets under `en-US/` and `de-DE/`, then verifies
   every generated screenshot is the App Store-ready `1284x2778` size.
7. Launch from Xcode and verify:
   - the configured backend matches the build settings you generated the app with
   - passkey login succeeds for the selected backend
   - list switching works
   - adding/editing/checking/deleting items updates correctly
   - the device or simulator can satisfy the Apple passkey prompt

## Self-hosted builds

Use Invoke to stamp the app with your backend domain and bundle identifier before building:

```bash
.venv/bin/inv configure-ios-app \
  --backend-url=https://shopping.example.com \
  --bundle-id=com.example.shopping \
  --development-team=YOURTEAMID
```

That task updates:
- the iOS app's embedded backend URL
- the associated-domain entitlement for `webcredentials:<your host>`
- the generated Xcode project

The backend URL is no longer edited inside the app.

To start a local backend with a matching WebAuthn RP ID for that build:

```bash
.venv/bin/inv start-ios-backend --backend-url=https://shopping.example.com
```

That derives `WEBAUTHN_RP_ID` from the configured backend host automatically.

## Passkey login notes

- The native app now accepts the backend's current `/api/v1/auth/login/options` response shape directly, whether the WebAuthn options are top-level or nested under `publicKey`.
- The app relies on the `Set-Cookie` session from `/api/v1/auth/login/options` to complete `/api/v1/auth/login/verify`, so login tests should always use the same session between both requests.
- For local native passkey checks, use `localhost` as the browser-facing host and RP ID. `127.0.0.1` is not valid for WebAuthn passkey UX in Apple and Chromium clients.
- The app target now includes the Associated Domains entitlement for `webcredentials:planini.malaber.de`.
- Production passkey login still requires a real Apple team ID and bundle identifier that match the `appID` entries served by `https://planini.malaber.de/.well-known/apple-app-site-association`.
- A locally signed placeholder app such as `FAKETEAMID.com.example.planini` will be rejected by `AuthenticationServices`, even if the backend URL and RP ID are otherwise correct.
- Self-hosted builds work when the builder signs the app themselves and uses `configure-ios-app` so the bundle ID, associated domain, and backend host all match.
- An App Store build cannot support arbitrary self-hosted passkey domains at runtime, because Apple Associated Domains are static entitlements.

## Passkey deployment checklist

The app and backend now have a strict deployment contract for native Apple passkeys. Both sides must be configured together.

### App build requirements

1. Run `configure-ios-app` with the final backend URL and bundle identifier for the build you will sign:
   ```bash
   .venv/bin/inv configure-ios-app \
     --backend-url=https://shopping.example.com \
     --bundle-id=com.example.shopping \
     --development-team=YOURTEAMID
   ```
2. Sign the app with the Apple Developer team that will ship the build.
3. Confirm the generated entitlement includes `webcredentials:shopping.example.com`.
4. Remember that the final Apple app identifier is `TEAM_ID.bundle_id`, for example `ABCD123456.com.example.shopping`.

### Backend deployment requirements

1. Serve the backend over HTTPS on the same hostname you embedded into the app.
2. Set `APP_BASE_URL` to that public HTTPS origin.
3. Set `WEBAUTHN_RP_ID` to that hostname. `start-ios-backend` derives it automatically for local runs, but production deployments still need to set it explicitly.
4. Set `WEBCREDENTIALS_APPS` to the signed Apple app ID.
5. The backend now serves an Apple App Site Association file from that config at:
   - `https://shopping.example.com/.well-known/apple-app-site-association`
6. The file must include the signed app identifier under `webcredentials.apps`, for example:
   ```json
   {
     "webcredentials": {
       "apps": [
         "ABCD123456.com.example.shopping"
       ]
     }
   }
   ```
7. Keep the host in all four places identical:
   - the app's embedded backend URL
   - the `webcredentials:<host>` entitlement
   - `APP_BASE_URL`
   - the backend's `WEBAUTHN_RP_ID`

If any of those values drift apart, the simulator or device will fail passkey login before the app can complete `/api/v1/auth/login/verify`.

### Review deployment note

Review deployments can intentionally split the app host from the passkey host:

- app backend URL: `https://pr-<PR>.pr.planini.malaber.de`
- passkey entitlement and RP ID: `pr.planini.malaber.de`

That shared-review setup only works if `pr.planini.malaber.de` itself serves
the Apple App Site Association payload for the signed app ID. It is not enough
for only the individual `pr-<PR>` app host to serve the AASA response.

## Shipping to the App Store

1. Join the Apple Developer Program and create an App ID for the iOS app.
2. In Xcode, configure the bundle identifier, signing team, app icon, launch assets, and display metadata.
3. Add privacy disclosures in App Store Connect, including whether account identifiers or diagnostics are collected.
4. If passkeys are used in production, verify the associated domains and WebAuthn relying party configuration you will use for the final backend.
   This includes:
   - setting the final Apple Developer team and bundle identifier
   - adding the matching `webcredentials:` domain entitlement to the app
   - serving an Apple App Site Association file for that exact app identifier on the backend domain
   - setting `WEBAUTHN_RP_ID` on the backend to the same hostname the app uses
5. Test on physical devices, especially sign-in flows, keyboard behavior, and network error handling.
6. Archive the app in Xcode, validate it, and upload it through Organizer.
7. In App Store Connect, create the app record, complete screenshots, pricing, age rating, and submission notes.
8. Submit for App Review and be ready to provide a demo account or backend test environment if Apple asks for one.

### iPad release requirements

- The universal iPhone/iPad app uses the existing App ID, bundle identifier, signing certificate,
  provisioning profile, associated domains, App Group, and watch App IDs. No new Apple Developer
  group or capability is required solely for iPad support.
- App Store Connect requires iPad screenshots for a version that supports iPad. Capture and upload
  the required current iPad display-size screenshots before submitting the next version.
- Ad-hoc installation on a physical iPad requires registering that iPad UDID and regenerating the
  ad-hoc provisioning profile, exactly like adding another physical iPhone test device.
- Test passkeys, keyboard behavior, rotation, split view, and Stage Manager on a physical iPad
  before release.


## GitHub Actions automation

Two workflows now automate most of the iOS delivery path:

- `.github/workflows/ci.yml` runs Swift package tests on Linux, and runs native iOS backend e2e plus native iOS UI e2e as separate GitHub-hosted macOS jobs.
- `.github/workflows/ios-build-and-testflight.yml` runs the same native iOS backend/UI e2e jobs in parallel before optionally archiving/exporting/uploading signed app variants to TestFlight.

GitHub runs the native iOS checks as separate jobs so the backend e2e flow is not queued behind the
simulator UI e2e flow. Swift package coverage stays in the Linux Swift job, and the UI e2e
task performs the required Xcode project generation and simulator app build as part of
`xcodebuild test`.

The iOS workflow computes the app version from the same git tags as the web release workflow:

- `MARKETING_VERSION` uses the computed base version, for example `0.2.21`.
- `CURRENT_PROJECT_VERSION` uses the GitHub run number, a variant code, and run attempt, for example `418.10.1` for production and `418.20.1` for review.

No version bump commit is needed for normal TestFlight uploads.

### iOS build variants

The workflow builds signed variants when upload is enabled. Pushes to `main` build only the
production variant. Branches with an open PR build production plus review variants.

- `production`
  - backend URL: `IOS_PRODUCTION_BACKEND_URL`, default `https://planini.top`
  - passkey domain: `IOS_PRODUCTION_PASSKEY_DOMAIN`, default `planini.top`
  - display name: `Planini`
- `review`
  - backend URL: `https://pr-<PR>.pr.planini.malaber.de`
  - passkey domain: `IOS_REVIEW_PASSKEY_DOMAIN`, default `pr.planini.malaber.de`
  - display name: `Planini Review`

For branch pushes, the review PR number is auto-detected from the open pull request for that branch.
For manual workflow runs on PR branches, pass `review_pr_number` if the branch cannot be auto-detected.
TestFlight uploads only run for trusted `Malaber` repository pushes or manual dispatches on `main` or with an open PR/review PR number. Pushes without `main` or a PR still run native iOS checks, but do not upload to TestFlight.

Both variants may use the same bundle identifier, in which case TestFlight shows them as builds of the same app and only one can be installed on a device at a time. To install production and review side by side, create a second App Store Connect app and Apple App ID for the review variant, then set `IOS_REVIEW_BUNDLE_IDENTIFIER` and the review provisioning profile secrets below.

### Secrets needed for TestFlight uploads

Set these GitHub Actions secrets before dispatching the TestFlight upload workflow:

- `KEYCHAIN_PASSWORD`
- `BUILD_CERTIFICATE_BASE64`
- `P12_PASSWORD`
- `BUILD_PROVISION_PROFILE_BASE64`
- `BUILD_WATCH_APP_PROVISION_PROFILE_BASE64`
- `BUILD_WATCH_EXTENSION_PROVISION_PROFILE_BASE64`
- `BUILD_WATCH_WIDGET_PROVISION_PROFILE_BASE64`
- `IOS_REVIEW_BUNDLE_IDENTIFIER` (optional; defaults to `IOS_BUNDLE_IDENTIFIER`)
- `BUILD_REVIEW_PROVISION_PROFILE_BASE64` (optional; defaults to `BUILD_PROVISION_PROFILE_BASE64`)
- `BUILD_REVIEW_WATCH_APP_PROVISION_PROFILE_BASE64` (optional; defaults to `BUILD_WATCH_APP_PROVISION_PROFILE_BASE64`)
- `BUILD_REVIEW_WATCH_EXTENSION_PROVISION_PROFILE_BASE64` (optional; defaults to `BUILD_WATCH_EXTENSION_PROVISION_PROFILE_BASE64`)
- `BUILD_REVIEW_WATCH_WIDGET_PROVISION_PROFILE_BASE64` (optional; defaults to `BUILD_WATCH_WIDGET_PROVISION_PROFILE_BASE64`)
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_PRIVATE_KEY`

The workflow extracts provisioning profile names from the uploaded `.mobileprovision` files on the runner, so profile name secrets are not needed.

The workflow commits these non-secret signing constants directly:

- Apple team ID: `VWKG94374J`
- production bundle ID: `de.malaber.planini`

Each watch target needs its own profile because Apple provisioning profiles are bound to one App ID. Create App Store distribution profiles for:

- `de.malaber.planini`
- `de.malaber.planini.watchkitapp`
- `de.malaber.planini.watchkitapp.watchkitextension`
- `de.malaber.planini.watchkitapp.widget`

The upload job uses the GitHub Actions environment named `testflight`, so the secrets above should be configured as environment secrets on that environment.

Set these optional GitHub Actions variables to override default domains:

- `IOS_PRODUCTION_BACKEND_URL`
- `IOS_PRODUCTION_PASSKEY_DOMAIN`
- `IOS_REVIEW_PASSKEY_DOMAIN`

### Ad-hoc device artifacts

App Store signed IPAs should be installed through TestFlight. To test a CI-built IPA directly on a registered iPhone without TestFlight, create an Ad Hoc provisioning profile that includes the device UDID and the same bundle identifier/capabilities, then set:

- `AD_HOC_PROVISION_PROFILE_BASE64`
- `AD_HOC_WATCH_APP_PROVISION_PROFILE_BASE64`
- `AD_HOC_WATCH_EXTENSION_PROVISION_PROFILE_BASE64`
- `AD_HOC_WATCH_WIDGET_PROVISION_PROFILE_BASE64`
- `AD_HOC_REVIEW_PROVISION_PROFILE_BASE64` (optional; defaults to `AD_HOC_PROVISION_PROFILE_BASE64`)
- `AD_HOC_REVIEW_WATCH_APP_PROVISION_PROFILE_BASE64` (optional; defaults to `AD_HOC_WATCH_APP_PROVISION_PROFILE_BASE64`)
- `AD_HOC_REVIEW_WATCH_EXTENSION_PROVISION_PROFILE_BASE64` (optional; defaults to `AD_HOC_WATCH_EXTENSION_PROVISION_PROFILE_BASE64`)
- `AD_HOC_REVIEW_WATCH_WIDGET_PROVISION_PROFILE_BASE64` (optional; defaults to `AD_HOC_WATCH_WIDGET_PROVISION_PROFILE_BASE64`)

Run the workflow manually with `export_ad_hoc = true`. It uploads `*-ad-hoc.ipa` artifacts that can be installed with Apple Configurator or Xcode's Devices and Simulators window.

### How to use the workflow

1. Push the branch to GitHub. Pushes run the native iOS checks and upload signed TestFlight variants when signing secrets are present. `main` uploads production only; PR branches upload production plus review.
2. For a manual dry run, run the workflow with `upload_to_testflight = false`.
3. For a manual upload, run it with `upload_to_testflight = true`.
4. For local device sanity checks without TestFlight, also set `export_ad_hoc = true`, download the ad-hoc artifact, and install it on a device included in the ad-hoc profile.
