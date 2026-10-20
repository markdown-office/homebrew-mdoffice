#!/usr/bin/env bash
#
# Writes the formula for the latest `mdoffice` release.
#
# A formula carries a checksum, and a checksum can only come from a file that
# exists. While `markdown-office/mdoffice` has no release there is no file, so
# this leaves the formula alone and says so.
#
# The asset names are the ones the release workflow publishes, and the ones
# this repository's README documents:
#
#   mdoffice-<version>-macos-arm64
#   mdoffice-<version>-linux-x86_64
#   SHA256SUMS
#
# Environment:
#   MDOFFICE_API      the GitHub API to ask           (default https://api.github.com)
#   MDOFFICE_REPO     the repository to ask about     (default markdown-office/mdoffice)
#   MDOFFICE_FORMULA  the formula to compare against  (default Formula/mdoffice.rb)
#   MDOFFICE_OUTPUT   where to write the formula      (default $MDOFFICE_FORMULA)
#   GITHUB_TOKEN      sent to the API when it is set

set -euo pipefail

api="${MDOFFICE_API:-https://api.github.com}"
repo="${MDOFFICE_REPO:-markdown-office/mdoffice}"
formula="${MDOFFICE_FORMULA:-Formula/mdoffice.rb}"
output="${MDOFFICE_OUTPUT:-${formula}}"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

curl_options=(--silent --show-error --fail --location --retry 3
  --header "Accept: application/vnd.github+json")
if [[ -n "${GITHUB_TOKEN:-}" ]]
then
  curl_options+=(--header "Authorization: Bearer ${GITHUB_TOKEN}")
fi

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1
  then
    sha256sum "${1}" | cut -d' ' -f1
  else
    shasum -a 256 "${1}" | cut -d' ' -f1
  fi
}

asset_url() {
  jq -r --arg name "${1}" '[.assets[] | select(.name == $name) | .browser_download_url][0] // ""' \
    "${work}/release.json"
}

# The checksum of a file in `SHA256SUMS`, whether it is written bare or with a
# path in front of it, and whether it is marked as binary mode.
sum_for() {
  if [[ ! -f "${work}/SHA256SUMS" ]]
  then
    return 0
  fi
  awk -v want="${1}" '
    { name = $2; sub(/^\*/, "", name); sub(/.*\//, "", name); if (name == want) print $1 }
  ' "${work}/SHA256SUMS"
}

# Downloads one asset and puts its URL and checksum in `<prefix>_url` and
# `<prefix>_checksum`.
resolve_asset() {
  local platform="${1}"
  local prefix="${2}"
  local name="mdoffice-${version}-${platform}"
  local url=""
  local checksum=""
  local expected=""

  url="$(asset_url "${name}")"
  if [[ -z "${url}" ]]
  then
    echo "The release ${tag} has no asset named ${name}. It has:" >&2
    jq -r '.assets[].name' "${work}/release.json" >&2
    exit 1
  fi

  if ! curl "${curl_options[@]}" --output "${work}/${name}" "${url}"
  then
    echo "Could not download ${url}" >&2
    exit 1
  fi
  checksum="$(sha256_of "${work}/${name}")"

  expected="$(sum_for "${name}")"
  if [[ -z "${expected}" ]]
  then
    echo "SHA256SUMS has no entry for ${name}; the checksum was computed from the download."
  elif [[ "${expected}" != "${checksum}" ]]
  then
    echo "SHA256SUMS says ${name} is ${expected} and the download hashes to ${checksum}." >&2
    exit 1
  fi

  printf -v "${prefix}_url" '%s' "${url}"
  printf -v "${prefix}_checksum" '%s' "${checksum}"
}

status="$(curl "${curl_options[@]}" --output "${work}/release.json" --write-out '%{http_code}' \
  "${api}/repos/${repo}/releases/latest" || true)"

case "${status}" in
  200) ;;
  404)
    echo "No release of ${repo} yet. The formula is left as it is."
    exit 0
    ;;
  *)
    echo "The GitHub API answered ${status} for ${api}/repos/${repo}/releases/latest." >&2
    exit 1
    ;;
esac

tag="$(jq -r '.tag_name // ""' "${work}/release.json")"
if [[ -z "${tag}" ]]
then
  echo "The latest release of ${repo} has no tag." >&2
  exit 1
fi
version="${tag#v}"
echo "The latest release of ${repo} is ${tag}."

sums_url="$(asset_url "SHA256SUMS")"
if [[ -n "${sums_url}" ]]
then
  curl "${curl_options[@]}" --output "${work}/SHA256SUMS" "${sums_url}"
else
  echo "The release has no SHA256SUMS; the checksums are computed from the assets."
fi

resolve_asset macos-arm64 macos
resolve_asset linux-x86_64 linux

# The template is written to a file first: a heredoc inside a command
# substitution is parsed by bash as a nested command, and an apostrophe in the
# body of a quoted one ends the quoting early.
cat >"${work}/template.rb" <<'RUBY'
class Mdoffice < Formula
  desc "Markdown to Word and to PowerPoint, as a command-line tool"
  homepage "https://github.com/markdown-office/mdoffice"
  license "MIT"

  # This is a formula and not a cask, and it has to stay one.
  #
  # Homebrew re-adds the quarantine flag to what a *cask* downloads, because a
  # cask's payload is an application bundle that has to be opened. `mdoffice` is
  # a command: it installs into `$(brew --prefix)/bin` and there is no bundle to
  # open. As a cask it would give every user a Gatekeeper dialog over a
  # program that has no application.

  on_macos do
    on_arm do
      url "@@MACOS_URL@@"
      sha256 "@@MACOS_SHA256@@"
    end
  end

  on_linux do
    on_intel do
      url "@@LINUX_URL@@"
      sha256 "@@LINUX_SHA256@@"
    end
  end

  def install
    # A bare download is staged under the name its URL ends in, and the only
    # file in the staging directory is the one that was downloaded.
    binaries = Dir["mdoffice-*"]
    raise "expected one mdoffice binary, found #{binaries.inspect}" unless binaries.one?

    bin.install binaries.first => "mdoffice"
  end

  def caveats
    return unless OS.mac?

    <<~EOS
      The macOS binary is ad-hoc signed, not notarised. Homebrew quarantines
      casks and not formulae, so nothing here is quarantined and Gatekeeper does
      not ask. A copy fetched from the release page with a browser is
      quarantined, and that one needs `xattr -d com.apple.quarantine mdoffice`
      before it will run.
    EOS
  end

  test do
    assert_match "mdoffice", shell_output("#{bin}/mdoffice --version")
  end
end
RUBY

template="$(cat "${work}/template.rb")"
template="${template//@@MACOS_URL@@/${macos_url}}"
template="${template//@@MACOS_SHA256@@/${macos_checksum}}"
template="${template//@@LINUX_URL@@/${linux_url}}"
template="${template//@@LINUX_SHA256@@/${linux_checksum}}"

current=""
if [[ -f "${formula}" ]]
then
  current="$(cat "${formula}")"
fi
if [[ "${template}" == "${current}" ]]
then
  echo "The formula already describes ${version}."
  exit 0
fi

printf '%s\n' "${template}" >"${output}"
echo "The formula now describes ${version}."
