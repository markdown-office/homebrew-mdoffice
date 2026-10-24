#!/usr/bin/env bash
#
# A stand-in for `curl`, which answers the GitHub API from a directory.
#
# The manifest script asks the API three things: what the release is, what the
# fork has already been asked for, and what to write. This answers them from
# files — `release.json` is the release — and remembers what it has been asked
# to do in the directory `FIXTURE_STATE` names.
#
# A second run of the script therefore sees the branch and the pull request the
# first one made, which is what GitHub does and what the script has to cope
# with. The endpoints that can only be used once answer 422 the second time.
#
# It is used by putting it on the path as `curl`, and it serves `file://` URLs
# as the files they are, which is how the release's assets are given.

set -euo pipefail

state="${FIXTURE_STATE:?the directory this keeps its state in}"
mkdir -p "${state}"

for remembered in refs pulls files
do
  touch "${state}/${remembered}"
done

output=""
write_out=""
method="GET"
data=""
url=""
fail="no"

while [[ $# -gt 0 ]]
do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    --write-out) write_out="$2"; shift 2 ;;
    --request) method="$2"; shift 2 ;;
    --data) data="$2"; shift 2 ;;
    --header|--max-redirs|--retry) shift 2 ;;
    --fail) fail="yes"; shift ;;
    --silent|--show-error|--location) shift ;;
    *) url="$1"; shift ;;
  esac
done

if [[ "${url}" == file://* ]]
then
  if [[ -n "${output}" ]]
  then
    cp "${url#file://}" "${output}"
  else
    cat "${url#file://}"
  fi

  exit 0
fi

path="${url#*://*/}"
path="${path%%\?*}"

body=""
code="200"

case "${method}" in
  GET)
    case "${path}" in
      */releases/latest)
        if [[ -f "${state}/release.json" ]]
        then
          body="$(cat "${state}/release.json")"
        else
          code="404"
          body='{"message":"Not Found"}'
        fi
        ;;
      */git/ref/heads/master)
        body='{"object":{"sha":"the-head-of-master"}}'
        ;;
      */git/ref/heads/*)
        branch="${path##*/git/ref/heads/}"

        if grep -qxF "${branch}" "${state}/refs"
        then
          body='{"object":{"sha":"the-branch"}}'
        else
          code="404"
          body='{"message":"Not Found"}'
        fi
        ;;
      */pulls)
        opens=""

        while IFS= read -r branch
        do
          [[ -n "${branch}" ]] || continue
          [[ -n "${opens}" ]] && opens="${opens},"
          opens="${opens}{\"html_url\":\"/pull/1\",\"head\":{\"ref\":\"${branch}\"}}"
        done <"${state}/pulls"

        body="[${opens}]"
        ;;
      */contents/*)
        name="${path##*/contents/}"

        if grep -qxF "${name}" "${state}/files"
        then
          body='{"sha":"the-file"}'
        else
          code="404"
          body='{"message":"Not Found"}'
        fi
        ;;
      *)
        code="404"
        body='{"message":"Not Found"}'
        ;;
    esac
    ;;
  POST)
    case "${path}" in
      */git/refs)
        ref="$(printf '%s' "${data}" | jq -r '.ref // ""')"
        branch="${ref#refs/heads/}"

        if grep -qxF "${branch}" "${state}/refs"
        then
          code="422"
          body='{"message":"Reference already exists"}'
        else
          printf '%s\n' "${branch}" >>"${state}/refs"
          body="{\"ref\":\"${ref}\"}"
        fi
        ;;
      */pulls)
        head="$(printf '%s' "${data}" | jq -r '.head // ""')"

        if grep -qxF "${head}" "${state}/pulls"
        then
          code="422"
          body='{"message":"A pull request already exists"}'
        else
          printf '%s\n' "${head}" >>"${state}/pulls"
          body="{\"html_url\":\"/pull/1\",\"head\":{\"ref\":\"${head}\"}}"
        fi
        ;;
      *)
        code="404"
        body='{"message":"Not Found"}'
        ;;
    esac
    ;;
  PUT)
    case "${path}" in
      */contents/*)
        printf '%s\n' "${path##*/contents/}" >>"${state}/files"
        body='{"content":{"sha":"the-file"}}'
        ;;
      *)
        code="404"
        body='{"message":"Not Found"}'
        ;;
    esac
    ;;
esac

# An error is what `curl --fail` is for: the body is not written and the exit
# status is not zero. The code is still written out, because that is what
# `curl` does and what the script reads.
if [[ "${code}" != "200" && "${fail}" = "yes" ]]
then
  if [[ -n "${write_out}" ]]
  then
    printf '%s' "${write_out}" | sed "s/%{http_code}/${code}/"
  fi

  exit 22
fi

if [[ -n "${output}" ]]
then
  printf '%s' "${body}" >"${output}"
else
  printf '%s' "${body}"
fi

if [[ -n "${write_out}" ]]
then
  printf '%s' "${write_out}" | sed "s/%{http_code}/${code}/"
fi
