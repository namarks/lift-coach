#!/usr/bin/env bash
# Capture fictional data through real app screens. No provider or ASC writes.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="${1:-$repo_root/.artifacts/app-store-screenshots}"
if [[ $# -gt 1 || -e "$output" ]]; then
  echo 'Usage: capture-app-store-screenshots.sh [new-output-directory]' >&2
  echo 'Choose a new directory; existing screenshots are never overwritten.' >&2
  exit 2
fi
scratch="$(mktemp -d "${TMPDIR:-/tmp}/tres-fort-app-store-capture.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
if ! IOS_KEEP_RESULTS=1 IOS_EVIDENCE_DIR="$scratch/results" \
  bash "$repo_root/scripts/verify-ios.sh" \
    --runtime com.apple.CoreSimulator.SimRuntime.iOS-26-2 \
    --device com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max \
    --only-testing TresFortUITests/AppStoreScreenshotTests >"$scratch/verify.log" 2>&1; then
  cat "$scratch/verify.log" >&2
  # Retain failure evidence at the requested new location before cleaning the
  # owned staging directory. The simulator/build cleanup belongs to verify-ios.
  mkdir -p "$(dirname "$output")"
  mkdir "$output"
  if [[ -d "$scratch/results" ]]; then cp -R "$scratch/results" "$output/failed-results"; fi
  cp "$scratch/verify.log" "$output/verify.log"
  exit 1
fi
bundles=("$scratch"/results/*/Tests.xcresult)
[[ ${#bundles[@]} -eq 1 && -d "${bundles[0]}" ]] || { echo 'Missing unique test result' >&2; exit 1; }
evidence="$(dirname "${bundles[0]}")"
xcrun xcresulttool export attachments --path "${bundles[0]}" \
  --output-path "$scratch/attachments" --test-id AppStoreScreenshotTests
python3 - "$repo_root" "$evidence" "$scratch/attachments" "$output" <<'PY'
import datetime, hashlib, json, pathlib, re, shutil, struct, subprocess, sys
repo, evidence, attachments, output = map(pathlib.Path, sys.argv[1:])
sources = json.loads((evidence / 'sources.json').read_text())
for name, digest in sources.items():
    assert hashlib.sha256((repo / 'ios' / name).read_bytes()).hexdigest() == digest, f'Source changed during capture: {name}'
images = {}
for test in json.loads((attachments / 'manifest.json').read_text()):
    for item in test['attachments']:
        match = re.match(r'app-store-(\d{2}-[a-z]+)_', item['suggestedHumanReadableName'])
        if not match:
            continue
        name = match[1] + '.png'
        assert name not in images, f'Duplicate screenshot: {name}'
        source = attachments / item['exportedFileName']
        data = source.read_bytes()
        assert data[:8] == b'\x89PNG\r\n\x1a\n', f'Not PNG: {name}'
        assert struct.unpack('>II', data[16:24]) == (1320, 2868), f'Unexpected size: {name}'
        assert data[25] == 2, f'Expected opaque RGB: {name}'
        offset = 8
        while offset < len(data):
            length = struct.unpack('>I', data[offset:offset + 4])[0]
            assert data[offset + 4:offset + 8] != b'tRNS', f'Transparency is not allowed: {name}'
            offset += length + 12
        assert offset == len(data), f'Invalid PNG chunk length: {name}'
        images[name] = (source, hashlib.sha256(data).hexdigest())
expected = {'01-today.png', '02-runner.png', '03-workouts.png', '04-history.png', '05-feedback.png'}
assert set(images) == expected, f'Wrong screenshot set: {set(images)}'
output.mkdir(parents=True, exist_ok=False)
for name, (source, _) in images.items():
    shutil.copy2(source, output / name)
shutil.copy2(evidence / 'sources.json', output / 'sources.json')
shutil.copy2(evidence / 'xcodebuild.log', output / 'capture-tests.log')
def git(*args):
    return subprocess.check_output(['git', '-C', str(repo), *args], text=True).strip()
manifest = {
    'captured_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'source_head': git('rev-parse', 'HEAD'),
    'source_tree': git('rev-parse', 'HEAD^{tree}'),
    'working_tree_changes': git('status', '--porcelain'),
    'ios_source_manifest': 'sources.json',
    'test_evidence': 'capture-tests.log',
    'device': 'iPhone 17 Pro Max', 'runtime': 'iOS 26.2', 'locale': 'en_US',
    'configuration': 'Debug simulator; production views with fictional, network-isolated data',
    'image_size': [1320, 2868], 'images': {name: digest for name, (_, digest) in sorted(images.items())},
    'status': 'Draft assets. Visually review and match to the final selected release candidate before publication.',
    'specification': 'https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/'
}
(output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(f'Captured five draft screenshots in {output}')
PY
