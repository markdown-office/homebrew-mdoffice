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
  #
  # No release of `mdoffice` exists yet: there is nothing to download and no
  # checksum to verify, and the URLs below point at a version that was never
  # published. `tools/update-formula.sh` replaces this file with the released
  # formula, checksum included, as soon as there is a release to point at.

  on_macos do
    on_arm do
      url "https://github.com/markdown-office/mdoffice/releases/download/v0.0.0/mdoffice-0.0.0-macos-arm64"
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/markdown-office/mdoffice/releases/download/v0.0.0/mdoffice-0.0.0-linux-x86_64"
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
