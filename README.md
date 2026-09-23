# Windows Dotfiles

This repository is the source of truth for personal configuration. `dotfiles.yaml` maps files from `apps/` and the profile-shaped `home/` tree to their Windows locations. PowerShell commands apply, inspect, and capture those mappings.

## Structure

```text
.dotfiles/
├── apps/
│   └── zed/
│       ├── settings.json
│       ├── keymap.json
│       └── themes/spencer-zed-theme.json
├── home/
│   └── .config/starship.toml
├── scripts/
│   ├── Apply.ps1
│   ├── Backup.ps1
│   ├── Bootstrap.ps1
│   ├── Capture.ps1
│   ├── Status.ps1
│   ├── Utils.ps1
│   └── dotfiles.ps1
├── backups/.gitkeep
├── dotfiles.yaml
├── install.ps1
└── README.md
```

The `home/` directory mirrors paths below `%USERPROFILE%`. For example, `home/.config/starship.toml` maps to `%USERPROFILE%\.config\starship.toml`. A `mode: directory` manifest entry expands files individually, so the manager never links the whole user profile. Files named `.gitkeep` only preserve empty directories and are ignored by the mapper.

Application-specific files live under `apps/<application>/`. The current Zed entries use copy mode at `%APPDATA%\Zed` so Zed reads ordinary files. The Zed settings entry preserves the local `ssh_connections` key across apply and excludes it from status comparisons and capture, keeping it out of the shared repository. Use `capture` after editing other deployed settings in Zed.

## Requirements and setup

Use PowerShell 7.2 or newer (`pwsh`). The YAML manifest uses the `powershell-yaml` PowerShell Gallery module. Run the bootstrap from the repository root:

```powershell
.\install.ps1
```

Bootstrap installs that module for the current user if needed, validates the manifest, applies the entries, and reports status. It does not install the applications whose settings are managed. A `symlink` entry requires Windows Developer Mode or elevated permissions; the manager reports a clear error and does not silently fall back to copying.

## Commands

```powershell
.\scripts\dotfiles.ps1 apply
.\scripts\dotfiles.ps1 status
.\scripts\dotfiles.ps1 capture
```

Select one top-level entry or an individual expanded home file:

```powershell
.\scripts\dotfiles.ps1 apply zed-settings
.\scripts\dotfiles.ps1 status home
.\scripts\dotfiles.ps1 capture zed-settings
.\scripts\dotfiles.ps1 status home/.config/starship.toml
```

`apply` creates target parent directories and deploys enabled entries. `status` compares target state with the manifest. `capture` copies changed `copy` targets back to the repository; a symlink entry already points to its source. Commands return a non-zero exit code if entries fail or need attention.

## Manifest and modes

`dotfiles.yaml` is generic. Sources are relative to the repository unless absolute. Targets may use `${USERPROFILE}`, `${APPDATA}`, `${LOCALAPPDATA}`, or variables defined in the manifest. Variables can refer to other manifest variables or environment variables. Unknown and circular variables fail with an error. Entries support `source`, `target`, `mode`, `file_mode` (for directory entries), `preserve_keys` (for copied JSON objects), `groups`, `machines`, and `enabled`. Preserved top-level JSON keys remain local at the target: apply retains their target values, status compares the managed fields and requires the shared source to omit those keys, and capture strips them from the repository copy. Groups are recorded for future group selection; the current CLI selects entries by name.

- `symlink`: create a file symbolic link from the target to the repository source.
- `copy`: copy the repository file to the target; `status` compares file content and `capture` copies target changes back.
- `directory`: expand every file below `source` into a mapping at the same relative path below `target`, using `file_mode` (`symlink` by default or `copy`).

## Backups and safety

Before replacing any existing file or incorrect symbolic link, `apply` saves it below `backups/<machine>/<timestamp>/`. Paths inside the current user profile retain their profile-relative structure; other paths retain their drive or UNC namespace. Backups have a `.dotfiles-backup.json` sidecar with their original path. Link backups also have a `.dotfiles-link.json` sidecar with the original link destination. File contents are copied and verified before the target changes. A backup is created only when a target is about to change. Backup content is ignored by Git while `backups/.gitkeep` stays tracked.

The manager does not recursively remove a directory target, overwrite a target before verifying its backup, or silently fall back from symlink to copy.