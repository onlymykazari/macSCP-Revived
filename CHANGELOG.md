# Changelog

All notable changes to macSCP-Revived are documented here.
Pre-1.0.0 history of the original macSCP lives in [release.md](release.md) and the upstream [releases page](https://github.com/macnev2013/macSCP/releases).

## [1.0.1] — 2026-10-13

### Added
- **Encrypted Backup & Restore** (Settings → Backup & Restore):
  - Export all connections, folders, saved passwords/S3 keys, and app-lock preferences into a single password-protected file (PBKDF2-HMAC-SHA256 + AES-256-GCM, no new dependencies)
  - Import with a decrypt-and-preview step, then **Merge** (newer versions win, skipped items keep local credentials) or **Replace All**
  - Folders are deduplicated by name on merge; the Touch ID master switch is never changed by a restore
- Settings window now has Security and Backup & Restore panes

### Fixed
- Unified the connection UTType with the rebranded bundle identity (`com.onlymykazari.macscp-revived.connection`)

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
