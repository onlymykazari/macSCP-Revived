# Changelog

All notable changes to macSCP-Revived are documented here.
Pre-1.0.0 history of the original macSCP lives in [release.md](release.md) and the upstream [releases page](https://github.com/macnev2013/macSCP/releases).

## [1.0.0] — 2026-10-13

First release of macSCP-Revived, the community-maintained continuation of [macSCP](https://github.com/macnev2013/macSCP).

### Added
- **Go to Folder** (⇧⌘G or the folder icon in the path bar): jump to any remote path with a Finder-style input; supports relative paths, `..`, `~`, and duplicate-separator cleanup.

### Changed
- Rebranded as **macSCP-Revived** with a new bundle identifier (`com.onlymykazari.macscp-revived`), display name, and DMG naming.
- Releases, Sparkle update feed (new EdDSA key pair), and Homebrew distribution now run from `onlymykazari/macSCP-Revived`.
- Version sources consolidated: the latest `v*` git tag is the single source of truth for app and DMG versions.
- Release DMGs require macOS 15.0+ (matches the deployment target; the old appcast claimed 13.0).

### Removed
- TelemetryDeck analytics — the app is now fully offline and collects nothing.
