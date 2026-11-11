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
      url "https://github.com/markdown-office/mdoffice/releases/download/v0.2.1/mdoffice-0.2.1-macos-arm64"
      sha256 "2baf32899c48e84fb1ae3cb1e86a6cf83ac7afcc2b4c8eb7a083d669da779f96"
    end

    on_intel do
      url "https://github.com/markdown-office/mdoffice/releases/download/v0.2.1/mdoffice-0.2.1-macos-x86_64"
      sha256 "de5734ebeaf8ab2b8d4677038aa50cb667b894205581754f5809bcb0f9c6e1a8"
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/markdown-office/mdoffice/releases/download/v0.2.1/mdoffice-0.2.1-linux-x86_64"
      sha256 "8aad2c8c0a53f5b7967c8d6dedb3229ac3ccc3cbdee760ad4947aaf257564315"
    end

    on_arm do
      url "https://github.com/markdown-office/mdoffice/releases/download/v0.2.1/mdoffice-0.2.1-linux-aarch64"
      sha256 "d3974b1b34b12758641e95ba555109090908e68bd500c3433e34ff1800f44374"
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
