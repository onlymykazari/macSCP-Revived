# macSCP URL Scheme Reference

> Integrating another app with macSCP? The machine-facing contract lives in the
> [URL Scheme Protocol Specification](url-scheme-protocol.md) (Chinese) — this
> page is the end-user guide.

macSCP registers the `macscp://` URL scheme. Other apps on the same Mac can use it
to open macSCP directly on a saved connection — in the file browser or in the
terminal — at a specific remote path. Examples: `open` in Terminal, shell scripts,
Alfred/Raycast commands, Shortcuts, or a plain link in a browser (the browser asks
for confirmation before handing off).

Credentials are **never** part of the URL: a URL only names a *saved* connection or
bookmark, and macSCP resolves its own credentials from the Keychain. Every launch
passes through the same security gates as an in-app connect (Touch ID / app lock,
if configured).

- Requires macSCP 1.2.0 or later.
- Configure and copy ready-made URLs under **Settings → URL Scheme**.

---

## Syntax

```
macscp://open?<parameter>=<value>[&<parameter>=<value>…]
```

The scheme (`macscp`) and host (`open`) are fixed and case-insensitive; a missing
host (`macscp://?connection=…`) is also accepted. Parameters are query-style and
order-independent.

### Parameters

| Parameter   | Required                       | Values                                       | Default | Description |
|-------------|--------------------------------|----------------------------------------------|---------|-------------|
| `connection` | exactly one of `connection` / `bookmark` | saved connection's **name** or **UUID** | — | The target machine. A value that parses as a UUID matches by id; anything else matches by name (case-insensitive). |
| `bookmark`   | exactly one of `connection` / `bookmark` | saved bookmark's **name**                | — | Launch via a saved remote-path bookmark; its path becomes the start path (see below). |
| `view`       | no                             | `files` \| `terminal`                        | `files` | Which window to open. `files` = file browser (works for SFTP **and** S3 connections), `terminal` = SSH terminal (SFTP only). |
| `path`       | no                             | remote directory                             | see start-path rules | Start directory, overriding the bookmark/connection default. |
| `new`        | no                             | `1` \| `true` \| `yes` (case-insensitive)    | off | Force a brand-new window instead of activating an already open one. |

Unknown parameters are logged and ignored. A parameter present with an empty value
(`connection=`) counts as absent.

### Examples

```sh
# File browser on a connection by name
open 'macscp://open?connection=web-prod'

# Terminal on the same connection, starting in /var/log
open 'macscp://open?connection=web-prod&view=terminal&path=/var/log'

# By bookmark — opens at the bookmark's saved path
open 'macscp://open?bookmark=logs'

# Terminal in the remote home directory
open 'macscp://open?connection=web-prod&view=terminal&path=~'

# By connection UUID (immune to renames)
open 'macscp://open?connection=9F0B2A2E-5B13-434E-9FA6-89D75CFF69B4'

# Force a second, independent window even if one is already open
open 'macscp://open?connection=web-prod&view=terminal&new=1'

# Names with spaces / non-ASCII must be percent-encoded
open 'macscp://open?connection=My%20Server&path=/srv/%E9%A1%B9%E7%9B%AE'
```

---

## Target resolution

1. **UUID vs name** — if the `connection` value parses as a UUID, it matches a
   saved connection by id (exact). Otherwise it matches connection names,
   case-insensitively.
2. **Bookmarks** — `bookmark` matches bookmark names across all connections,
   case-insensitively. The launch then targets that bookmark's connection.
3. **Ambiguity** — if a name matches several entries (e.g. two connections named
   `test`), macSCP shows a picker listing the candidates; picking one resumes the
   launch. Cancelling is safe — nothing opens.
