# Full-scan the Navidrome library (Docker Desktop's Windows v9fs mount has no working
# file-watcher, and quick scans miss files, so a periodic FULL scan is the reliable way
# to pick up newly added music). Run by the "Navidrome Auto Scan" scheduled task.
#
# Hardened so the task can never hang or report a spurious kill:
#   - full path to docker.exe (no PATH dependency)
#   - skips quietly if the container isn't running (e.g. Docker still starting)
#   - runs the scan inside a background job with a hard timeout (no console signals,
#     no waiting on the Task Scheduler execution limit)
#   - logs one line per run to scan.log (trimmed to the last 500 lines)

$ErrorActionPreference = 'SilentlyContinue'
$docker = 'C:\Program Files\Docker\Docker\resources\bin\docker.exe'
$log    = 'F:\homelab\navidrome\scan.log'
function Log($m) { "{0}  {1}" -f ([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')), $m | Add-Content -LiteralPath $log }

# Is the navidrome container running? (also proves the Docker daemon is responsive)
$running = & $docker inspect -f '{{.State.Running}}' navidrome 2>$null
if ($running -ne 'true') { Log "skip - navidrome not running ($running)"; return }

# Run the scan in a job so it has no console (avoids the CTRL_C exit code) and can be
# time-boxed instead of hanging.
$job = Start-Job -ScriptBlock { param($d) & $d exec navidrome navidrome scan --full 2>&1 } -ArgumentList $docker
if (Wait-Job $job -Timeout 300) {
    $out  = Receive-Job $job
    $line = ($out | Select-String 'Finished full rescan|Finished scanning' | Select-Object -Last 1)
    Log ("scan ok - " + ($line -replace '\s+', ' '))
} else {
    Stop-Job $job
    Log "scan TIMED OUT after 300s (Docker busy?)"
}
Remove-Job $job -Force

# keep the log small
if ((Test-Path $log) -and (Get-Content $log).Count -gt 500) {
    (Get-Content $log -Tail 500) | Set-Content -LiteralPath $log
}
