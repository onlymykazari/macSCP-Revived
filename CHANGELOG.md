# Changelog

All notable changes to macSCP-Revived are documented here.
Pre-1.0.0 history of the original macSCP lives in [release.md](release.md) and the upstream [releases page](https://github.com/macnev2013/macSCP/releases).

## [1.1.0] — 2026-10-21

### Added
- **Diagnostics pane** (Settings → Diagnostics): shows the exact build identity (version, build number, Debug/Release), a Verbose Logging toggle, and Export Logs… — app logs are now also written to an on-disk file that survives relaunches (info-level always, debug-level when verbose), with a session marker per launch so bug reports carry the full picture.
- **Quick Look (Space)**: press Space on a selected file to preview it in the system Quick Look panel (text, images, video, audio, PDF). The file is quietly downloaded to a temporary directory first; files over 100 MB are skipped.
- **Import from ssh config**: create connections from `~/.ssh/config` — pick the file (Finder dialog, which grants sandbox access) or paste its text, review the parsed hosts (name, user@host:port, auth method), and import the selected ones. HostName/User/Port/IdentityFile map onto the connection; wildcard patterns, `Include` and `Proxy*` directives are skipped; duplicates are detected before import; key-based entries import as private-key auth, the rest ask for a password on first connect.
- **Bookmarks** (toolbar bookmark menu, ⌘D to bookmark the current folder): save frequently used remote paths per connection, jump to them from the toolbar, and rename or remove them from the same menu.
- **Initial Remote Path** on connections (connection form → Optional): the browser now opens the configured directory automatically after connecting.
- **Copy Path** (⌥⌘C, also in the context menu): copies the selected files' remote paths to the system clipboard.
- **Go menu** (Finder-style): Back (⌘[), Forward (⌘]), Enclosing Folder (⌘↑), Open Selection (⌘↓), and Go to Folder (⇧⌘G, now a real menu item instead of a hidden shortcut).
- Finder-style keyboard shortcuts in the file list: Delete removes the selection (with confirmation), Return renames, Space previews a file in the editor.

### Changed
- **Copy (⌘C) now works like Finder**: files up to 50 MB are staged to a temporary directory and placed on the system clipboard as real file URLs — pasting into Finder copies them like local files. Larger files and directories stay in-app-copy only. Cut (⌘X) keeps its in-app move semantics.
- The status bar confirms Finder copy-out with "paste in Finder to download" once the clipboard write succeeds.
- **Paste (⌘V) is context-aware**: pastes files previously copied within the connection, or — when the system clipboard holds local files — uploads them to the current remote directory.
- Right-click actions now operate on the whole selection when the clicked row is part of it, instead of collapsing it to one file.

### Fixed
- Copy (⌘C) now actually lands on the system clipboard: file promises were written but Finder never pastes them; the clipboard now carries real file URLs (staged by a quiet download), which Finder copies natively.
- Main window could hang forever on "Loading connections..." when the menu bar's focused-window tracking (⌘R/⌘N routing) re-evaluated the app scene: the connection list view model was being recreated on every re-evaluation. The view model is now held once per window.
- ⌘N / ⇧⌘N / ⌘R were dead menu items since the rebrand: ⌘R now refreshes the focused browser (and reconnects a lost session), ⌘N creates a new folder in the browser or a new connection in the main window, ⇧⌘N creates a new file.
- ⌘I (Get Info) now works from the menu bar for the current selection.
- Bookmarks, connections, and the initial remote path are included in encrypted backups; old backups without bookmarks still restore.

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
