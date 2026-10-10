# App Store screenshots

Every GitHub Release created from `main` includes a versioned ZIP containing the current App Store
screenshots. This release asset is the fastest path from CI to App Store Connect.

## Download the latest bundle

1. Open the [latest GitHub Release](https://github.com/Malaber/planini/releases/latest).
2. Under **Assets**, download `planini-app-store-screenshots-v<version>.zip`.
3. Extract the ZIP. It contains ready-to-upload PNGs grouped by platform and locale:

| Directory | App Store Connect destination | Size |
| --- | --- | --- |
| `iphone/en-US` | iPhone, English (U.S.) | 1284 x 2778 |
| `iphone/de-DE` | iPhone, German | 1284 x 2778 |
| `ipad/en-US` | iPad, English (U.S.) | 2064 x 2752 |
| `ipad/de-DE` | iPad, German | 2064 x 2752 |
| `watchos/en-US` | Apple Watch, English (U.S.) | 422 x 514 |
| `watchos/de-DE` | Apple Watch, German | 422 x 514 |

Using GitHub CLI:

```bash
gh release download --repo Malaber/planini --pattern 'planini-app-store-screenshots-*.zip'
```

## Upload to App Store Connect

1. Open [App Store Connect](https://appstoreconnect.apple.com/), select **Apps**, then Planini.
2. Select the app version under its platform in the sidebar.
3. Choose English (U.S.) or German from the language menu.
4. In **App Previews and Screenshots**, select the matching iPhone or iPad tab and drag in all PNGs
   from the corresponding directory.
5. Open **View All Sizes in Media Manager** to upload PNGs from the matching `watchos` directory.
6. Check screenshot order and save the version metadata.

Apple documents the current UI and requirements in
[Upload app previews and screenshots](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/).

## Download a branch or PR bundle

Branch CI runs expose the same files before merge:

1. Open the PR's **Checks** tab and select the check containing **Capture upload bundle**.
2. Follow the workflow summary link.
3. Download the `ios-marketing-screenshots` artifact from **Artifacts**.

Artifacts expire after seven days. GitHub Release assets do not use that CI retention window.

Using GitHub CLI:

```bash
gh run list --repo Malaber/planini --workflow CI --branch <branch> --limit 1
gh run download <run-id> --repo Malaber/planini --name ios-marketing-screenshots
```

## Generate locally

On macOS with Xcode installed:

```bash
.codex/setup.sh
.venv/bin/inv check-ios-marketing-screenshots
```

Output is written to `e2e-artifacts/ios-marketing-screenshots` using the same platform and locale
layout as the release ZIP.
