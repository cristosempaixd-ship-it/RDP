function Log($msg) { Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $msg" }

# ===== 0. Comprobaciones iniciales =====
Log "=== INICIO ==="
$authKey = 'tskey-auth-k6LJ1wFAdJ11CNTRL-JdypnTNHu7EsggJZcroL7EcDsmWF4NUt'
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
Log "[3/6] Descargando Tailscale (ultima version)..."
$tsUrl = "https://pkgs.tailscale.com/stable/tailscale-setup-latest-amd64.msi"
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
Log "Version de Tailscale: $(& $tsExe version | Select-Object -First 1)"
Log "Servicio Tailscale: $((Get-Service Tailscale -ErrorAction SilentlyContinue).Status)"

# ===== 4. Establish Tailscale Connection =====
Log "[4/6] Probando conexion a los servidores de Tailscale..."
foreach ($h in @("controlplane.tailscale.com", "login.tailscale.com")) {
    $t = Test-NetConnection -ComputerName $h -Port 443 -WarningAction SilentlyContinue
    Log "  $h:443 -> TcpTestSucceeded=$($t.TcpTestSucceeded)"
}
Log "netcheck:"
& $tsExe netcheck 2>&1 | ForEach-Object { Log "  $_" }

$tsIP = $null
for ($attempt = 1; $attempt -le 3 -and -not $tsIP; $attempt++) {
    Log "[4/6] Intento $attempt/3: tailscale up (timeout 90s)..."
    & $tsExe up --reset --authkey=$authKey --hostname=gh-runner-$env:GITHUB_RUN_ID --timeout=90s 2>&1 | ForEach-Object { Log "  $_" }
    Log "[4/6] 'tailscale up' termino con codigo: $LASTEXITCODE"

    Log "Estado de Tailscale:"
    & $tsExe status 2>&1 | ForEach-Object { Log "  $_" }

    $tsIP = (& $tsExe ip -4 2>$null | Select-Object -First 1)

    if (-not $tsIP) {
        Log "Sin IP. Ultimas lineas del log de Tailscale:"
        Get-ChildItem "$env:ProgramData\Tailscale" -Recurse -Include *.log -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1 |
            ForEach-Object { Get-Content $_.FullName -Tail 40 | ForEach-Object { Log "  $_" } }
        Log "Reiniciando servicio Tailscale..."
        Restart-Service -Name Tailscale -Force
        Start-Sleep -Seconds 5
    }
}

if (-not $tsIP) {
    Log "ERROR: Tailscale no asigno IP despues de 3 intentos."
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
