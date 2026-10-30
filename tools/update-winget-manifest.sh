#!/usr/bin/env bash
#
# Writes the `winget` manifest for the latest `mdoffice` release.
#
# A manifest carries the checksum of the file it installs, and a checksum can only
# come from a file that exists. While `markdown-office/mdoffice` has no release
# there is no file, so this writes nothing and says so.
#
# The manifest is three files, which is what `winget` expects for a package with a
# display name: the version, the installer, and the locale that names the package.
# The installer is `portable`, because the release publishes a bare executable and
# there is nothing to unpack.
#
# The asset name is the one the release workflow publishes, and the one this
# repository's README documents:
#
#   mdoffice-<version>-windows-x64.exe
#
# Environment:
#   MDOFFICE_API             the GitHub API to ask          (default https://api.github.com)
#   MDOFFICE_REPO            the repository to ask about    (default markdown-office/mdoffice)
#   MDOFFICE_WINGET_OUTPUT   where to write the manifest   (default manifests)
#   MDOFFICE_WINGET_BASE     the repository proposed against (default microsoft/winget-pkgs)
#   MDOFFICE_WINGET_FORK     the fork to propose against   (default markdown-office/winget-pkgs)
#   MDOFFICE_WINGET_SUBMIT   open the pull request         (default false)
#   GITHUB_TOKEN             sent to the API when it is set

set -euo pipefail

api="${MDOFFICE_API:-https://api.github.com}"
repo="${MDOFFICE_REPO:-markdown-office/mdoffice}"
output="${MDOFFICE_WINGET_OUTPUT:-manifests}"
base="${MDOFFICE_WINGET_BASE:-microsoft/winget-pkgs}"
fork="${MDOFFICE_WINGET_FORK:-markdown-office/winget-pkgs}"
submit="${MDOFFICE_WINGET_SUBMIT:-false}"

identifier="markdown-office.mdoffice"

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

# The status code is what tells a repository without a release from a broken API,
# and this script reports either of them itself.
status="$(curl "${curl_options[@]}" --output "${work}/release.json" --write-out '%{http_code}' \
  "${api}/repos/${repo}/releases/latest" 2>/dev/null || true)"

case "${status}" in
  200) ;;
  404)
    echo "No release of ${repo} yet. The manifest is left as it is."
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

name="mdoffice-${version}-windows-x64.exe"
url="$(jq -r --arg name "${name}" '[.assets[] | select(.name == $name) | .browser_download_url][0] // ""' \
  "${work}/release.json")"

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
released="$(jq -r '.published_at // "" | split("T")[0]' "${work}/release.json")"

directory="${output}/m/markdown-office/mdoffice/${version}"
mkdir -p "${directory}"

cat >"${directory}/${identifier}.yaml" <<YAML
# yaml-language-server: \$schema=https://aka.ms/winget-manifest.version.1.10.0.schema.json

PackageIdentifier: ${identifier}
PackageVersion: ${version}
DefaultLocale: en-US
ManifestType: version
ManifestVersion: 1.10.0
YAML

cat >"${directory}/${identifier}.installer.yaml" <<YAML
# yaml-language-server: \$schema=https://aka.ms/winget-manifest.installer.1.10.0.schema.json

PackageIdentifier: ${identifier}
PackageVersion: ${version}
InstallerType: portable
Commands:
- mdoffice
ReleaseDate: ${released}
Installers:
- Architecture: x64
  InstallerUrl: ${url}
  InstallerSha256: ${checksum}
ManifestType: installer
ManifestVersion: 1.10.0
YAML

cat >"${directory}/${identifier}.locale.en-US.yaml" <<YAML
# yaml-language-server: \$schema=https://aka.ms/winget-manifest.defaultLocale.1.10.0.schema.json

PackageIdentifier: ${identifier}
PackageVersion: ${version}
PackageLocale: en-US
Publisher: markdown-office
PublisherUrl: https://github.com/markdown-office
PublisherSupportUrl: https://github.com/markdown-office/mdoffice/issues
Author: markdown-office
PackageName: mdoffice
PackageUrl: https://github.com/markdown-office/mdoffice
License: MIT
LicenseUrl: https://github.com/markdown-office/mdoffice/blob/main/LICENSE
ShortDescription: Markdown to Word and to PowerPoint, as a command-line tool
Tags:
- markdown
- docx
- pptx
- cli
ReleaseNotesUrl: https://github.com/markdown-office/mdoffice/releases/tag/${tag}
ManifestType: defaultLocale
ManifestVersion: 1.10.0
YAML

echo "Wrote the manifest for ${version} into ${directory}."

if [[ "${submit}" != "true" ]]
then
  exit 0
fi

