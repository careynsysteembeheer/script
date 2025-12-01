# Log file
$LogFile = "C:\Temp\AAD_Repair.log"
$LogDir = Split-Path $LogFile

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

# 1. Direct aan het begin: GPupdate
Write-Log "Groepsbeleid update gestart..."
gpupdate /force | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Log "Groepsbeleid update geslaagd."
} else {
    Write-Log "FOUT: Groepsbeleid update mislukt. ExitCode: $LASTEXITCODE"
}

# 2. Loop tot Azure AD join gelukt is
while ($true) {

    $status = (dsregcmd.exe /status) -join ""
    if ($status -match "AzureAdJoined\s*:\s*YES") {
        Write-Log "Device is AzureADJoined. Klaar!"
        break
    }

    Write-Log "Device is NIET AzureADJoined. Azure AD herregistratie nodig."

    Write-Log "Opruimen oude device registraties..."
    dsregcmd /leave | Out-Null

    try {
        Remove-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Registry CloudDomainJoin verwijderd."
    } catch {
        Write-Log "Registry CloudDomainJoin kon niet worden verwijderd: $_"
    }

    try {
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
        Write-Log "AzureAD Join succesvol."
    } else
        {
        Write-Log "FOUT: Azure AD join mislukt. ExitCode: $JoinExitCode"
        Write-Log "Resultaat: $Result"
    }

    Write-Log "Join mislukt — wacht 60 seconden en probeer opnieuw..."
    Start-Sleep -Seconds 60
}

Write-Log "=== SCRIPT EINDE ==="
