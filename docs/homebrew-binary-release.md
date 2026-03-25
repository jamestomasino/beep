# Homebrew Binary Distribution (From GitHub Tags)

This project can publish precompiled macOS binaries on tag push and use those release assets from a Homebrew tap formula.

## Release flow

1. Push a semver tag:

```bash
git tag v0.1.0
git push origin v0.1.0
```

2. GitHub Actions workflow `release-macos` builds:
- `darwin-arm64` on `macos-15`
- `darwin-x86_64` on `macos-15-intel`

3. Workflow publishes release assets:
- `beep-v0.1.0-darwin-arm64.tar.gz`
- `beep-v0.1.0-darwin-arm64.sha256`
- `beep-v0.1.0-darwin-x86_64.tar.gz`
- `beep-v0.1.0-darwin-x86_64.sha256`
- `SHA256SUMS`

Each tarball contains:
- `bin/beep`
- `README.md`

## Homebrew tap formula

Create a tap (once):

```bash
brew tap-new jamestomasino/beep
```

Add `Formula/beep.rb` in that tap:

```ruby
class Beep < Formula
  desc "Activity sonifier CLI"
  homepage "https://github.com/jamestomasino/beep"
  version "0.1.0"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/jamestomasino/beep/releases/download/v#{version}/beep-v#{version}-darwin-arm64.tar.gz"
      sha256 "REPLACE_WITH_ARM64_SHA256"
    else
      url "https://github.com/jamestomasino/beep/releases/download/v#{version}/beep-v#{version}-darwin-x86_64.tar.gz"
      sha256 "REPLACE_WITH_X86_64_SHA256"
    end
  end

  def install
    bin.install "bin/beep"
    doc.install "README.md"
  end

  test do
    assert_match "beep", shell_output("#{bin}/beep --version")
  end
end
```

Install from tap:

```bash
brew install jamestomasino/beep/beep
```

## Notes

- Keep tags immutable. If you must rebuild, cut a new tag.
- Update `version` and both `sha256` values each release.
- This avoids requiring end users to install Ada toolchains locally.
