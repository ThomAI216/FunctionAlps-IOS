#!/usr/bin/env bash
# The Foundation Track screenshots (Screenshots workflow, job "Shoot the Foundation Track"): one launch of the Debug
# app in its showcase mode per line of Scripts/track_shots.tsv (name, then the showcase arguments). Run from
# FunctionAlps/ with UDID, BUNDLE and TZONE set; writes shots/track/<name>.png.
set -uo pipefail
mkdir -p shots/track
while IFS=$'\t' read -r name args; do
  [ -z "$name" ] && continue
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  # shellcheck disable=SC2086
  SIMCTL_CHILD_TZ="$TZONE" xcrun simctl launch "$UDID" "$BUNDLE" $args -AppleLanguages "(en)" -AppleLocale "en_CH" >/dev/null
  case "$name" in
    *-a-home-p0) sleep 9 ;;
    *-a-home-*) sleep 11 ;;
    *-c-q*) sleep 10 ;;
    *) sleep 8 ;;
  esac
  xcrun simctl io "$UDID" screenshot --type=png "shots/track/$name.png" >/dev/null 2>&1 && echo "shot $name" || echo "FAILED $name"
done < Scripts/track_shots.tsv
ls shots/track | wc -l
