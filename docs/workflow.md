# Trinketed Development Workflow

## Local Development

1. Edit files in the project directory (`~/projects/Trinketed/`)
   - Core addon and shared library: edit directly in this repo
   - TrinketedCD: edit in `TrinketedCD/` (this is a git submodule with its own repo)
   - TrinketedHistory: edit in `TrinketedHistory/` (same)

2. Sync to WoW for testing:
   ```bash
   ~/bin/sync-trinketed.sh          # one-time sync
   ~/bin/sync-trinketed.sh --watch  # auto-sync on file changes
   ```

## Pushing Changes

### Core addon (Trinketed)

```bash
git add <files>
git commit -m "your message"
git push
```

This triggers **auto-tag → release** automatically.

### Sub-addons (TrinketedCD / TrinketedHistory)

```bash
cd TrinketedCD   # or TrinketedHistory
git add <files>
git commit -m "your message"
git push
```

That's it. The full pipeline runs automatically:

```
Submodule push to main
  → notify-parent.yml (in submodule repo)
    → update-submodule.yml (in parent repo, updates the pointer)
      → auto-tag.yml (bumps version tag)
        → release.yml (packages and publishes GitHub Release)
```

No need to manually update the submodule pointer in the parent repo.

## CI/CD Workflows

| Workflow | Repo | Trigger | Purpose |
|----------|------|---------|---------|
| `notify-parent.yml` | cd, history | Push to `main` | Tells parent repo to update its submodule pointer |
| `update-submodule.yml` | addon | `workflow_dispatch` | Updates a submodule to latest commit and pushes |
| `auto-tag.yml` | addon | Push to `main` | Bumps patch version tag (e.g., v0.1.2 → v0.1.3) |
| `release.yml` | addon | Tag creation (`v*`) | Runs BigWigsMods packager, publishes GitHub Release |

## Secrets

A single `RELEASE_TOKEN` PAT is stored as an org-level secret on the Trinketed GitHub org. It provides cross-repo workflow triggering and tag creation permissions.

## Branch Naming

All repos use `main` as the default branch.
