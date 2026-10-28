<br/>

<p align="center">
  <img src="screens/logo.png" alt="macSCP-Revived Logo" width="200"/>
</p>

<h1 align="center">macSCP-Revived</h1>

<p align="center">
  <strong>Native macOS SFTP · S3 · SSH terminal — community-maintained continuation of <a href="https://github.com/macnev2013/macSCP">macSCP</a></strong>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#screenshots">Screenshots</a> •
  <a href="#installation">Installation</a> •
  <a href="#building">Building</a> •
  <a href="#contributing">Contributing</a> •
  <a href="#license">License</a>
</p>

<p align="center">
  <a href="https://github.com/onlymykazari/macSCP-Revived/releases"><img src="https://img.shields.io/github/v/release/onlymykazari/macSCP-Revived" alt="Release"/></a>
  <a href="https://github.com/onlymykazari/macSCP-Revived/releases"><img src="https://img.shields.io/github/downloads/onlymykazari/macSCP-Revived/total" alt="Downloads"/></a>
  <a href="https://github.com/onlymykazari/homebrew-tap"><img src="https://img.shields.io/badge/homebrew-tap-orange?logo=homebrew" alt="Homebrew Tap"/></a>
  <img src="https://img.shields.io/badge/macOS-15.0%2B-blue?logo=apple" alt="macOS 15.0+"/>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-CC0--1.0-green" alt="License CC0"/></a>
  <a href="https://github.com/onlymykazari/macSCP-Revived/stargazers"><img src="https://img.shields.io/github/stars/onlymykazari/macSCP-Revived?style=social" alt="Stars"/></a>
</p>

---

<p align="center">
  <img src="screens/screen-1.png" alt="macSCP-Revived Connection Manager" width="800"/>
</p>
<p align="center"><em>Manage SFTP servers, S3 buckets, and SSH terminals from one native macOS app.</em></p>

---

## Overview