4. **Misses** — unknown ids/names produce an error dialog naming the problem
   (see [Errors](#errors)).

## Start-path rules

Which directory the window opens in, in precedence order:

| Priority | Source | Applies to |
|----------|--------|------------|
| 1 | `path` parameter | both views |
| 2 | the bookmark's saved remote path (when launched via `bookmark`) | both views |
| 3 | the connection's *Initial Remote Path* setting | file browser only |
| 4 | server default (home directory) | both views |

Notes:

- A leading `~` (e.g. `~`, `~/logs`) means the remote home directory in both views.
- For `view=terminal` the path is typed into the shell as its first input
  (`cd …`). Paths containing control characters are rejected; quoting is handled
  for you, including single quotes in the path.
- If the target directory doesn't exist, the window still opens (at the server
  default or with an error in the file list) — the launch itself doesn't fail.

## Window behavior

- Without `new=1`, a launch for the same connection **and** view activates the
  window that is already open instead of stacking a duplicate. The `path` of that
  repeat launch is ignored (the window keeps its current location). After closing
  the window, the next launch opens a fresh one with the then-current parameters.
- With `new=1`, every launch opens a new window.
- Terminal and file-browser windows are tracked separately: opening a terminal
  never reuses a browser window, and vice versa.

## Launch behavior

| Situation | What happens |
|-----------|--------------|
| macSCP not running | App launches, then processes the URL. |
| Running, main window open | URL is processed immediately. |
| Running, all windows closed | The main window is reopened automatically, then the URL is processed. |

Multiple URLs delivered in one event are processed in order; each opens its own
session.

---

## Percent-encoding

Query values are percent-decoded by the URL rules (RFC 3986):

| Character | Encode as | Note |
|-----------|-----------|------|
| space | `%20` | **not** `+` — a literal `+` stays a plus |
| `&` | `%26` | otherwise it splits parameters |
| `=` | `%3D` | otherwise it splits name/value |
| `#` | `%23` | otherwise it truncates the URL |
| `%` | `%25` | |
| non-ASCII (e.g. 中文) | UTF-8 bytes, percent-encoded | e.g. 项 → `%E9%A1%B9` |

`/`, `:`, `~` are safe unencoded in query values. The easiest way to get a
correctly encoded URL is **Settings → URL Scheme → Copy URLs**, which encodes
connection names for you.

## Calling macSCP from code and tools

```sh
# Terminal / scripts
open 'macscp://open?connection=web-prod&view=terminal'
```

```applescript
-- AppleScript / osascript
open location "macscp://open?connection=web-prod&view=terminal"
```

```swift
// Swift / Objective-C (NSWorkspace)
NSWorkspace.shared.open(URL(string: "macscp://open?connection=web-prod")!)
```

- **Shortcuts**: use the *Open URLs* action with the URL.
- **Alfred / Raycast**: any "open URL" / custom command entry.
- **Browsers**: typing the URL in the address bar shows a confirmation before
  macOS hands it to macSCP.

## Security model

- **No credentials in URLs.** The URL user-info component (`user:pass@`) is
  ignored — and redacted if it ever appears in logs. Saved passwords never leave
  the app.
- **Saved targets only.** A URL cannot create an ad-hoc connection to an
  arbitrary host; it can only open connections and bookmarks already saved in
  macSCP.
- **Same gates as in-app connects.** If Touch ID / app lock is configured,
  external launches authenticate exactly like clicking *Connect*.
- **Terminal paths are sanitized.** Control characters are rejected and all
  shell metacharacters are neutralized before the start directory is used.
- **Opt-out.** Settings → URL Scheme → *Allow launching from URLs* disables
  processing (launchers get an explanatory error).

## Errors

All failures surface as a dialog in the main window; nothing opens silently.

| Message | Cause |
|---------|-------|
| Unknown URL scheme '…' (expected 'macscp') | A non-`macscp://` URL was handed to the app (e.g. via `open -a`). |
| The URL must specify a 'connection' or 'bookmark' parameter | Neither target given. |
| The URL must not specify both 'connection' and 'bookmark' | Both targets given. |
| Unsupported macscp URL '…' (expected 'open') | Host part isn't `open`. |
| Unknown view '…' (expected 'files' or 'terminal') | Invalid `view` value. |
| No saved connection named '…' / with id … | Target not found. |
| No saved bookmark named '…' | Target not found. |
| The bookmark '…' belongs to a connection that no longer exists | Stale bookmark. |
| A terminal is only available for SFTP connections | `view=terminal` on an S3 connection. |
| Launching macSCP from URLs is disabled in Settings | Feature switched off. |
