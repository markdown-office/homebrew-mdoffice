#!/usr/bin/env bash
#
# Checks `update-formula.sh` against a release that is not a release.
#
# The point of the update script is that it does nothing when there is nothing
# to do: no release, a release the formula already describes, a release whose
# sums file disagrees with its assets. A tap that opens a pull request for
# nothing trains everyone to ignore its pull requests.
#
# The release is served by a plain file server over a directory that holds the
# files a release would hold. A path that is not there is a 404, which is what
# the GitHub API answers for a repository without a release.

set -euo pipefail

here="$(cd "$(dirname "${0}")" && pwd)"
root="$(dirname "${here}")"

work="$(mktemp -d)"
server_pid=""
cleanup() {
  if [[ -n "${server_pid}" ]]
  then
    kill "${server_pid}" 2>/dev/null || true
    # Reaping the job is what prints "Terminated"; the wait is what keeps it
    # out of the test's output.
    wait "${server_pid}" 2>/dev/null || true
  fi
  rm -rf "${work}"
}
trap cleanup EXIT

failures=0
check() {
  if [[ "${2}" == "${3}" ]]
  then
    echo "  ok: ${1}"
  else
    echo "  FAILED: ${1}"
    echo "    expected: ${3}"
    echo "    got:      ${2}"
    failures=$((failures + 1))
  fi
}

# The number of lines of the given text that match the given pattern.
count_of() {
  printf '%s\n' "${1}" | grep -c -- "${2}" || true
}

# "same" when the file still says what it said, "changed" when it does not.
state_of() {
  local content=""
  content="$(cat "${1}")"
  if [[ "${content}" == "${2}" ]]
  then
    echo "same"
  else
    echo "changed"
  fi
}

# "failed" when the exit status is not zero, "passed" when it is.
outcome_of() {
  if [[ "${1}" -ne 0 ]]
  then
    echo "failed"
  else
    echo "passed"
  fi
}

port="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
api="http://127.0.0.1:${port}"
www="${work}/www"
mkdir -p "${www}/repos/markdown-office/mdoffice/releases" "${www}/assets"

python3 -m http.server "${port}" --bind 127.0.0.1 --directory "${www}" >/dev/null 2>&1 &
server_pid=$!

for _ in {1..50}
do
  if curl -s -o /dev/null "${api}/assets/"
  then
    break
  fi
  sleep 0.1
done

export MDOFFICE_API="${api}"
export MDOFFICE_REPO="markdown-office/mdoffice"
export MDOFFICE_FORMULA="${work}/formula.rb"
export MDOFFICE_OUTPUT="${work}/formula.rb"

formula="${work}/formula.rb"
cp "${root}/Formula/mdoffice.rb" "${formula}"
placeholder="$(cat "${root}/Formula/mdoffice.rb")"

echo "no release"
status=0
output="$("${root}/tools/update-formula.sh" 2>&1)" || status=$?
count="$(count_of "${output}" 'No release')"
check "exits without an error" "${status}" "0"
check "says there is no release" "${count}" "1"
state="$(state_of "${formula}" "${placeholder}")"
check "leaves the formula alone" "${state}" "same"

echo "a release"
printf 'the macos binary\n' >"${www}/assets/mdoffice-1.2.3-macos-arm64"
printf 'the macos intel binary\n' >"${www}/assets/mdoffice-1.2.3-macos-x86_64"
printf 'the linux binary\n' >"${www}/assets/mdoffice-1.2.3-linux-x86_64"
printf 'the linux arm binary\n' >"${www}/assets/mdoffice-1.2.3-linux-aarch64"
macos_sum="$(shasum -a 256 "${www}/assets/mdoffice-1.2.3-macos-arm64" | cut -d' ' -f1)"
macos_intel_sum="$(shasum -a 256 "${www}/assets/mdoffice-1.2.3-macos-x86_64" | cut -d' ' -f1)"
linux_sum="$(shasum -a 256 "${www}/assets/mdoffice-1.2.3-linux-x86_64" | cut -d' ' -f1)"
linux_arm_sum="$(shasum -a 256 "${www}/assets/mdoffice-1.2.3-linux-aarch64" | cut -d' ' -f1)"
{
  printf '%s  mdoffice-1.2.3-macos-arm64\n' "${macos_sum}"
  printf '%s  mdoffice-1.2.3-macos-x86_64\n' "${macos_intel_sum}"
  printf '%s  mdoffice-1.2.3-linux-x86_64\n' "${linux_sum}"
  printf '%s  mdoffice-1.2.3-linux-aarch64\n' "${linux_arm_sum}"
} >"${www}/assets/SHA256SUMS"

