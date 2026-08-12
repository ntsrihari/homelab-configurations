# ============================================================================
# Share ALL drives over SMB, reachable ONLY from the local LAN and Tailscale.
# >>> RUN IN AN ELEVATED POWERSHELL (Run as administrator) <<<
# Access requires your Windows account + password (not anonymous/guest).
# ============================================================================

$acct  = "$env:COMPUTERNAME\ntssr"     # only this account may connect
$lan   = '192.168.29.0/24'             # your home LAN
$tsnet = '100.64.0.0/10'               # Tailscale (CGNAT) range -> covers 100.107.202.55
$scope = @($lan, $tsnet)

# --- 1. One SMB share per drive --------------------------------------------
# NOTE: 'C_System' exposes the Windows OS + your user profile. Delete that line
# below if you'd rather NOT share C:. All shares still require your login.
$shares = [ordered]@{
  'C_System' = 'C:\'
  'D_SSD2'   = 'D:\'
  'E_Vol'    = 'E:\'
  'F_Data'   = 'F:\'
  'G_GDrive' = 'G:\'
  'H_Cloud'  = 'H:\'
  'I_Immich' = 'I:\'
}
foreach ($name in $shares.Keys) {
  $path = $shares[$name]
  if (-not (Test-Path $path)) { Write-Host "skip $name (no $path)"; continue }
  if (Get-SmbShare -Name $name -ErrorAction SilentlyContinue) { Write-Host "$name already exists"; continue }
  New-SmbShare -Name $name -Path $path -FullAccess $acct -CachingMode None | Out-Null
  Write-Host "shared $name -> $path"
}

# --- 2. Firewall: allow SMB (445) ONLY from LAN + Tailscale -----------------
$ruleName = 'SMB LAN+Tailscale only'
if (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue) {
  Set-NetFirewallRule -DisplayName $ruleName -RemoteAddress $scope
} else {
  New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort 445 `
    -Action Allow -Profile Any -RemoteAddress $scope | Out-Null
}
Write-Host "firewall: TCP 445 allowed only from $($scope -join ', ')"

# --- 2b. Web apps (Immich 2283, Nextcloud 8080): also ONLY LAN + Tailscale --
$webRule = 'Immich+Nextcloud web (LAN+Tailscale only)'
if (Get-NetFirewallRule -DisplayName $webRule -ErrorAction SilentlyContinue) {
  Set-NetFirewallRule -DisplayName $webRule -RemoteAddress $scope
} else {
  New-NetFirewallRule -DisplayName $webRule -Direction Inbound -Protocol TCP -LocalPort 2283,8080 `
    -Action Allow -Profile Any -RemoteAddress $scope | Out-Null
}
Write-Host "firewall: TCP 2283 (Immich) + 8080 (Nextcloud) allowed only from LAN + Tailscale"
# If an earlier, broader Immich rule exists, tighten it to the same scope
if (Get-NetFirewallRule -DisplayName 'Immich 2283 (LAN + Tailscale)' -ErrorAction SilentlyContinue) {
  Set-NetFirewallRule -DisplayName 'Immich 2283 (LAN + Tailscale)' -RemoteAddress $scope
}

# --- 3. Constrain built-in File-and-Printer-Sharing rules to the SAME scope -
#     (this is what enforces "ONLY LAN + Tailscale" so a Private cafe wifi can't reach it)
try {
  Get-NetFirewallRule -DisplayGroup 'File and Printer Sharing' -ErrorAction Stop |
    Where-Object { $_.Direction -eq 'Inbound' } |
    Set-NetFirewallRule -RemoteAddress $scope
  Write-Host "built-in SMB rules scoped to LAN + Tailscale"
} catch { Write-Host "note: built-in rules unchanged ($($_.Exception.Message)); dedicated rule still applies" }

# --- 4. Ensure the wired LAN is classified Private (so sharing is permitted) -
try { Set-NetConnectionProfile -InterfaceAlias 'Ethernet' -NetworkCategory Private -ErrorAction Stop } catch {}

Write-Host ""
Write-Host "DONE. From another LAN or Tailscale device:"
Write-Host "  \\192.168.29.96\H_Cloud   (on the LAN)"
Write-Host "  \\100.107.202.55\H_Cloud  (over Tailscale)"
Write-Host "Sign in as $acct with your Windows password."
