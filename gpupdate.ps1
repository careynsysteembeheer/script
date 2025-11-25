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

# 1. Status check
$status = (dsregcmd.exe /status) -join ""
if ($status -match "AzureAdJoined\s*:\s*YES") {
    Write-Log "Device is al AzureADJoined. Geen registratie nodig."
} else {
    Write-Log "Device is NIET AzureADJoined. Azure AD herregistratie nodig."

    # 2. Force cleanup
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

    # 3. Join opnieuw uitvoeren
    Write-Log "Azure AD registratie proberen..."
    $Result = dsregcmd.exe /join
    $ExitCode = $LASTEXITCODE

    if ($ExitCode -eq 0) {
        Write-Log "AzureAD Join succesvol."
    } else {
        Write-Log "FOUT: Azure AD join mislukt. ExitCode: $ExitCode"
        Write-Log "Resultaat: $Result"
    }
}

# 4. GPupdate draaien
Write-Log "Groepsbeleid update gestart..."
gpupdate /force | Out-Null
$ExitCode = $LASTEXITCODE

if ($ExitCode -eq 0) {
    Write-Log "Groepsbeleid update geslaagd."

    # 5. Check join status na join
    $status = (dsregcmd.exe /status) -join ""
    if ($status -match "AzureAdJoined\s*:\s*YES") {
        Write-Log "Azure AD Join status is OK. Reboot uitvoeren."
        Restart-Computer -Force
    } else {
        Write-Log "Azure AD Join mislukt of niet compleet -> GEEN reboot."
    }

} else {
    Write-Log "FOUT: Groepsbeleid update mislukt. ExitCode: $ExitCode"
    Write-Log "Computer wordt NIET opnieuw opgestart."
}

Write-Log "=== SCRIPT EINDE ==="
