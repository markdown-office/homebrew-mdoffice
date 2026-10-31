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
      url "https://github.com/markdown-office/mdoffice/releases/download/v0.1.2/mdoffice-0.1.2-macos-arm64"
      sha256 "0ab25e74a208b4bf8d18583bad656c904b118a51ae5922808230ab3da554d670"
    end

    on_intel do
      url "https://github.com/markdown-office/mdoffice/releases/download/v0.1.2/mdoffice-0.1.2-macos-x86_64"
      sha256 "a72a7af251bc0d7be9acc60fc93fabc4b0b48fc557b768d80161db2bb7dbb5b4"
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/markdown-office/mdoffice/releases/download/v0.1.2/mdoffice-0.1.2-linux-x86_64"
      sha256 "f1995cc02066a014ac368abf1d99674a2fc23531e7a7b0d18b19454c316bfd7a"
    end

    on_arm do
      url "https://github.com/markdown-office/mdoffice/releases/download/v0.1.2/mdoffice-0.1.2-linux-aarch64"
      sha256 "a32b8da6b838a2b9edee9f7fe742044e1c45316dbe95e30af9fe3f371850d481"
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