# The pull request is opened through the API rather than by pushing to a clone:
# the repository holds a manifest for every package there is, and cloning it to
# add three files is a large thing to do for three files.
#
# The branch is named for the package and the version, and nothing else. The
# branch ends up as the head of a pull request against another repository — the
# fork this is written in is the staging area, and the submission to
# `microsoft/winget-pkgs` is a pull request from it — and a head is named by a
# path in the API, where a component that is a version with dots in it is a
# component that cannot be read. `manifests/markdown-office.mdoffice/0.1.1` is
# refused; `mdoffice-0.1.1` is not.
branch="mdoffice-${version}"

# The branch is cut from the base's master and not from the fork's.
#
# The fork is a staging area, and its master holds the manifests of the versions
# that have been proposed and not yet merged: a manifest merged into it is a
# version the base does not have. A branch cut from there carries those files
# with it, and the submission then holds two versions where the validator wants
# one. It refuses such a pull request and says so:
#
#   The pull request contains more than one manifest. Either singleton or multi
#   file manifest under one version directory.
#
# The base's master is the one the submission is measured against, so it is the
# one the branch has to start from.
base_sha="$(curl "${curl_options[@]}" "${api}/repos/${base}/git/ref/heads/master" | jq -r '.object.sha')"

if [[ -z "${base_sha}" || "${base_sha}" == "null" ]]
then
  echo "Could not read the head of ${base}." >&2
  exit 1
fi

# The fork's master is moved to the base's master, so that the pull request
# opened against it shows the manifest and nothing else. A fork's master that
# has fallen behind shows every commit the base has taken since, and one that
# has been merged into shows the version before as well.
fork_sha="$(curl "${curl_options[@]}" "${api}/repos/${fork}/git/ref/heads/master" | jq -r '.object.sha')"

if [[ "${fork_sha}" != "${base_sha}" ]]
then
  curl "${curl_options[@]}" --request PATCH \
    --data "{\"sha\": \"${base_sha}\", \"force\": true}" \
    "${api}/repos/${fork}/git/refs/heads/master" >/dev/null

  echo "The fork's master is now the base's master."
fi

# The branch is made only when it is not there. The workflow runs every day and
# the release does not change every day, so the second run is the ordinary case
# rather than an accident, and GitHub refuses a reference that already exists.
ref="$(curl "${curl_options[@]}" "${api}/repos/${fork}/git/ref/heads/${branch}" | jq -r '.object.sha // ""' || true)"

if [[ -z "${ref}" || "${ref}" == "null" ]]
then
  curl "${curl_options[@]}" --request POST \
    --data "{\"ref\": \"refs/heads/${branch}\", \"sha\": \"${base_sha}\"}" \
    "${api}/repos/${fork}/git/refs" >/dev/null
fi

for file in "${directory}"/*.yaml
do
  name_in_repo="$(basename "${file}")"
  content="$(base64 <"${file}" | tr -d '\n')"

  # The path in the repository, and not the path in the working directory. A
  # manifest lives under `manifests/` in `winget-pkgs` — `manifests/m/<publisher>/<package>/<version>/`
  # — and the working directory is the same path, which is why the two look alike
  # until one of them is wrong.
  path_in_repo="manifests/m/markdown-office/mdoffice/${version}/${name_in_repo}"

  # The API refuses to write a file that is already there without the hash of what
  # is there, and refuses to write a new one with a hash at all. The version a
  # manifest names is written once, so a file that is already there is a manifest
  # for the same version being corrected rather than a new one.
  existing="$(curl "${curl_options[@]}" "${api}/repos/${fork}/contents/${path_in_repo}?ref=${branch}" \
    2>/dev/null | jq -r '.sha // ""' || true)"

  if [[ -n "${existing}" && "${existing}" != "null" ]]
  then
    payload="{\"message\": \"Correct the ${identifier} ${version} manifest\", \"content\": \"${content}\", \"branch\": \"${branch}\", \"sha\": \"${existing}\"}"
  else
    payload="{\"message\": \"Add the ${identifier} ${version} manifest\", \"content\": \"${content}\", \"branch\": \"${branch}\"}"
  fi

  curl "${curl_options[@]}" --request PUT --data "${payload}" \
    "${api}/repos/${fork}/contents/${path_in_repo}" >/dev/null
done

# The pull request is opened only when there is not one for the branch. GitHub
# refuses a second pull request for the same branch, and the run that follows
# the first would fail on it rather than on anything else.
owner="${fork%%/*}"
open="$(curl "${curl_options[@]}" "${api}/repos/${fork}/pulls?head=${owner}:${branch}&state=open" \
  | jq -r '.[0].html_url // ""' || true)"

if [[ -n "${open}" && "${open}" != "null" ]]
then
  echo "The pull request for ${version} is already open: ${open}"

  exit 0
fi

pull="$(curl "${curl_options[@]}" --request POST \
  --data "{\"title\": \"Add ${identifier} ${version}\", \"head\": \"${branch}\", \"base\": \"master\", \"body\": \"The manifest for ${identifier} ${version}, generated from the release.\"}" \
  "${api}/repos/${fork}/pulls" | jq -r '.html_url // ""')"

echo "The pull request is ${pull}"
