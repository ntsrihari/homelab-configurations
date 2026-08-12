# Nextcloud on this Windows PC — the OneDrive-like cloud

Self-hosted file cloud for backing up **non-photo** files from phones (Immich handles
photos/videos). Files are stored browsably on `H:`; the database is kept safely off `H:`.

## 1. Architecture

```
Docker Desktop (WSL2)  — compose project "nextcloud" (F:\homelab\nextcloud\)
├─ nextcloud_app    :8080  → http://192.168.29.96:8080  /  http://100.107.202.55:8080 (Tailscale)
├─ nextcloud_db     (MariaDB)  → Docker VOLUME nextcloud_db  (ext4 in WSL2, NOT on H:)
└─ nextcloud_redis  (cache/locking)
H:\NextcloudData  → /var/www/html/data   user files, browsable at H:\NextcloudData\<user>\files\
Docker VOLUME nextcloud_app → /var/www/html   app code + config
```

## 2. Key paths / facts

| Thing | Value |
|-------|-------|
| Compose / env | `F:\homelab\nextcloud\docker-compose.yml` + `.env` |
| File data (browsable) | `H:\NextcloudData\<user>\files\...` |
| Database | Docker volume **`nextcloud_db`** (MariaDB, never on H:) |
| App/config | Docker volume **`nextcloud_app`** |
| LAN URL | `http://192.168.29.96:8080` |
| Tailscale URL | `http://100.107.202.55:8080` |
| DB passwords | in `.env` (`MYSQL_ROOT_PASSWORD`, `MYSQL_PASSWORD`) — **back up** |
| Timezone | `Asia/Kolkata` |

## 3. Create the admin account
Open `http://localhost:8080` (or the LAN URL). The database is pre-wired via the compose
env, so it only asks you to choose an **admin username + password** → Finish setup.

## 4. Phone backup (auto upload)
1. Install the **Nextcloud** app on each phone.
2. Server: `http://192.168.29.96:8080` at home, `http://100.107.202.55:8080` over Tailscale.
3. Log in → **Settings → Auto upload** → enable for the folders you want backed up
   (Documents, Downloads, WhatsApp, etc.). Leave camera photos to Immich (or enable here too
   for a second copy).

## 5. H: can disconnect (it's a USB drive)
- User **files** live on `H:`. If `H:` unplugs, file access fails until it's reconnected,
  but the **database is safe** (it's in the `nextcloud_db` Docker volume, not on H:).
- Keep the `H:` drive letter pinned (Disk Management) so the bind mount stays valid.

## 6. Start / stop / update
```
cd F:\homelab\nextcloud
docker compose ps
docker compose up -d          # start / apply
docker compose stop|start|restart
docker compose logs -f nextcloud-app
# update (Nextcloud upgrades one major at a time — don't skip majors):
docker compose pull
docker compose up -d
docker compose exec -u www-data nextcloud-app php occ upgrade   # if prompted
```

## 7. What to back up (files alone are NOT a full backup)
1. **`H:\NextcloudData`** — the actual files (browsable). Required.
2. **Database** `nextcloud_db` — users, shares, metadata, sync state. Required, not recreatable:
   ```
   cd F:\homelab\nextcloud
   docker compose exec -T nextcloud-db sh -c 'exec mariadb-dump --single-transaction -uroot -p"$MARIADB_ROOT_PASSWORD" nextcloud' > nextcloud-db.sql
   ```
3. **`.env`** (holds DB passwords) + this compose file.
Restoring files without the DB loses shares/accounts; the DB without files loses the data.

## 8. Network sharing (SMB) — `setup-network-shares.ps1`
Run `setup-network-shares.ps1` **elevated** to share all drives over SMB, restricted to LAN +
Tailscale only. See the top-level repo README for details.

## 9. Migration to Ubuntu (future)
Copy compose + `.env` (adjust `NEXTCLOUD_DATA` to a Linux path), `mariadb-dump` → restore into
a fresh MariaDB, and copy `H:\NextcloudData` to the new data path. Put Nextcloud into
maintenance mode during the copy. Keep the same DB name/user/passwords and Nextcloud version.

## 10. Do NOT
- Put the database on `H:` or any network share.
- Hand-edit files inside `H:\NextcloudData` outside Nextcloud, then expect it to notice
  instantly — run `occ files:scan --all` after external changes.
- Skip Nextcloud major versions when updating.
