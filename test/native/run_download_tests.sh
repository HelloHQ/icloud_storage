#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/../.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

for platform in ios macos; do
  echo "Testing $platform download queries"
  package_dir="$test_dir/$platform"
  mkdir -p "$package_dir/Sources/ICloudDownload" "$package_dir/Tests/ICloudDownloadTests"
  cp "$repo_dir/test/native/Package.swift" "$package_dir/Package.swift"
  cp "$repo_dir/$platform/icloud_storage/Sources/icloud_storage/DownloadQuery.swift" "$package_dir/Sources/ICloudDownload/"
  cp "$repo_dir/test/native/DownloadQueryTests.swift" "$package_dir/Tests/ICloudDownloadTests/"
  xcrun swift test --package-path "$package_dir" --quiet
done
