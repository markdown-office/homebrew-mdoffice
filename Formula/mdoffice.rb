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
      url "https://github.com/markdown-office/mdoffice/releases/download/v0.1.3/mdoffice-0.1.3-macos-arm64"
      sha256 "f21bfb307b383174b7944cba310a70a8bde3047711614cef8917e7a35ab41d20"
    end

    on_intel do
      url "https://github.com/markdown-office/mdoffice/releases/download/v0.1.3/mdoffice-0.1.3-macos-x86_64"
      sha256 "72d5a539ebc9f513206a1463daa13b82b47855528b4b418f6ab59923ddfdfef5"
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/markdown-office/mdoffice/releases/download/v0.1.3/mdoffice-0.1.3-linux-x86_64"
      sha256 "b16639ca6f9d6b958dc206dad8d86ac30b91bfabfb950f60762fff7379696969"
    end

    on_arm do
      url "https://github.com/markdown-office/mdoffice/releases/download/v0.1.3/mdoffice-0.1.3-linux-aarch64"
      sha256 "ca97fff830df7bfda795e5d091558e946622c54c6053bdcbd1d03fe8ec124713"
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
