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
      url "https://github.com/markdown-office/mdoffice/releases/download/v0.2.0/mdoffice-0.2.0-macos-arm64"
      sha256 "4a5e580146f366caeed34d48d3b7e8909413fafd39083e89cdaae7a638c86c5f"
    end

    on_intel do
      url "https://github.com/markdown-office/mdoffice/releases/download/v0.2.0/mdoffice-0.2.0-macos-x86_64"
      sha256 "308adfcc8b49d1e46da4caee8e3a77a0ad77751290269c10a7290e242ef0b3eb"
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/markdown-office/mdoffice/releases/download/v0.2.0/mdoffice-0.2.0-linux-x86_64"
      sha256 "b1b0dec0cd326a6ee03b7aebc6e1932252cc0d40bc03af63a548bb101f306121"
    end

    on_arm do
      url "https://github.com/markdown-office/mdoffice/releases/download/v0.2.0/mdoffice-0.2.0-linux-aarch64"
      sha256 "2a7efef932d3d861a7877242684d9a73d6bf5efd76dc26728af7074f6b8b18d5"
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
