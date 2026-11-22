# ===== 1. Configure Core RDP Settings =====
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
                 -Name "fDenyTSConnections" -Value 0 -Force
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' `
                 -Name "UserAuthentication" -Value 0 -Force
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' `
                 -Name "SecurityLayer" -Value 0 -Force

netsh advfirewall firewall delete rule name="RDP-Tailscale"
netsh advfirewall firewall add rule name="RDP-Tailscale" `
    dir=in action=allow protocol=TCP localport=3389

Restart-Service -Name TermService -Force

# ===== 2. Create RDP User =====
$password = 'Loscabos2021!!!'
$securePass = ConvertTo-SecureString $password -AsPlainText -Force
New-LocalUser -Name "hesiz" -Password $securePass -AccountNeverExpires
Add-LocalGroupMember -Group "Administrators" -Member "hesiz"
Add-LocalGroupMember -Group "Remote Desktop Users" -Member "hesiz"

if (-not (Get-LocalUser -Name "hesiz")) {
    Write-Error "User creation failed"
    exit 1
}

# ===== 3. Install Tailscale =====
$tsUrl = "https://pkgs.tailscale.com/stable/tailscale-setup-1.82.0-amd64.msi"
$installerPath = "$env:TEMP\tailscale.msi"

Invoke-WebRequest -Uri $tsUrl -OutFile $installerPath
Start-Process msiexec.exe -ArgumentList "/i", "`"$installerPath`"", "/quiet", "/norestart" -Wait
Remove-Item $installerPath -Force

# ===== 4. Establish Tailscale Connection =====
& "$env:ProgramFiles\Tailscale\tailscale.exe" up --authkey=$env:TAILSCALE_AUTH_KEY --hostname=gh-runner-$env:GITHUB_RUN_ID

$tsIP = $null
$retries = 0
while (-not $tsIP -and $retries -lt 10) {
    $tsIP = & "$env:ProgramFiles\Tailscale\tailscale.exe" ip -4
    Start-Sleep -Seconds 5
    $retries++
}

if (-not $tsIP) {
    Write-Error "Tailscale IP not assigned. Exiting."
    exit 1
}

# ===== 5. Verify RDP Accessibility =====
Write-Host "Tailscale IP: $tsIP"
$testResult = Test-NetConnection -ComputerName $tsIP -Port 3389
if (-not $testResult.TcpTestSucceeded) {
    Write-Error "TCP connection to RDP port 3389 failed"
    exit 1
}
Write-Host "TCP connectivity successful!"

# ===== 6. Maintain Connection =====
Write-Host "`n=== RDP ACCESS ==="
Write-Host "Address: $tsIP"
Write-Host "Username: hesiz"
Write-Host "Password: $password"
Write-Host "==================`n"

while ($true) {
    Write-Host "[$(Get-Date)] RDP Active - Use Ctrl+C in workflow to terminate"
    Start-Sleep -Seconds 300
}
