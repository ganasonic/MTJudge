#!/bin/sh
set -eu
# Run once after a fresh checkout. No network/download is performed by the app or Xcode build.
base=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
archive=$(mktemp -t mtjudge-opencv)
work=$(mktemp -d -t mtjudge-opencv)
trap 'rm -f "$archive"; rm -rf "$work"' EXIT HUP INT TERM
curl -L --fail --retry 2 -o "$archive" https://github.com/opencv/opencv/releases/download/4.12.0/opencv-4.12.0-ios-framework.zip
printf '%s  %s\n' '86b42c9f141cd9169b91be2fc380b0e556a88a95c98ccc8e7aef8349ab74cf70' "$archive" | shasum -a 256 -c -
unzip -q "$archive" -d "$work"
if [ -e "$base/opencv2.framework" ]; then
    printf '%s\n' 'opencv2.framework already exists; left unchanged.'
    exit 0
fi
mv "$work/opencv2.framework" "$base/opencv2.framework"
printf '%s\n' 'OpenCV 4.12.0 is ready.'
