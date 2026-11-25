function Log($msg) { Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $msg" }

# ===== 0. Comprobaciones iniciales =====
Log "=== INICIO ==="
$authKey = 'tskey-auth-k1ws48sWe821CNTRL-Tn1f1SgdtWArmTdT1Z7HXAxSXj9maZKF'
Log "Auth key cargada (longitud: $($authKey.Length))"

# ===== 1. Configure Core RDP Settings =====
Log "[1/6] Configurando RDP..."
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
Log "[1/6] RDP configurado. Servicio TermService: $((Get-Service TermService).Status)"

# ===== 2. Create RDP User =====
Log "[2/6] Creando usuario hesiz..."
$password = 'Loscabos2021!!!'
$securePass = ConvertTo-SecureString $password -AsPlainText -Force
New-LocalUser -Name "hesiz" -Password $securePass -AccountNeverExpires
Add-LocalGroupMember -Group "Administrators" -Member "hesiz"
Add-LocalGroupMember -Group "Remote Desktop Users" -Member "hesiz"

if (-not (Get-LocalUser -Name "hesiz")) {
    Log "ERROR: no se pudo crear el usuario"
    exit 1
}
Log "[2/6] Usuario hesiz creado correctamente"

# ===== 3. Install Tailscale =====
Log "[3/6] Descargando Tailscale..."
$tsUrl = "https://pkgs.tailscale.com/stable/tailscale-setup-1.82.0-amd64.msi"
$installerPath = "$env:TEMP\tailscale.msi"

Invoke-WebRequest -Uri $tsUrl -OutFile $installerPath
Log "[3/6] Descargado ($((Get-Item $installerPath).Length) bytes). Instalando..."
$proc = Start-Process msiexec.exe -ArgumentList "/i", "`"$installerPath`"", "/quiet", "/norestart" -Wait -PassThru
Log "[3/6] msiexec termino con codigo: $($proc.ExitCode)"
Remove-Item $installerPath -Force

$tsExe = "$env:ProgramFiles\Tailscale\tailscale.exe"
if (-not (Test-Path $tsExe)) {
    Log "ERROR: no existe $tsExe, la instalacion fallo"
    exit 1
}
Log "[3/6] Tailscale instalado. Servicio: $((Get-Service Tailscale -ErrorAction SilentlyContinue).Status)"

# ===== 4. Establish Tailscale Connection =====
Log "[4/6] Conectando a Tailscale (timeout 60s)..."
& $tsExe up --authkey=$authKey --hostname=gh-runner-$env:GITHUB_RUN_ID --timeout=60s
Log "[4/6] 'tailscale up' termino con codigo: $LASTEXITCODE"

Log "Estado de Tailscale:"
& $tsExe status

$tsIP = $null
$retries = 0
while (-not $tsIP -and $retries -lt 10) {
    $tsIP = & $tsExe ip -4
    if (-not $tsIP) {
        $retries++
        Log "[4/6] Esperando IP... intento $retries/10"
        Start-Sleep -Seconds 5
    }
}

if (-not $tsIP) {
    Log "ERROR: Tailscale no asigno IP. Probablemente el auth key es invalido o expiro."
    exit 1
}
Log "[4/6] IP de Tailscale: $tsIP"

# ===== 5. Verify RDP Accessibility =====
Log "[5/6] Verificando puerto 3389..."
$testResult = Test-NetConnection -ComputerName $tsIP -Port 3389
if (-not $testResult.TcpTestSucceeded) {
    Log "ERROR: fallo la conexion TCP al puerto 3389"
    exit 1
}
Log "[5/6] Conexion TCP al puerto 3389 exitosa"

# ===== 6. Maintain Connection =====
Log "[6/6] Todo listo"
Write-Host "`n=== RDP ACCESS ==="
Write-Host "Address: $tsIP"
Write-Host "Username: hesiz"
Write-Host "Password: $password"
Write-Host "==================`n"

while ($true) {
    Log "RDP Active - Cancela el workflow para terminar"
    Start-Sleep -Seconds 300
}
