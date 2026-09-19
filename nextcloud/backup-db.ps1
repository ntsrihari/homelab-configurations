<#
    backup-db.ps1  --  Nextcloud MariaDB backup (Windows / Docker Desktop)

    Dumps the "nextcloud_db" container's database to a timestamped, gzipped .sql.gz
    OUTSIDE the git repo (DB dumps contain user data and must never be pushed to GitHub).

    Restore set for full recovery = this DB dump  +  H:\NextcloudData  +  F:\homelab\nextcloud\.env
    (files-on-disk alone are NOT a full restore -- the DB holds shares/metadata.)

    Reads the DB password from .env at runtime; no secrets are stored in this script.
    Scheduled daily by a Windows Task (see README-nextcloud.md). Run manually anytime:
        powershell -NoProfile -ExecutionPolicy Bypass -File F:\homelab\nextcloud\backup-db.ps1
#>

$ErrorActionPreference = 'Stop'

# ---- Config -------------------------------------------------------------
$EnvFile    = Join-Path $PSScriptRoot '.env'
$Container  = 'nextcloud_db'
$BackupDir  = 'F:\Backups\nextcloud\db'   # OUTSIDE the git repo on purpose
$KeepCount  = 14                          # how many daily dumps to retain
$LogFile    = Join-Path $BackupDir 'backup.log'
# -------------------------------------------------------------------------

function Write-Log($msg) {
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Write-Output $line
    try { Add-Content -Path $LogFile -Value $line -Encoding utf8 } catch {}
}

# Ensure backup dir exists
if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }

# Parse .env for the DB name + root password
if (-not (Test-Path $EnvFile)) { Write-Log "FATAL: .env not found at $EnvFile"; exit 1 }
$envMap = @{}
foreach ($l in Get-Content $EnvFile) {
    if ($l -match '^\s*#') { continue }
    if ($l -match '^\s*([A-Za-z0-9_]+)\s*=\s*(.*)$') { $envMap[$matches[1]] = $matches[2].Trim() }
}
$dbName = $envMap['MYSQL_DATABASE']
$dbPass = $envMap['MYSQL_ROOT_PASSWORD']
if ([string]::IsNullOrWhiteSpace($dbName)) { $dbName = 'nextcloud' }
if ([string]::IsNullOrWhiteSpace($dbPass)) { Write-Log "FATAL: MYSQL_ROOT_PASSWORD missing in .env"; exit 1 }

# Confirm the DB container is running
$running = (& docker inspect -f '{{.State.Running}}' $Container) 2>$null
if ($running -ne 'true') { Write-Log "FATAL: container '$Container' is not running (is Docker Desktop up?)"; exit 1 }

$stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$outFile = Join-Path $BackupDir "nextcloud-db_$stamp.sql.gz"

Write-Log "START dump of '$dbName' -> $outFile"

# Run mariadb-dump | gzip inside the container; stream RAW BYTES to the host file.
# MYSQL_PWD keeps the password off the in-container command line.
# .Arguments (single string) is used because PS 5.1 / .NET Framework has no ArgumentList.
$innerCmd = "exec mariadb-dump --single-transaction --routines --triggers --default-character-set=utf8mb4 -u root $dbName | gzip -c"
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName               = 'docker'
$psi.Arguments              = "exec -e MYSQL_PWD=$dbPass $Container sh -c `"$innerCmd`""
$psi.UseShellExecute        = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError  = $true
$psi.CreateNoWindow         = $true

$proc = [System.Diagnostics.Process]::Start($psi)
$fs   = [System.IO.File]::Create($outFile)
try {
    $proc.StandardOutput.BaseStream.CopyTo($fs)
} finally {
    $fs.Close()
}
$stderr = $proc.StandardError.ReadToEnd()
$proc.WaitForExit()

if ($proc.ExitCode -ne 0) {
    Write-Log "FATAL: dump failed (exit $($proc.ExitCode)). stderr: $stderr"
    if (Test-Path $outFile) { Remove-Item $outFile -Force }
    exit 1
}

# Validate: gzip magic bytes (1f 8b) + non-trivial size
$fi = Get-Item $outFile
$magic = [byte[]](Get-Content -Path $outFile -Encoding Byte -TotalCount 2)
if ($fi.Length -lt 1024 -or $magic[0] -ne 0x1f -or $magic[1] -ne 0x8b) {
    Write-Log "FATAL: output looks invalid (size=$($fi.Length), magic=$($magic[0]),$($magic[1])). Removing."
    Remove-Item $outFile -Force
    exit 1
}
if ($stderr) { Write-Log "note (stderr, non-fatal): $stderr" }
Write-Log ("OK  dump complete: {0:N0} bytes" -f $fi.Length)

# Rotation: keep the newest $KeepCount, delete older
$old = Get-ChildItem $BackupDir -Filter 'nextcloud-db_*.sql.gz' |
       Sort-Object LastWriteTime -Descending | Select-Object -Skip $KeepCount
foreach ($f in $old) { Remove-Item $f.FullName -Force; Write-Log "pruned old backup: $($f.Name)" }

Write-Log "DONE"
exit 0
