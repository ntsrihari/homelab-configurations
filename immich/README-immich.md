# Immich on this Windows PC — operations, backup & migration

This machine is **stage 1** of a homelab. It runs a clean single-node Immich now,
and is designed to later hand the primary role to an Ubuntu server while this PC
becomes a secondary copy/backup target.

---

## 1. Architecture (current)

```
Windows 11 PC (Ryzen 5 5600X, 32GB, RTX 4070)  LAN 192.168.29.96/24
│
├─ Docker Desktop (WSL2 backend)
│   └─ compose project "immich"  (F:\immich\docker-compose.yml + .env)
│        ├─ immich_server            :2283  → http://192.168.29.96:2283
│        ├─ immich_machine_learning
│        ├─ immich_redis   (valkey)
│        └─ immich_postgres          → Docker VOLUME immich_pgdata (ext4 in WSL2 VHDX)
│
├─ I:\ImmichData      → /data     Immich-managed: phone uploads, thumbs, transcodes
└─ I:\Photos (USB)    → /mnt/photos  READ-ONLY external library (existing 512GB collection)
```

Remote access later = **Tailscale** (already installed, 100.107.202.55). No port
forwarding, no public exposure.

## 2. Key paths / facts

| Thing | Value |
|-------|-------|
| Compose file | `F:\immich\docker-compose.yml` |
| Environment file | `F:\immich\.env` |
| Immich-managed storage (UPLOAD_LOCATION) | `I:\ImmichData`  → container `/data` (on the external drive, by choice) |
| External library source | `I:\Photos` (read-only) → container `/mnt/photos` |
| External library import path (enter in UI) | `/mnt/photos` |
| Postgres storage | Docker-managed volume **`immich_pgdata`** (never NTFS) |
| DB password | in `F:\immich\.env` (`DB_PASSWORD`) — **back this up** |
| Timezone | `Asia/Kolkata` |
| Immich version | pinned `v3.1.0` in `.env` |
| LAN URL | `http://192.168.29.96:2283` |
| Tailscale URL (remote) | `http://100.107.202.55:2283` — needs the inbound firewall rule below |

### Remote access over Tailscale
Immich publishes on all interfaces, so it's reachable at `http://100.107.202.55:2283`
from any device signed into the same tailnet — no port forwarding, nothing public.
Requirement: a Windows Firewall inbound allow for TCP 2283 (run once, elevated):
```
New-NetFirewallRule -DisplayName "Immich 2283 (LAN + Tailscale)" -Direction Inbound -Protocol TCP -LocalPort 2283 -Action Allow -Profile Any
```
In the mobile app you can set the server to the LAN URL for home and the Tailscale URL
for away (Immich supports auto-switching between two server URLs).

## 3. The external drive (I:) can disconnect — how that's handled

**Important:** BOTH the read-only library (`I:\Photos`) and Immich's writable store
(`I:\ImmichData`) now live on the external drive. So if `I:` disconnects:
- the **read-only library** photos show **offline** (never deleted) — harmless, and
- **phone backups pause** and Immich **cannot read/write its own data** (thumbnails,
  new uploads) until the drive returns. The web app may error until reconnected.
Keep the drive connected during normal use; treat a disconnect as "Immich is paused."
If this fragility becomes annoying, moving `UPLOAD_LOCATION` to `C:\ImmichData`
(779 GB free, internal) is a one-line change — see §13 for the exact relocation steps.

- The library mount is **`:ro`**. Immich can never write, move, rename, or delete anything
  on `I:\Photos`. Windows stays the source of truth.
- If `I:` is **disconnected**: the stack keeps running, **phone backups keep working**
  (they go to `I:\ImmichData`), and the external photos simply show as **offline** in
  Immich. They are **not deleted** from the catalog.
- When you **reconnect** `I:`: make sure it still has drive letter **I:**, then in
  Immich run the library job again (Administration → External Libraries → ⋯ → *Scan*).
  Offline assets come back online. If the container was started while I: was absent and
  the mount looks empty, restart the stack (see §7) after reconnecting.
- **Keep the drive letter stable:** Disk Management → right-click the One Touch volume →
  *Change Drive Letter and Paths* → keep it pinned to **I:**. A changed letter breaks the
  mount until you fix `EXTERNAL_LIBRARY` in `.env`.
- Do **not** enable "remove offline files" in the library settings, or a scan while the
  drive is unplugged would purge the catalog entries (originals still stay safe on I:).

## 4. Create the admin account

1. Open `http://192.168.29.96:2283` (or `http://localhost:2283` on this PC).
2. First visit shows **"Getting Started" → Create admin account**. Set email, name,
   and a strong password. This first user is the server admin.
