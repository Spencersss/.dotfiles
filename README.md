# Windows Dotfiles

This repository is the source of truth for personal configuration files. A YAML manifest maps repository files to their application-required locations, and a small PowerShell manager applies, checks, or captures those mappings.

## Structure

```text
dotfiles/
├── .config/starship.toml
├── config/dotfiles.yaml
├── scripts/dotfiles.ps1
├── scripts/modules/
│   ├── Apply.ps1
│   ├── Capture.ps1
│   ├── Status.ps1
│   └── Utils.ps1
├── backups/.gitkeep
├── install.ps1
└── README.md
```

The scripts find the repository root from their own location, so the checkout can live on any drive or in a directory containing spaces.

## Requirements and install

Use PowerShell 7.2 or newer (`pwsh`). The YAML manifest is parsed by the `powershell-yaml` PowerShell Gallery module. Bootstrap it and apply the manifest with:

```powershell
.\install.ps1
```

The installer checks the manifest, confirms symbolic-link support in a temporary directory, applies entries, and runs status. It does not install the applications whose settings are managed.

On Windows, creating symbolic links may require Developer Mode or elevated permissions. The manager reports a clear error and never silently changes a symlink entry into a copy.

## Commands

Run these from any current directory by using the full path to the checked-out script, or from the repository root as shown:

```powershell
.\scripts\dotfiles.ps1 apply
.\scripts\dotfiles.ps1 status
.\scripts\dotfiles.ps1 capture
```

Target one entry by name:

```powershell
.\scripts\dotfiles.ps1 apply starship
.\scripts\dotfiles.ps1 status starship
.\scripts\dotfiles.ps1 capture starship
```

`apply` creates the target parent directory and deploys each enabled entry. `status` reports whether each target matches the declared mode. `capture` copies a changed `copy` target back into the repository; a symlink entry already writes directly to the repository and has nothing to capture. Commands return a non-zero exit code if an entry fails or needs attention.

## Manifest

The initial `config/dotfiles.yaml` entry is generic:

```yaml
version: 1

variables:
  HOME: "${USERPROFILE}"

entries:
  starship:
    source: ".config/starship.toml"
    target: "${HOME}/.config/starship.toml"
    mode: symlink
    groups:
      - terminal
      - common
    enabled: true
```

Sources are relative to the repository unless absolute. Targets may use `${USERPROFILE}`, `${APPDATA}`, `${LOCALAPPDATA}`, or variables defined in the manifest. Manifest variables can refer to other manifest or environment variables. Unknown and circular variables fail with an error. Entries accept `source`, `target`, `mode`, `groups`, `machines`, and `enabled`. Disabled entries and entries filtered to another machine are skipped. Groups are recorded for future group selection; the current CLI selects entries by name.

Supported modes:

- `symlink`: create a file symbolic link from the target to the repository source.
- `copy`: copy the repository file to the target; `status` compares file content and `capture` copies target changes back.

## Backups and safety

Before replacing any existing file or incorrect symbolic link, `apply` saves a backup below `backups/<machine>/<timestamp>/`. Paths inside the current user profile retain their profile-relative structure. Other paths retain their drive or UNC namespace. Every backup includes a `.dotfiles-backup.json` sidecar with its original path; link backups also include a `.dotfiles-link.json` sidecar with the original link destination. A broken link is recorded in the sidecar. File contents are copied and verified before the target changes. A backup is created only when a target is about to change. The ignore rules keep backup contents out of Git while preserving `backups/.gitkeep`.

The manager does not recursively remove a directory target, overwrite an unexpected target before verifying its backup, or silently fall back from symlink to copy.

## Add a managed configuration

Put the clean configuration in the repository, then add a manifest entry. Most applications require no changes to PowerShell code. For example:

```yaml
  example:
    source: "apps/example/config.json"
    target: "${APPDATA}/Example/config.json"
    mode: symlink
    groups:
      - development
```

Use `mode: copy` for applications that do not work correctly with symlinks. Re-run `apply` and `status` for that entry to deploy and verify it.
