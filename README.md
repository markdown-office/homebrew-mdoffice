# homebrew-mdoffice

The Homebrew tap for [`mdoffice`](https://github.com/markdown-office/mdoffice), the
command line for the [markdown-office](https://github.com/markdown-office) suite:
Markdown to Word and to PowerPoint, in one program.

```bash
brew tap markdown-office/mdoffice
brew install mdoffice
```

## There is no release yet

`mdoffice` has not been released. The formula in `Formula/mdoffice.rb` is a
placeholder: it points at a version that was never published and carries no
checksum, because there is no file to checksum. `brew install mdoffice` fails
with a 404 until the first release is published and the pull request that
carries its formula is merged.

The tap updates itself. `.github/workflows/update-formula.yml` asks GitHub for
the latest `markdown-office/mdoffice` release, downloads the assets, computes
their checksums, writes the formula and opens a pull request with it. It opens
one only when the formula says something different from the release, and it
merges nothing: a person reads the pull request and merges it.

Run it by hand from the Actions tab, or wait for the daily run at 04:23 UTC.
The script needs `curl` and `jq`; the runner has both.

## Windows

Windows is not in this tap. It is in
[`microsoft/winget-pkgs`](https://github.com/microsoft/winget-pkgs), and this
repository writes the manifest for it: `.github/workflows/update-winget.yml`
asks for the same release, writes the three files a `winget` manifest is made
of, and opens a pull request against the fork at
[`markdown-office/winget-pkgs`](https://github.com/markdown-office/winget-pkgs).
It merges nothing, for the same reason the formula's pull request is not merged.

The fork is the organisation's, so that the manifest and the pull request that
carries it are under the same name as the package. The pull request against
`microsoft/winget-pkgs` itself is opened from that fork, by a person.

That workflow needs a token of its own — `WINGET_TOKEN`, a personal access
token with write access to the fork — because this repository's own token is
good for this repository and not for the fork. The workflow says so when it is
not set, rather than failing later as an authentication error.

The manifest is written through the API rather than by pushing to a clone:
`winget-pkgs` holds a manifest for every package there is, and cloning it to
add three files is a large thing to do for three files.


## The release assets

The formula is written for the assets the release workflow publishes, and the
names are fixed here because the formula is generated from them:

| Asset | |
| --- | --- |
| `mdoffice-<version>-macos-arm64` | macOS, Apple silicon |
| `mdoffice-<version>-macos-x86_64` | macOS, Intel |
| `mdoffice-<version>-linux-x86_64` | Linux, x86-64 |
| `mdoffice-<version>-linux-aarch64` | Linux, ARM |
| `mdoffice-<version>-windows-x64.exe` | Windows, x64 — the one the `winget` manifest installs |
| `SHA256SUMS` | the checksums of the release's assets |

The URLs are of the form

```
https://github.com/markdown-office/mdoffice/releases/download/v<version>/<asset>
```

`tools/update-formula.sh` computes the checksums from the downloads and compares
them with `SHA256SUMS` before it writes the formula, so a release whose sums
file disagrees with its assets is refused rather than installed. A release whose
assets are named otherwise is refused too, and the script says which asset it
looked for.

## A formula, not a cask

`mdoffice` is a command, and it is a formula. Homebrew re-adds the quarantine
flag to what a **cask** downloads, because a cask's payload is an application
bundle that has to be opened; a formula installs into `$(brew --prefix)/bin` and
has no bundle. As a cask, `mdoffice` would give every user a Gatekeeper dialog
over a program that has no application.

The macOS binary is ad-hoc signed and not notarised, so it needs no quarantine
flag to run:

- **Installed from this tap.** Homebrew does not quarantine what it downloads,
  and the binary is signed, so it runs.
- **Downloaded from the release page with a browser.** The browser sets the
  quarantine flag, and macOS asks. Remove it before running the program:

  ```bash
  xattr -d com.apple.quarantine mdoffice
  ```

- **Downloaded with `curl`.** `curl` does not set the flag, and the program
  runs.

## The files

| | |
| --- | --- |
| `Formula/mdoffice.rb` | the formula, written by the update script |
| `tools/update-formula.sh` | writes the formula from the latest release |
| `tools/test-update-formula.sh` | checks the update script against a release that is not a release |
| `tools/update-winget-manifest.sh` | writes the `winget` manifest from the latest release |
| `tools/test-update-winget-manifest.sh` | checks that script against a release that is not a release |
| `tools/fake-curl.sh` | the GitHub the manifest test is run against |
| `.github/workflows/update-formula.yml` | runs the script and opens the pull request |
| `.github/workflows/update-winget.yml` | writes the manifest and opens the pull request against the fork |
| `.github/workflows/ci.yml` | parses the formula and runs the tests on every push |