3. Log in. (Optional) Administration → Users to add family accounts later.

## 5. Add the External Library (existing photos, read-only)

1. Log in as admin → **Administration → External Libraries → Create Library**, pick the
   owner (your admin user).
2. Open the new library → **Edit Import Paths → Add path** → enter exactly:
   `/mnt/photos` → Save.
3. ⋯ menu → **Scan New Library Files**. Immich indexes in place (no copying of originals).
4. Leave **"Delete offline files"** OFF so a disconnected drive never purges entries.

## 6. Configure phone backup (Immich mobile app)

1. Install **Immich** from the App Store / Play Store on each phone.
2. Server URL: `http://192.168.29.96:2283` (must be on the same Wi-Fi/LAN).
   Later, over Tailscale, use the PC's Tailscale IP/name instead.
3. Log in with your Immich account.
4. **Backup → select albums / Camera Roll → Enable Backup**. Turn on **Background backup**
   and (optionally) **Foreground backup**. These uploads land in `I:\ImmichData` — they are
   ORIGINALS that exist only inside Immich, so they must be backed up (see §9).

## 7. Start / stop / restart / status

Run from `F:\immich` (PowerShell):

```
cd F:\immich
docker compose ps            # status + health
docker compose up -d         # start (create/refresh containers)
docker compose stop          # stop containers, keep them
docker compose start         # start existing containers
docker compose restart       # restart
docker compose down          # stop AND remove containers (VOLUMES/DATA are kept)
docker compose logs -f       # follow logs
```

`docker compose down` does **not** delete the `immich_pgdata` volume or `I:\ImmichData`.
Never run `docker compose down -v` unless you intend to destroy the database volume.

## 8. Update Immich

```
cd F:\immich
# 1) (recommended) back up the DB first — see §9
# 2) edit .env: set IMMICH_VERSION to the new release tag (e.g. v3.2.0)
docker compose pull
docker compose up -d
```

Review the release notes before jumping major versions. Because the version is pinned,
Immich never auto-upgrades on its own.

## 9. What must be backed up  (read this carefully)

Backing up the Postgres database ALONE is **NOT** a complete Immich backup. Three
distinct data sets exist:

