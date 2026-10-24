#!/usr/bin/env bash
#
# Checks `update-winget-manifest.sh` against a release that is not a release.
#
# The point of the update script is that it does nothing when there is nothing
# to do: no release, a release without the executable the manifest installs. A
# script that opens a pull request for nothing trains everyone to ignore its
# pull requests.
#
# The release is served over a directory that holds the files a release would
# hold, and the GitHub API is served by `tools/fake-github-api.py`, which
# answers the endpoints the script calls and refuses the ones that can only be
# used once — as GitHub does. A path that is not there is a 404, which is what
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

python3 "${root}/tools/fake-github-api.py" "${port}" "${www}" >/dev/null 2>&1 &
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
export MDOFFICE_WINGET_OUTPUT="${work}/manifests"

manifests="${work}/manifests"
directory="${manifests}/m/markdown-office/mdoffice"

echo "no release"
status=0
output="$("${root}/tools/update-winget-manifest.sh" 2>&1)" || status=$?
count="$(count_of "${output}" 'No release')"
check "exits without an error" "${status}" "0"
check "says there is no release" "${count}" "1"
check "writes nothing" "$([[ -d "${directory}" ]] && echo yes || echo no)" "no"

echo "a release"
printf 'the windows binary\n' >"${www}/assets/mdoffice-1.2.3-windows-x64.exe"
sum="$(shasum -a 256 "${www}/assets/mdoffice-1.2.3-windows-x64.exe" | cut -d' ' -f1)"

cat >"${www}/repos/markdown-office/mdoffice/releases/latest" <<JSON
{
  "tag_name": "v1.2.3",
  "published_at": "2026-10-20T10:00:00Z",
  "assets": [
    { "name": "mdoffice-1.2.3-windows-x64.exe", "browser_download_url": "${api}/assets/mdoffice-1.2.3-windows-x64.exe" }
  ]
}
JSON

status=0
output="$("${root}/tools/update-winget-manifest.sh" 2>&1)" || status=$?
check "exits without an error" "${status}" "0"

version_manifest="${directory}/1.2.3/markdown-office.mdoffice.yaml"
installer_manifest="${directory}/1.2.3/markdown-office.mdoffice.installer.yaml"
locale_manifest="${directory}/1.2.3/markdown-office.mdoffice.locale.en-US.yaml"

check "writes the version manifest" "$([[ -f "${version_manifest}" ]] && echo yes || echo no)" "yes"
check "writes the installer manifest" "$([[ -f "${installer_manifest}" ]] && echo yes || echo no)" "yes"
check "writes the locale manifest" "$([[ -f "${locale_manifest}" ]] && echo yes || echo no)" "yes"

version_text="$(cat "${version_manifest}")"
check "names the package" "$(count_of "${version_text}" 'PackageIdentifier: markdown-office.mdoffice')" "1"
check "names the version" "$(count_of "${version_text}" 'PackageVersion: 1.2.3')" "1"
check "is a version manifest" "$(count_of "${version_text}" 'ManifestType: version')" "1"

installer_text="$(cat "${installer_manifest}")"
check "installs a portable command" "$(count_of "${installer_text}" 'InstallerType: portable')" "1"
check "names the command" "$(count_of "${installer_text}" '^- mdoffice$')" "1"
check "writes the url" "$(count_of "${installer_text}" 'assets/mdoffice-1.2.3-windows-x64.exe')" "1"
check "writes the checksum" "$(count_of "${installer_text}" "InstallerSha256: ${sum}")" "1"
check "writes the release date" "$(count_of "${installer_text}" 'ReleaseDate: 2026-10-20')" "1"
check "is an installer manifest" "$(count_of "${installer_text}" 'ManifestType: installer')" "1"

locale_text="$(cat "${locale_manifest}")"
check "names the package" "$(count_of "${locale_text}" 'PackageIdentifier: markdown-office.mdoffice')" "1"
check "is a locale manifest" "$(count_of "${locale_text}" 'ManifestType: defaultLocale')" "1"

echo "a release without the windows asset"
cat >"${www}/repos/markdown-office/mdoffice/releases/latest" <<JSON
{
  "tag_name": "v1.2.3",
  "published_at": "2026-10-20T10:00:00Z",
  "assets": [
    { "name": "mdoffice-1.2.3-macos-arm64", "browser_download_url": "${api}/assets/mdoffice-1.2.3-macos-arm64" }
  ]
}
JSON

status=0
output="$("${root}/tools/update-winget-manifest.sh" 2>&1)" || status=$?
outcome="$(outcome_of "${status}")"
count="$(count_of "${output}" 'no asset named mdoffice-1.2.3-windows-x64.exe')"
check "fails" "${outcome}" "failed"
check "says which asset is missing" "${count}" "1"

# The workflow runs every day and the release does not change every day, so the
# second run for a version is the ordinary case rather than an accident. It has
# to succeed: the branch is there already and the pull request is open already,
# and GitHub refuses both a reference that exists and a second pull request for
# the same branch.
echo "the same release, twice, with the pull request open"
cat >"${www}/repos/markdown-office/mdoffice/releases/latest" <<JSON
{
  "tag_name": "v1.2.3",
  "published_at": "2026-10-20T10:00:00Z",
  "assets": [
    { "name": "mdoffice-1.2.3-windows-x64.exe", "browser_download_url": "${api}/assets/mdoffice-1.2.3-windows-x64.exe" }
  ]
}
JSON

export MDOFFICE_WINGET_SUBMIT="true"

status=0
output="$("${root}/tools/update-winget-manifest.sh" 2>&1)" || status=$?
check "the first run exits without an error" "${status}" "0"
count="$(count_of "${output}" 'The pull request is')"
check "the first run opens the pull request" "${count}" "1"

status=0
output="$("${root}/tools/update-winget-manifest.sh" 2>&1)" || status=$?
check "the second run exits without an error" "${status}" "0"
count="$(count_of "${output}" 'is already open')"
check "the second run says the pull request is open" "${count}" "1"

if [[ "${failures}" -ne 0 ]]
then
  echo "${failures} check(s) failed."
  exit 1
fi
echo "all checks passed."
