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
      url "https://github.com/markdown-office/mdoffice/releases/download/v0.2.2/mdoffice-0.2.2-macos-arm64"
      sha256 "a810498d65f324dde86bbd32d6a44506223c82a52c3c48e7d8f5b9e94e7de7b2"
    end

    on_intel do
      url "https://github.com/markdown-office/mdoffice/releases/download/v0.2.2/mdoffice-0.2.2-macos-x86_64"
      sha256 "ce536a2b05cc52a854d22632f88a0375698c48f622ca3260f60bdc9094da1cb3"
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/markdown-office/mdoffice/releases/download/v0.2.2/mdoffice-0.2.2-linux-x86_64"
      sha256 "4d15580f36767126b4797193095e133811577ba56d2bb34050ca477d8d31ba85"
    end

    on_arm do
      url "https://github.com/markdown-office/mdoffice/releases/download/v0.2.2/mdoffice-0.2.2-linux-aarch64"
      sha256 "f2287f70d0893858e334c610e676f3c996e5ef78c6ddf6fa05cbf587b4561a87"
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
