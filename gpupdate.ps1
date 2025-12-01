# Log file primary
$LogFile = "C:\Temp\AAD_Repair_Main.log"
$LogDir = Split-Path $LogFile

if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

function Write-LogA {
    param([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "$Timestamp`t$Message"
    Add-Content -Path $LogFile -Value $LogMessage
    Write-Output $LogMessage
}

Write-LogA "=== SCRIPT START (MAIN) ==="

# 1. GPUpdate aan het begin
Write-LogA "Groepsbeleid update gestart..."
gpupdate /force | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-LogA "Groepsbeleid update geslaagd."
} else {
    Write-LogA "FOUT: Groepsbeleid update mislukt. ExitCode: $LASTEXITCODE"
}

# 2. Azure AD join test
$status = (dsregcmd.exe /status) -join ""
if ($status -match "AzureAdJoined\s*:\s*YES") {
    Write-LogA "Device is al AzureADJoined → niets te doen."
    Write-LogA "=== SCRIPT EINDE ==="
    exit
}

Write-LogA "Device is NIET AzureADJoined. Eénmalige attempt..."

Write-LogA "Azure AD registratie proberen..."
$Result = dsregcmd.exe /join
$ExitCode = $LASTEXITCODE

if ($ExitCode -eq 0) {
    Write-LogA "AzureAD Join succesvol."
    Write-LogA "=== SCRIPT EINDE ==="
    exit
} else {
    Write-LogA "FOUT: Azure AD join mislukt. ExitCode: $ExitCode"
    Write-LogA "Resultaat: $Result"
}

# 3. Script B genereren op disk
$RetryScript = "C:\Temp\AAD_Repair_Retry.ps1"
Write-LogA "Retry script wordt geschreven naar: $RetryScript"

$RetrySource = @'
# Log file retry
$LogFile = "C:\Temp\AAD_Repair_Retry.log"
$LogDir = Split-Path $LogFile

if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

function Write-LogB {
    param([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "$Timestamp`t$Message"
    Add-Content -Path $LogFile -Value $LogMessage
}

Write-LogB "=== SCRIPT START (RETRY) ==="

while ($true) {
    $status = (dsregcmd.exe /status) -join ""
    if ($status -match "AzureAdJoined\s*:\s*YES") {
        Write-LogB "Device is AzureADJoined. Script stopt."
        Write-LogB "=== SCRIPT EINDE (RETRY) ==="
        exit
    }

    Write-LogB "Device niet AzureAdJoined → nieuwe poging..."

    dsregcmd /leave | Out-Null
    Remove-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin" -Recurse -Force -ErrorAction SilentlyContinue

    try {
        $certs = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -like "*MS-Organization*" }
        foreach ($cert in $certs) {
            Remove-Item -Path ("Cert:\LocalMachine\My\" + $cert.Thumbprint) -Force
        }
    } catch {}

    Write-LogB "Join proberen..."
    dsregcmd /join | Out-Null

    Start-Sleep -Seconds 60
}
'@

Set-Content -Path $RetryScript -Value $RetrySource -Force -Encoding UTF8

# 4. Script B starten in achtergrond
Write-LogA "Start achtergrondproces voor retry..."
Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$RetryScript`"" -WindowStyle Hidden

Write-LogA "=== SCRIPT EINDE ==="
