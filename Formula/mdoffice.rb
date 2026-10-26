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
      url "https://github.com/markdown-office/mdoffice/releases/download/v0.1.1/mdoffice-0.1.1-macos-arm64"
      sha256 "ff8f38fb9aeefa39eb4889815c834ee587543ad12e174c57b91f720d2c36cb46"
    end

    on_intel do
      url "https://github.com/markdown-office/mdoffice/releases/download/v0.1.1/mdoffice-0.1.1-macos-x86_64"
      sha256 "6b59651ae33b51a7674d2b938d5576d79ca0ec1908b6f409b70c2d4143065df8"
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/markdown-office/mdoffice/releases/download/v0.1.1/mdoffice-0.1.1-linux-x86_64"
      sha256 "291485db259ce2e9df6cae993d58db554e97dbb8cc4b7c91f03bf374eff7790c"
    end

    on_arm do
      url "https://github.com/markdown-office/mdoffice/releases/download/v0.1.1/mdoffice-0.1.1-linux-aarch64"
      sha256 "27a0cffaae87607517635758176c532f919beb27ef9d11d3ceef74ac9a972dda"
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