The original [macSCP](https://github.com/macnev2013/macSCP) is no longer maintained — its author moved on to a cross-platform rewrite. **macSCP-Revived** picks up the native-SwiftUI macOS lineage: same app, actively maintained, with its own releases, versioning, and Homebrew distribution.

macSCP-Revived is a modern, native macOS application built with SwiftUI that provides seamless file management for SFTP servers, Amazon S3 storage, and integrated SSH terminal access. With its intuitive interface and powerful features, it makes managing remote servers and cloud storage as easy as working with local files.

## How macSCP-Revived Compares

| Feature | macSCP-Revived | Cyberduck | Transmit | FileZilla |
|---------|--------|-----------|----------|-----------|
| Native SwiftUI | Yes | No (Java) | Yes (AppKit) | No (wxWidgets) |
| SFTP | Yes | Yes | Yes | Yes |
| S3 / S3-compatible | Yes | Yes | Yes | Pro only |
| Integrated SSH terminal | Yes | No | No | No |
| Built-in file editor | Yes | Yes | Yes | No |
| macOS Keychain | Yes | Yes | Yes | No |
| Free & open source | Yes | Yes (GPL) | No ($45) | Yes (GPL) |
| Dark mode | Yes | Yes | Yes | No |

## Features

### 🔐 **Secure Connection Management**
- **Multiple Authentication Methods**: Support for both password and SSH key-based authentication
- **Keychain Integration**: Securely store passwords in macOS Keychain
- **SSH Key Support**: Use your existing SSH private keys for authentication
- **Connection Profiles**: Save and organize multiple server connections with custom icons and descriptions
- **Encrypted Backup & Restore**: Export everything (connections, folders, saved passwords, app settings) to a single password-protected file (AES-256-GCM), and restore it with merge or replace strategies

### ☁️ **Amazon S3 Support**
- **S3 & S3-Compatible Storage**: Connect to Amazon S3, MinIO, DigitalOcean Spaces, and other S3-compatible services
- **Bucket Browser**: Browse and manage S3 buckets with the same familiar interface
- **Access Key Authentication**: Secure authentication using AWS access keys
- **Region Support**: Connect to any AWS region or custom endpoints
- **Full File Operations**: Upload, download, delete, and manage objects in S3 buckets

### 📁 **Advanced File Management**
- **Full File Browser**: Navigate remote file systems with an intuitive Finder-like interface
- **Go to Folder**: Jump to any path with ⇧⌘G or the path-bar icon — supports relative paths, `..`, and `~`
- **File Operations**:
  - Create, delete, rename files and folders
  - Copy, cut, and paste operations with clipboard support
  - Upload and download files with progress tracking
  - Drag-and-drop file uploads
- **File Permissions**: View and understand Unix file permissions (rwxrwxrwx)
- **Quick Actions**: Context menu with common operations (Open, Download, Copy, Cut, Delete, Rename, Get Info)

### ✏️ **Built-in File Editor**
- **Syntax Highlighting**: Edit remote files directly with built-in text editor
- **Real-time Editing**: Open and modify files without downloading them first
- **Search Functionality**: Find text within files with integrated search
- **Multiple File Support**: Open multiple files in separate editor windows
- **Auto-save**: Changes are saved directly to the remote server

### 📊 **Organization & Workflow**
- **Folder Management**: Organize connections into custom folders (Production, Development, etc.)
- **Tagging System**: Tag connections for easy filtering and organization
- **Custom Icons**: Assign SF Symbols to connections for visual identification
- **Quick Search**: Filter connections by name or tags
- **Connection Counter**: See how many connections you have at a glance

### 🎨 **Native macOS Experience**
- **SwiftUI Interface**: Built entirely with SwiftUI for a modern, native feel
- **Dark Mode Support**: Fully supports macOS appearance modes
- **Multiple Windows**: Open multiple SSH sessions and file explorers simultaneously
- **Window Management**: Separate windows for file browser, editor, and file info
- **macOS Integration**: Follows macOS design patterns and conventions

### 📂 **Remote File Browser**
- **Dual Navigation**: Sidebar with favorites and locations, plus main file list view
- **File Metadata**: View file sizes, permissions, and modification dates
- **Breadcrumb Navigation**: Easy path navigation with breadcrumb bar
- **Folder Shortcuts**: Quick access to common system folders (home, root, etc.)
- **File Info Panel**: Detailed information about files and folders

### 🔄 **Transfer Operations**
- **Upload Progress**: Real-time progress tracking for file uploads
- **Download Manager**: Monitor download progress with visual feedback
- **Batch Operations**: Upload or download multiple files at once
- **Error Handling**: Clear error messages and recovery options

### 💻 **Terminal Emulator**
- **Integrated SSH Terminal**: Open terminal sessions directly from SFTP connections
- **Full Terminal Support**: Complete terminal emulation with xterm-256color support
- **Multiple Sessions**: Open multiple terminal windows for different servers
- **Native Experience**: Terminal windows integrated into the macOS app environment
- **Quick Access**: Launch terminal from connection list or file browser toolbar

### 🛠️ **Developer-Friendly**
- **URL Scheme Launch**: other apps on the same Mac can open a saved connection in the file browser or terminal via `macscp://` links — see the [URL Scheme Reference](docs/url-scheme.md)
- **SwiftData Persistence**: Modern data persistence using SwiftData
- **Citadel SFTP**: Built on the robust Citadel SSH/SFTP library
- **NIO Foundation**: Leverages SwiftNIO for high-performance networking
- **Combine Framework**: Reactive programming for smooth UI updates

## Screenshots

| Connection Manager | New Connection |
|:--:|:--:|
| ![Connection Manager](screens/screen-1.png) | ![New Connection](screens/screen-2.png) |
| *Organize servers with folders, tags, and icons* | *Password or SSH key authentication* |

| Remote File Browser | Built-in Editor |
|:--:|:--:|
| ![File Browser](screens/screen-3.png) | ![File Editor](screens/screen-4.png) |
| *Finder-like interface with context menus* | *Edit remote files with syntax highlighting* |

## Installation

### Homebrew (recommended)

```bash
brew tap onlymykazari/tap
brew install --cask macscp-revived
```

### Manual Download
1. Download the latest release from the [Releases](https://github.com/onlymykazari/macSCP-Revived/releases) page
2. Open the `.dmg` file
3. Drag macSCP-Revived to your Applications folder
4. Launch macSCP-Revived from Applications

### ⚠️ Note on first launch (unsigned builds)

Releases are currently **ad-hoc signed** (no Apple Developer ID), so Gatekeeper will block the first launch. To open the app:

- **Easiest**: right-click (or Control-click) the app → **Open** → **Open** in the dialog, or
- Remove the quarantine attribute manually:
  ```bash
  xattr -dr com.apple.quarantine /Applications/macSCP-Revived.app
  ```
- If you installed via Homebrew, `brew` strips the quarantine attribute automatically in most cases.

### Requirements
- macOS 15.0 (Sequoia) or later
- For SFTP: SSH access to remote servers
- For S3: AWS access key and secret key (or S3-compatible credentials)

## Building

### Prerequisites

- Xcode 16.0 or later
- macOS 15.0 SDK or later
- Swift 5.9 or later

### Dependencies

macSCP-Revived uses Swift Package Manager for dependency management. Required packages:
- [Citadel](https://github.com/Orlandos-nl/Citadel) - SSH/SFTP implementation
- [Soto](https://github.com/soto-project/soto) - AWS SDK for Swift (S3 support)
- [SwiftNIO](https://github.com/apple/swift-nio) - High-performance networking
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) - Terminal emulator support

### Build Instructions

1. Clone the repository:
   ```bash
   git clone https://github.com/onlymykazari/macSCP-Revived.git
   cd macSCP-Revived
   ```

2. Open the project in Xcode:
   ```bash
   open macSCP.xcodeproj
   ```

3. Wait for Swift Package Manager to resolve dependencies

4. Build and run — the project is configured for ad-hoc signing, so **no development team is required**:
   - Press `⌘R` or click the Run button
   - Or use the build script: `./create-dmg.sh`

### Creating a DMG

A build script is included to create a distributable DMG:

```bash
./create-dmg.sh
```

This will:
- Build the app in Release mode (version is derived from the latest `v*` git tag)
- Create a DMG installer named `macSCP-Revived-<version>.dmg`
- Print a Sparkle update signature for the appcast (requires `SPARKLE_PRIVATE_KEY` context for CI)

## Architecture

macSCP-Revived is built with modern Swift and SwiftUI patterns:

- **SwiftUI**: Entire UI built with declarative SwiftUI
- **SwiftData**: Model persistence and data management
- **Combine**: Reactive state management
- **Citadel**: SSH/SFTP protocol implementation
- **Soto**: AWS S3 protocol implementation
- **SwiftNIO**: Non-blocking I/O for network operations
- **MVVM Pattern**: Clean separation of concerns
- **Async/Await**: Modern concurrency for smooth performance

### Key Components

- **Models**: `Connection`, `ConnectionFolder`, `RemoteFile`, `S3Credentials`
- **Sessions**:
  - `SFTPSession` - SFTP protocol operations
  - `S3Session` - AWS S3 protocol operations
  - `TerminalSession` - SSH terminal session management
- **Repositories**:
  - `FileRepository` - SFTP file operations
  - `S3FileRepository` - S3 file operations
  - `ConnectionRepository` - Connection management
- **Services**:
  - `KeychainService` - Secure credential storage
  - `ClipboardService` - Clipboard operations
  - `WindowManager` - Window management
- **Views**: Modular SwiftUI views for each feature

## Contributing

Contributions are welcome! Here's how you can help:

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/amazing-feature`
3. **Commit your changes**: `git commit -m 'Add amazing feature'`
4. **Push to the branch**: `git push origin feature/amazing-feature`
5. **Open a Pull Request**

### Development Guidelines

- Follow Swift style guidelines
- Write clear commit messages
- Add comments for complex logic
- Test your changes thoroughly
- Update documentation as needed

## Security

macSCP-Revived takes security seriously:

- Passwords and AWS credentials are stored securely in macOS Keychain
- SSH keys are never copied or stored
- All SFTP connections use SSH protocol encryption
- All S3 connections use HTTPS encryption
- **No telemetry** — the app is fully offline and collects nothing
- Backups are encrypted with AES-256-GCM and never leave your machine unless you choose to move them
- All code is open source for transparency

## Roadmap

Future features under consideration:

- [x] Terminal emulator integration
- [x] Go to Folder (⇧⌘G) path navigation
- [x] Encrypted backup & restore (import/export connections)
- [ ] Port forwarding support
- [ ] File synchronization
- [ ] Bookmarks and favorites
- [ ] Split-pane view
- [ ] Theme customization
- [ ] Multi-tab support
- [ ] iCloud sync for connections

## Troubleshooting

### SFTP Connection Issues

- **Can't connect**: Verify host, port, username, and credentials
- **Authentication failed**: Check password or SSH key permissions
- **Timeout**: Check firewall settings and network connectivity

### S3 Connection Issues

- **Access Denied**: Verify your access key and secret key are correct
- **Bucket not found**: Check the bucket name and region settings
- **Invalid credentials**: Ensure IAM user has S3 permissions (s3:ListBucket, s3:GetObject, s3:PutObject)

### File Operations

- **Permission denied**: Ensure your user has appropriate file permissions
- **Upload failed**: Check available disk space on remote server
- **Editor won't open**: Verify file is a text file and not too large

### General

- **App won't launch**: Check macOS version requirements (15.0+); see the first-launch note above if Gatekeeper blocks it
- **Crashes**: Check Console.app for crash logs and report issues

## License

This project is licensed under CC0 1.0 Universal - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Based on [macSCP](https://github.com/macnev2013/macSCP) by macnev2013 (CC0)
- Built with [Citadel](https://github.com/Orlandos-nl/Citadel) by Joannis Orlandos
- S3 support powered by [Soto](https://github.com/soto-project/soto)
- Terminal emulation powered by [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) by Miguel de Icaza
- Uses [SwiftNIO](https://github.com/apple/swift-nio) by Apple
- Icons from SF Symbols by Apple
- Inspired by classic SCP clients and modern macOS design

## Support

- **Issues**: [GitHub Issues](https://github.com/onlymykazari/macSCP-Revived/issues)
- **Discussions**: [GitHub Discussions](https://github.com/onlymykazari/macSCP-Revived/discussions)

---

<p align="center">
  If you find macSCP-Revived useful, please consider giving it a <a href="https://github.com/onlymykazari/macSCP-Revived">star on GitHub</a>!
</p>

<p align="center">
  Made with ❤️ for the macOS community
</p>

<p align="center">
  <a href="#top">Back to top</a>
</p>
