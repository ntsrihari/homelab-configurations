# Homelab config

Docker Compose stacks and setup scripts for a self-hosted homelab running on a Windows 11 PC
(Docker Desktop / WSL2 backend), designed to migrate to an Ubuntu server later. LAN
`192.168.29.96`, Tailscale `100.107.202.55` — never exposed to the public internet.

## Contents

| Path | What |
|------|------|
| `immich/` | **Immich** — photo/video backup from phones. Read-only external library on `I:\Photos`, generated + uploaded media on `I:\ImmichData`, Postgres in a Docker volume. Port **2283**. See `immich/README-immich.md`. |
| `nextcloud/` | **Nextcloud** — OneDrive-like cloud for other phone files. Data on `H:\NextcloudData`, MariaDB in a Docker volume. Port **8080**. See `nextcloud/README-nextcloud.md`. |
| `nextcloud/setup-network-shares.ps1` | Shares all drives over SMB, restricted to **LAN + Tailscale only**. Run elevated. |

## Drive layout

| Drive | Role |
|-------|------|
| `I:` (USB exFAT) | Immich only — `I:\Photos` (existing, read-only) + `I:\ImmichData` (Immich media) |
| `H:` (USB NTFS) | Nextcloud cloud storage — `H:\NextcloudData` |
| Docker volumes | `immich_pgdata`, `nextcloud_db`, `nextcloud_app`, `model-cache` (databases live here, off the USB drives) |

## Secrets

Real `.env` files are **git-ignored** (they hold DB passwords). Each stack has a committed
`.env.example` template — copy it to `.env` and fill in real values. The live `.env` files
already exist locally in each stack folder; keep a secure backup of them (they're required to
open the databases after a restore or migration).

## Networking

`nextcloud/setup-network-shares.ps1` (run in an elevated PowerShell) creates one SMB share per
drive and constrains SMB (445) plus the web apps (Immich 2283, Nextcloud 8080) to the home LAN
subnet and the Tailscale range **only**. Access requires the Windows account `PC\ntssr`.

## Common ops

```
cd immich      # or: cd nextcloud
docker compose ps
docker compose up -d          # start / apply changes
docker compose stop|start|restart
docker compose logs -f
```

## Backups (per stack, see each README)

A complete backup is always **three** parts, not just one:
1. the original/source files on disk,
2. a database dump (Postgres for Immich, MariaDB for Nextcloud), and
3. the `.env` + compose config.
