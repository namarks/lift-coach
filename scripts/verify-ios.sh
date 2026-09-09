#!/usr/bin/env bash
# Build and test an unsigned copy. Never reuse a person's simulator or keychain.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
usage() {
  echo 'Usage: npm run ios:verify -- --runtime com.apple.CoreSimulator.SimRuntime.iOS-26-2 --device com.apple.CoreSimulator.SimDeviceType.iPhone-17 [--only-testing Target[/Class[/method]]]'
}
runtime=''
device=''
test_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --runtime|--device|--only-testing)
      [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || { usage >&2; exit 2; }
      case "$1" in
        --runtime) runtime="$2" ;;
        --device) device="$2" ;;
        --only-testing) test_args+=("-only-testing:$2") ;;
      esac
      shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
[[ -n "$runtime" && -n "$device" ]] || { usage >&2; exit 2; }
for tool in xcodegen xcodebuild xcrun python3; do
  command -v "$tool" >/dev/null || { echo "Required tool missing: $tool" >&2; exit 1; }
done

scratch="$(mktemp -d "${TMPDIR:-/tmp}/tres-fort-ios.XXXXXX")"
simulator=''
evidence_root="${IOS_EVIDENCE_DIR:-$repo_root/.artifacts/ios}"
cleanup() {
  result=$?
  trap - EXIT
  if [[ -n "$simulator" ]]; then
    xcrun simctl shutdown "$simulator" >>"$scratch/cleanup.log" 2>&1 || true
    if ! xcrun simctl delete "$simulator" >>"$scratch/cleanup.log" 2>&1; then
      echo "Could not delete verification simulator $simulator; see cleanup.log" >&2
      result=1
    fi
  fi
  # Retain logs and the result bundle (including synthetic UI screenshots).
  # DerivedData, copied sources, and simulator data never become artifacts.
  if [[ "$result" -ne 0 || "${IOS_KEEP_RESULTS:-0}" == 1 ]]; then
    evidence="$evidence_root/$(basename "$scratch")"
    if mkdir -p "$evidence"; then
      for path in "$scratch"/*.log "$scratch"/*.json "$scratch"/*.xcresult; do
        if [[ -e "$path" ]] && ! cp -R "$path" "$evidence/"; then result=1; fi
      done
      echo "iOS verification evidence: $evidence"
    else
      echo "Could not retain verification evidence at $evidence" >&2
      result=1
    fi
  fi
  rm -rf "$scratch"
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

xcrun simctl list runtimes -j >"$scratch/runtimes.json"
xcrun simctl list devicetypes -j >"$scratch/devicetypes.json"
python3 - "$scratch" "$runtime" "$device" <<'PY'
import json, pathlib, sys
root, runtime, device = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
runtimes = json.loads((root / 'runtimes.json').read_text())['runtimes']
devices = json.loads((root / 'devicetypes.json').read_text())['devicetypes']
if not any(r['identifier'] == runtime and r.get('isAvailable') for r in runtimes):
    sys.exit('Selected runtime is not installed and available: ' + runtime)
if not any(d['identifier'] == device for d in devices):
    sys.exit('Selected device type is not installed: ' + device)
PY
python3 - "$repo_root/ios" "$scratch/ios" <<'PY'
import hashlib, json, pathlib, shutil, sys
shutil.copytree(sys.argv[1], sys.argv[2], ignore=shutil.ignore_patterns(
    '*.xcodeproj', 'DerivedData', 'build', '.bundle', 'vendor', 'fastlane',
    '*.xcuserstate', '.DS_Store', '.api_key.json'))
root = pathlib.Path(sys.argv[2])
manifest = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(root.rglob('*')) if p.is_file()}
(root.parent / 'sources.json').write_text(json.dumps(manifest, indent=2) + '\n')
PY
{
  xcodebuild -version
  xcodegen --version
  echo "Runtime: $runtime"
  echo "Device type: $device"
  git -C "$repo_root" rev-parse HEAD
  git -C "$repo_root" status --short
} >"$scratch/environment.log"
xcodegen generate --spec "$scratch/ios/project.yml" >"$scratch/xcodegen.log" 2>&1
simulator="$(xcrun simctl create "TresFort verification $(basename "$scratch")" "$device" "$runtime")"
echo "Verifying TresFort on $runtime / $device ($simulator)"
# Disable test cloning so every simulator this command creates has one owner.
if ! xcodebuild test -project "$scratch/ios/TresFort.xcodeproj" \
    -scheme TresFort -configuration Debug \
    -destination "platform=iOS Simulator,id=$simulator" \
    -derivedDataPath "$scratch/DerivedData" -resultBundlePath "$scratch/Tests.xcresult" \
    -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO \
    ${test_args[@]+"${test_args[@]}"} >"$scratch/xcodebuild.log" 2>&1; then
  tail -n 100 "$scratch/xcodebuild.log" >&2
  exit 1
fi
awk '/Executed [0-9]+ tests|\*\* TEST/{print}' "$scratch/xcodebuild.log"
