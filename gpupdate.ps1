# Log file
$LogFile = "C:\Temp\AAD_Repair.log"
$LogDir = Split-Path $LogFile
$RetryScript = "C:\Temp\AAD_Retry.ps1"
$TaskName = "AAD_Retry_Join"

if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "$Timestamp`t$Message"
    Add-Content -Path $LogFile -Value $LogMessage
    Write-Output $LogMessage
}

Write-Log "=== SCRIPT START ==="

# 1. Direct GPupdate
Write-Log "Groepsbeleid update gestart..."
gpupdate /force | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Log "Groepsbeleid update geslaagd."
} else {
    Write-Log "FOUT: Groepsbeleid update mislukt. ExitCode: $LASTEXITCODE"
}

# 2. Retry-script genereren
Write-Log "Retry-script wordt aangemaakt..."

$RetryScriptContent = @'
$LogFile = "C:\Temp\AAD_Repair.log"
function Write-Log {
    param([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "$Timestamp`t$Message"
    Add-Content -Path $LogFile -Value $LogMessage
    Write-Output $LogMessage
}

$status = (dsregcmd.exe /status) -join ""
if ($status -match "AzureAdJoined\s*:\s*YES") {
    Write-Log "Device is AzureADJoined. Retry-task wordt opgeruimd."
    Unregister-ScheduledTask -TaskName "AAD_Retry_Join" -Confirm:$false
    Remove-Item "C:\Temp\AAD_Retry.ps1" -Force
    exit 0
}

Write-Log "=========================="
Write-Log "Nieuwe join poging..."

Write-Log "Opruimen oude device registraties..."
dsregcmd /leave | Out-Null

Try {
    Remove-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "Registry CloudDomainJoin verwijderd."
} catch {
    Write-Log "Registry CloudDomainJoin kon niet worden verwijderd: $_"
}

Try {
    $certs = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -like "*MS-Organization*" }
    foreach ($cert in $certs) {
        Remove-Item -Path ("Cert:\LocalMachine\My\" + $cert.Thumbprint) -Force
        Write-Log "Certificaat verwijderd: $($cert.Subject)"
    }
} catch {
    Write-Log "Verwijderen certificaten mislukt: $_"
}

Write-Log "Azure AD registratie proberen..."
$Result = dsregcmd.exe /join
$JoinExitCode = $LASTEXITCODE

if ($JoinExitCode -eq 0) {
    Write-Log "AzureAD Join succesvol!"
} else {
    Write-Log "FOUT: Azure AD join mislukt. ExitCode: $JoinExitCode"
    Write-Log "Resultaat: $Result"
}
'@

Set-Content -Path $RetryScript -Value $RetryScriptContent -Force
Write-Log "Retry-script aangemaakt op $RetryScript"

# 3. Scheduled task aanmaken
Write-Log "Scheduled task wordt aangemaakt..."

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$RetryScript`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days 1)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Force

Write-Log "Scheduled task '$TaskName' aangemaakt en actief."

Write-Log "=== SCRIPT EINDE ==="
