#!/usr/bin/env bash
set -euo pipefail

package_dir=$(cd "$(dirname "$0")/.." && pwd)
marketing_version=${1:-}
build_number=${2:-}
if [[ ! "$marketing_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
   [[ ! "$build_number" =~ ^[1-9][0-9]*(\.[0-9]+){0,2}$ ]]; then
  echo "Usage: $0 <marketing-version> <build-number>" >&2
  exit 2
fi

release_dir=$(mktemp -d "${TMPDIR:-/tmp}/planini-testflight.XXXXXX")
archive_path="$release_dir/Planini.xcarchive"
echo "Release directory: $release_dir"
cd "$package_dir"

env PATH=/usr/bin:/bin:/usr/sbin:/sbin /usr/bin/xcodebuild \
  -project PlaniniApp.xcodeproj -scheme Planini -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$archive_path" \
  DEVELOPMENT_TEAM=VWKG94374J \
  MARKETING_VERSION="$marketing_version" CURRENT_PROJECT_VERSION="$build_number" \
  CODE_SIGN_STYLE=Automatic PROVISIONING_PROFILE_SPECIFIER= \
  -allowProvisioningUpdates archive

env PATH=/usr/bin:/bin:/usr/sbin:/sbin /usr/bin/xcodebuild \
  -exportArchive -archivePath "$archive_path" -exportPath "$release_dir/export" \
  -exportOptionsPlist "$package_dir/ExportOptions.TestFlight.plist" \
  -allowProvisioningUpdates
echo "TestFlight upload accepted. Archive: $archive_path"
