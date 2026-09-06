# Full-scan the Navidrome library.
# Why: on Docker Desktop (Windows), the music folder is a v9fs mount with no working
# file-watcher, and Navidrome's quick scans miss files added after startup. A periodic
# FULL scan is the reliable way to pick up newly added music.
# Run by the "Navidrome Auto Scan" scheduled task (every 20 min). Harmless no-op if
# Docker Desktop or the navidrome container isn't running.
$ErrorActionPreference = 'SilentlyContinue'
docker exec navidrome navidrome scan --full *> $null
