# Esconce

Modular post-installation setup for [Bluefin-DX](https://projectbluefin.io/).

Esconce transforms a fresh Bluefin installation into your fully configured
development workstation — custom packages, Flatpaks, GNOME extensions,
Nextcloud sync, desktop settings, and more.

## Quick Start

```bash
git clone https://github.com/derlocke-ng/esconce.git
cd esconce
./esconce.sh --init     # Create config/ from examples
# Edit files in config/ to match your setup
./esconce.sh            # Run setup
```

## Features

- **Modular steps** — each setup phase is a self-contained script in `steps/`
- **Simple config** — plain text list files, one item per line
- **Auto-resume** — saves progress and lets you continue after reboots
- **`--skip` / `--only`** — run or skip any step by name
- **Dry-run mode** — preview changes before applying
- **Logging** — capture full output for debugging
- **Preflight checks** — validates environment before running

## Project Structure

```
esconce/
├── esconce.sh              Main entry point
├── lib/                    Shared library modules
│   ├── logging.sh          Output formatting & log-to-file
│   ├── helpers.sh          run_cmd, confirm, image detection
│   ├── progress.sh         Checkpoint tracking & resume
│   ├── inhibitor.sh        Prevent sleep during setup
│   └── preflight.sh        Pre-run validation checks
├── steps/                  Modular setup steps (NN-name.sh)
│   ├── 01-rebase.sh        Switch to Bluefin-DX
│   ├── 02-ujust.sh         Developer groups & CLI tools
│   ├── 03-repos.sh         Add RPM repositories
│   ├── 04-packages.sh      Layer RPM packages
│   ├── 05-flatpaks.sh      Install Flatpak apps
│   ├── 06-overrides.sh     Flatpak permission overrides
│   ├── 07-extensions.sh    GNOME Shell extensions
│   ├── 08-cacert.sh        Custom CA certificates
│   ├── 09-nextcloud.sh     Preseed Nextcloud folder sync
│   └── 10-dconf.sh         GNOME desktop settings
├── config/                 Your personal configuration (gitignored)
├── config.example/         Template configuration (committed)
└── dconf-backup.sh         Utility: export current dconf settings
```

## Configuration

Run `./esconce.sh --init` to create `config/` from the examples, then edit:

| File / Directory | Purpose |
|---|---|
| `config/settings.sh` | Server URLs, feature toggles |
| `config/packages.list` | RPM packages to layer (one per line) |
| `config/flatpaks.list` | Flatpak app IDs (one per line) |
| `config/extensions.list` | GNOME extension UUIDs (one per line) |
| `config/repos.d/` | `.repo` files copied to `/etc/yum.repos.d/` |
| `config/flatpak-overrides/` | Per-app override files (native format) |
| `config/nextcloud/folders.list` | Sync folder definitions |
| `config/nextcloud/exclude.lst` | Global sync exclusion rules |
| `config/nextcloud/exclude.d/` | Per-folder exclusions via tags |
| `config/certs/` | CA certificates (`.pem` files) |
| `config/dconf-settings.ini` | GNOME desktop settings |
| `config/gtk3-bookmarks` | Nautilus sidebar bookmarks |

### List file format

All `.list` files use the same simple format:

```
# Comments start with #
# Blank lines are ignored

some-package       # Inline comments work too
another-package
```

### Nextcloud folder tags

Sync folders can have *tags* that link to per-folder exclusion files:

```
# folders.list — format: localPath|remotePath[|tags]
Documents|/cloud/Documents
.var/app/io.gitlab.librewolf-community|/cloud/apps/librewolf|browser
```

The `browser` tag causes `exclude.d/browser.lst` to be placed as
`.sync-exclude.lst` inside that folder, preventing SQLite corruption
while still syncing safe files like `user.js` and `bookmarkbackups/`.

### Flatpak overrides

Files in `config/flatpak-overrides/` use the **native Flatpak override
format**. The filename is the app ID:

```ini
# config/flatpak-overrides/com.valvesoftware.Steam
[Context]
filesystems=~/games;xdg-run/gvfs
```

## Usage

```bash
./esconce.sh                          # Run all steps
./esconce.sh --skip rebase,ujust      # Skip specific steps
./esconce.sh --only extensions,dconf  # Run only specific steps
./esconce.sh --dry-run                # Preview without making changes
./esconce.sh --log                    # Save output to log file
./esconce.sh --log /tmp/debug.log     # Log to specific file
./esconce.sh --status                 # Show progress
./esconce.sh --list-steps             # List available steps
./esconce.sh --reset                  # Clear progress, start fresh
./esconce.sh --init                   # Create config from examples
```

## Adding Custom Steps

Drop a new file in `steps/` following the naming convention:

```bash
#!/bin/bash
# Step: mystep
# Description: Do something awesome

step_mystep() {
    log_info "Running my custom step..."
    # Your logic here — use run_cmd, confirm, log_*, etc.
}
```

Name it `NN-mystep.sh` where the number controls execution order. The runner
auto-discovers it — no registration needed.

## For Template Builders

Esconce is designed to be reusable for custom OS image builds
(like [finpilot](https://github.com/projectbluefin/finpilot)):

- **`config.example/`** serves as the template others start from
- **`config/`** is gitignored — fork the repo, customize examples, ship it
- **Step modules** in `steps/` can be sourced individually from other scripts
- **Library modules** in `lib/` are self-contained and reusable


## License

GPL-3.0