cat >"${www}/repos/markdown-office/mdoffice/releases/latest" <<JSON
{
  "tag_name": "v1.2.3",
  "assets": [
    { "name": "mdoffice-1.2.3-macos-arm64", "browser_download_url": "${api}/assets/mdoffice-1.2.3-macos-arm64" },
    { "name": "mdoffice-1.2.3-macos-x86_64", "browser_download_url": "${api}/assets/mdoffice-1.2.3-macos-x86_64" },
    { "name": "mdoffice-1.2.3-linux-x86_64", "browser_download_url": "${api}/assets/mdoffice-1.2.3-linux-x86_64" },
    { "name": "mdoffice-1.2.3-linux-aarch64", "browser_download_url": "${api}/assets/mdoffice-1.2.3-linux-aarch64" },
    { "name": "SHA256SUMS", "browser_download_url": "${api}/assets/SHA256SUMS" }
  ]
}
JSON

status=0
output="$("${root}/tools/update-formula.sh" 2>&1)" || status=$?
written="$(cat "${formula}")"
check "exits without an error" "${status}" "0"
count="$(count_of "${written}" 'assets/mdoffice-1.2.3-macos-arm64')"
check "writes the macos url" "${count}" "1"
count="$(count_of "${written}" 'assets/mdoffice-1.2.3-macos-x86_64')"
check "writes the macos intel url" "${count}" "1"
count="$(count_of "${written}" 'assets/mdoffice-1.2.3-linux-x86_64')"
check "writes the linux url" "${count}" "1"
count="$(count_of "${written}" 'assets/mdoffice-1.2.3-linux-aarch64')"
check "writes the linux arm url" "${count}" "1"
count="$(count_of "${written}" "sha256 \"${macos_sum}\"")"
check "writes the macos checksum" "${count}" "1"
count="$(count_of "${written}" "sha256 \"${macos_intel_sum}\"")"
check "writes the macos intel checksum" "${count}" "1"
count="$(count_of "${written}" "sha256 \"${linux_sum}\"")"
check "writes the linux checksum" "${count}" "1"
count="$(count_of "${written}" "sha256 \"${linux_arm_sum}\"")"
check "writes the linux arm checksum" "${count}" "1"

echo "the same release"
before="$(cat "${formula}")"
status=0
output="$("${root}/tools/update-formula.sh" 2>&1)" || status=$?
count="$(count_of "${output}" 'already describes')"
state="$(state_of "${formula}" "${before}")"
check "exits without an error" "${status}" "0"
check "says the formula is already there" "${count}" "1"
check "leaves the formula alone" "${state}" "same"

echo "a release whose sums file lies"
printf '%s  mdoffice-1.2.3-macos-arm64\n' "0000000000000000000000000000000000000000000000000000000000000000" \
  >"${www}/assets/SHA256SUMS"
status=0
output="$("${root}/tools/update-formula.sh" 2>&1)" || status=$?
outcome="$(outcome_of "${status}")"
state="$(state_of "${formula}" "${before}")"
check "fails" "${outcome}" "failed"
check "leaves the formula alone" "${state}" "same"

echo "a release without the linux arm asset"
cat >"${www}/repos/markdown-office/mdoffice/releases/latest" <<JSON
{
  "tag_name": "v1.2.3",
  "assets": [
    { "name": "mdoffice-1.2.3-macos-arm64", "browser_download_url": "${api}/assets/mdoffice-1.2.3-macos-arm64" },
    { "name": "mdoffice-1.2.3-macos-x86_64", "browser_download_url": "${api}/assets/mdoffice-1.2.3-macos-x86_64" },
    { "name": "mdoffice-1.2.3-linux-x86_64", "browser_download_url": "${api}/assets/mdoffice-1.2.3-linux-x86_64" }
  ]
}
JSON
status=0
output="$("${root}/tools/update-formula.sh" 2>&1)" || status=$?
outcome="$(outcome_of "${status}")"
count="$(count_of "${output}" 'no asset named mdoffice-1.2.3-linux-aarch64')"
state="$(state_of "${formula}" "${before}")"
check "fails" "${outcome}" "failed"
check "says which asset is missing" "${count}" "1"
check "leaves the formula alone" "${state}" "same"

if [[ "${failures}" -ne 0 ]]
then
  echo "${failures} check(s) failed."
  exit 1
fi
echo "all checks passed."