1. **Existing collection — `I:\Photos`** (512GB). These are your originals and Immich
   only reads them. Back them up the way you already do (they're independent of Immich).
2. **Immich database — volume `immich_pgdata`.** Albums, faces, users, metadata, and the
   *links* to both `/data` and `/mnt/photos`. Recreatable ML/thumbs are NOT in here, but
   everything that makes the library "yours" is. Dump it:
   ```
   cd F:\immich
   docker compose exec -T database pg_dumpall --clean --if-exists -U postgres > immich-db-backup.sql
   ```
3. **Immich-managed media — `I:\ImmichData`.** This holds:
   - `I:\ImmichData\library\...` → **phone-backup ORIGINALS that exist nowhere else** — must back up.
   - `I:\ImmichData\thumbs`, `encoded-video`, `profile`, etc. → generated, **recreatable**
     by re-running jobs, but re-generating for a big library is slow, so backing them up
     saves time.

**Complete backup = (1) your I:\Photos routine  +  (2) a pg_dumpall  +  (3) I:\ImmichData\library**
(plus optionally the rest of I:\ImmichData and the `F:\immich` config folder incl. `.env`).

Also keep a copy of **`F:\immich\.env`** (holds `DB_PASSWORD`) and `docker-compose.yml`.

## 10. Migration plan to Ubuntu (future primary)

What actually needs to move:
- **Config:** `F:\immich\docker-compose.yml` + `.env` → copy to the Ubuntu host, adjust
  paths (`UPLOAD_LOCATION=/srv/immich/data`, `EXTERNAL_LIBRARY=/srv/photos`, etc.).
- **Database (required, not recreatable):** `pg_dumpall` on Windows → restore into the
  fresh Postgres on Ubuntu:
  ```
  # Windows (source):
  docker compose exec -T database pg_dumpall --clean --if-exists -U postgres > immich.sql
  # Ubuntu (target), with a fresh empty immich stack running:
  cat immich.sql | docker compose exec -T database psql -U postgres -d postgres
  ```
  Use the **same DB_PASSWORD** in the Ubuntu `.env`, and match the Immich version.
- **Immich-managed media (required for phone-backup originals):** copy `I:\ImmichData`
  → Ubuntu `UPLOAD_LOCATION` (e.g. rsync/robocopy). Keep the internal `library/` and,
  if you want to skip re-generation, `thumbs/`, `encoded-video/`.
- **Generated data (recreatable):** thumbs + transcodes + ML cache can be dropped and
  rebuilt via Immich jobs if you'd rather not copy them.
- **External library paths change:** on Ubuntu the mount becomes e.g.
  `- /srv/photos:/mnt/photos:ro`. **Keep the container path `/mnt/photos` identical** so
  the database's stored paths still match and you don't re-import. Physically the I: drive
  (or its contents) moves to / is reachable by the Ubuntu host. Only the host side of the
  mount changes; the in-container path stays `/mnt/photos`.
- **Postgres note:** it's in a Docker volume specifically so it stays on a Linux/ext4
  filesystem — which is exactly what Ubuntu wants. `pg_dumpall` → `psql` is the clean path;
  do not copy the raw NTFS/WSL volume files across.

## 11. Future mirror/backup topology — recommendation

Evaluated:
- **A. Windows primary now → Ubuntu primary later, Windows as backup** ✅ recommended path.
- B. Ubuntu primary → Windows backup — same end state as A; A is just the ordering that
  matches "we're starting on Windows today."
- C. Shared storage both instances mount — **do not**: two Immich DBs over one library =
  corruption/confusion. Not replication.
- D. **One Immich instance + replicated storage + DB backups** ✅ this is what "backup"
  should mean here.

**Recommendation:** run exactly **one** live Immich (Ubuntu, once ready). This Windows box
becomes a **cold/secondary copy**, NOT a second live server: it receives
(a) periodic `pg_dumpall` files and (b) a file-level mirror of `UPLOAD_LOCATION` (and your
`I:\Photos` if it stays here). That's model **A + D**. It is the safest and easiest to
maintain: no active-active, no shared-DB, no clustering. If the Ubuntu host dies you can
stand Immich back up on Windows from the dump + media copy. Do **not** point two running
Immich servers at the same library or database.

## 12. Do NOT change manually

- Don't edit, add, rename, or delete files inside `I:\ImmichData` by hand — Immich manages
  that tree; hand edits desync it from the database.
- Don't touch the `immich_pgdata` Docker volume's files directly. Use `pg_dumpall`/`psql`.
- Don't write to `I:\Photos` expecting Immich to react instantly — it's read-only to Immich;
  add/remove originals with your normal tools, then run a library scan.
- Don't run `docker compose down -v` (destroys the DB volume).
- Don't run a second live Immich against the same library/DB.

## 13. Relocating the writable store (UPLOAD_LOCATION) — the `.immich` marker gotcha

Immich writes a hidden `.immich` marker into each store subfolder and records in the
database that those mounts are verified. If you just change `UPLOAD_LOCATION` to a new
empty folder, the server **crash-loops** with `Failed to read .../.immich` (a safety check
so it never writes into a wrong/unmounted path). To relocate correctly:

```
cd F:\immich
docker compose stop immich-server
# copy the ENTIRE existing store (incl. hidden .immich markers + all data) to the new path
robocopy <OLD_UPLOAD_LOCATION> <NEW_UPLOAD_LOCATION> /E
# edit .env: set UPLOAD_LOCATION=<NEW_UPLOAD_LOCATION>
docker compose up -d immich-server
```

Example to move back to internal C: →
`robocopy I:\ImmichData C:\ImmichData /E`, then set `UPLOAD_LOCATION=C:/ImmichData`.
(This is exactly how the store was moved from F:\ to I:\ during setup.)

## 14. Resource limits (keep gaming / heavy tasks smooth)

- **GPU is untouched:** hardware acceleration was intentionally NOT enabled, so the
  RTX 4070 is 100% free for games. Immich ML/transcoding runs on CPU only.
- **CPU/RAM cap:** `C:\Users\ntssr\.wslconfig` limits Docker's WSL2 VM to `processors=6`
  (of 12) and `memory=12GB` (of 32), with `autoMemoryReclaim=gradual`. So the whole Immich
  stack can never grab more than half your CPU or hoard RAM. Editing `.wslconfig` requires
  `wsl --shutdown` (Docker auto-restarts) or a reboot to take effect.
- **Heaviest load is the one-time initial import** (thumbnails + face/CLIP indexing of your
  20k photos). To go easy on the CPU during it: Immich → Administration → Settings → **Job
  Concurrency** and lower Thumbnail Generation / Smart Search / Face Detection concurrency.
- **During intense sessions** you can also just pause Immich: `cd F:\immich; docker compose stop`
  then `docker compose start` afterwards. Phone backups resume when it's back up.
- Lower `processors=4` in `.wslconfig` if you ever feel in-game stutter during an import.
