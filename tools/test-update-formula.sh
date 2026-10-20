#!/usr/bin/env bash
#
# Checks `update-formula.sh` against a release that is not a release.
#
# The point of the update script is that it does nothing when there is nothing
# to do: no release, a release the formula already describes, a release whose
# sums file disagrees with its assets. A tap that opens a pull request for
# nothing trains everyone to ignore its pull requests.

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(dirname "$here")"

work="$(mktemp -d)"
server_pid=""
cleanup() {
  if [ -n "$server_pid" ]; then
    kill "$server_pid" 2>/dev/null || true
    # Reaping the job is what prints "Terminated"; the wait is what keeps it
    # out of the test's output.
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT

failures=0
check() {
  if [ "$2" = "$3" ]; then
    echo "  ok: $1"
  else
    echo "  FAILED: $1"
    echo "    expected: $3"
    echo "    got:      $2"
    failures=$((failures + 1))
  fi
}

port="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
api="http://127.0.0.1:$port"

mkdir -p "$work/assets"
cat > "$work/server.py" <<'PYTHON'
import http.server
import os
import sys

root = sys.argv[1]
port = int(sys.argv[2])


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/repos/markdown-office/mdoffice/releases/latest":
            release = os.path.join(root, "release.json")
            if not os.path.exists(release):
                self.send_response(404)
                self.end_headers()
                return
            self.respond(200, open(release, "rb").read(), "application/json")
            return
        asset = os.path.join(root, "assets", os.path.basename(path))
        if not os.path.exists(asset):
            self.send_response(404)
            self.end_headers()
            return
        self.respond(200, open(asset, "rb").read(), "application/octet-stream")

    def respond(self, status, body, content_type):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


http.server.HTTPServer(("127.0.0.1", port), Handler).serve_forever()
PYTHON

python3 "$work/server.py" "$work" "$port" &
server_pid=$!

for _ in $(seq 1 50); do
  curl -s -o /dev/null "$api/repos/markdown-office/mdoffice/releases/latest" && break
  sleep 0.1
done

formula="$work/formula.rb"
cp "$root/Formula/mdoffice.rb" "$formula"
update() {
  MDOFFICE_API="$api" MDOFFICE_REPO="markdown-office/mdoffice" \
    MDOFFICE_FORMULA="$formula" MDOFFICE_OUTPUT="$formula" \
    "$root/tools/update-formula.sh" 2>&1
}

echo "no release"
output="$(update)" && status=0 || status=$?
check "exits without an error" "$status" "0"
check "says there is no release" "$(echo "$output" | grep -c 'No release')" "1"
check "leaves the formula alone" "$(cmp -s "$formula" "$root/Formula/mdoffice.rb" && echo same)" "same"

echo "a release"
printf 'the macos binary\n' > "$work/assets/mdoffice-1.2.3-macos-arm64"
printf 'the linux binary\n' > "$work/assets/mdoffice-1.2.3-linux-x86_64"
printf 'the sums file\n' > "$work/assets/SHA256SUMS"
macos_sum="$(shasum -a 256 "$work/assets/mdoffice-1.2.3-macos-arm64" | cut -d' ' -f1)"
linux_sum="$(shasum -a 256 "$work/assets/mdoffice-1.2.3-linux-x86_64" | cut -d' ' -f1)"
{
  printf '%s  mdoffice-1.2.3-macos-arm64\n' "$macos_sum"
  printf '%s  mdoffice-1.2.3-linux-x86_64\n' "$linux_sum"
  printf '%s  SHA256SUMS\n' "$(shasum -a 256 "$work/assets/SHA256SUMS" | cut -d' ' -f1)"
} > "$work/assets/SHA256SUMS"

cat > "$work/release.json" <<JSON
{
  "tag_name": "v1.2.3",
  "assets": [
    { "name": "mdoffice-1.2.3-macos-arm64", "browser_download_url": "$api/assets/mdoffice-1.2.3-macos-arm64" },
    { "name": "mdoffice-1.2.3-linux-x86_64", "browser_download_url": "$api/assets/mdoffice-1.2.3-linux-x86_64" },
    { "name": "SHA256SUMS", "browser_download_url": "$api/assets/SHA256SUMS" }
  ]
}
JSON

output="$(update)" && status=0 || status=$?
check "exits without an error" "$status" "0"
check "writes the macos url" "$(grep -c "assets/mdoffice-1.2.3-macos-arm64" "$formula")" "1"
check "writes the linux url" "$(grep -c "assets/mdoffice-1.2.3-linux-x86_64" "$formula")" "1"
check "writes the macos checksum" "$(grep -c "sha256 \"$macos_sum\"" "$formula")" "1"
check "writes the linux checksum" "$(grep -c "sha256 \"$linux_sum\"" "$formula")" "1"

echo "the same release"
before="$(cat "$formula")"
output="$(update)" && status=0 || status=$?
check "exits without an error" "$status" "0"
check "says the formula is already there" "$(echo "$output" | grep -c 'already describes')" "1"
check "leaves the formula alone" "$([ "$(cat "$formula")" = "$before" ] && echo same)" "same"

echo "a release whose sums file lies"
printf '%s  mdoffice-1.2.3-macos-arm64\n' "0000000000000000000000000000000000000000000000000000000000000000" \
  > "$work/assets/SHA256SUMS"
output="$(update)" && status=0 || status=$?
check "fails" "$([ "$status" -ne 0 ] && echo failed)" "failed"
check "leaves the formula alone" "$([ "$(cat "$formula")" = "$before" ] && echo same)" "same"

echo "a release without the linux asset"
cat > "$work/release.json" <<JSON
{
  "tag_name": "v1.2.3",
  "assets": [
    { "name": "mdoffice-1.2.3-macos-arm64", "browser_download_url": "$api/assets/mdoffice-1.2.3-macos-arm64" }
  ]
}
JSON
output="$(update)" && status=0 || status=$?
check "fails" "$([ "$status" -ne 0 ] && echo failed)" "failed"
check "says which asset is missing" "$(echo "$output" | grep -c 'no asset named mdoffice-1.2.3-linux-x86_64')" "1"
check "leaves the formula alone" "$([ "$(cat "$formula")" = "$before" ] && echo same)" "same"

if [ "$failures" -ne 0 ]; then
  echo "$failures check(s) failed."
  exit 1
fi
echo "all checks passed."
