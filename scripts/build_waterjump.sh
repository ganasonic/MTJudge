#!/bin/bash
set -euo pipefail
phase="${1:-check}"
root="/tmp/MTJudge-waterjump-source"
mkdir -p "$root"
rsync -a MTJudge MTJudge.xcodeproj MTJudgeTests MTJudgeUITests resource "$root/"
if [ -d MTJudgeWatch ]; then rsync -a MTJudgeWatch "$root/"; fi
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "$root/MTJudge.xcodeproj" -scheme MTJudge -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /tmp/MTJudge-waterjump-build IPHONEOS_DEPLOYMENT_TARGET=15.0 CODE_SIGNING_ALLOWED=NO build > "/tmp/MTJudge-$phase.log" 2>&1
 tail -n 3 "/tmp/MTJudge-$phase.log"
