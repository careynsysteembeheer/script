# Pad naar het logbestand
$LogFile = "C:\Temp\GPUpdate_Restart.log"

# Zorg dat de map bestaat
$LogDir = Split-Path $LogFile
if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

# Logfunctie
function Write-Log {
    param([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "$Timestamp`t$Message"
    Add-Content -Path $LogFile -Value $LogMessage
    Write-Output $LogMessage
}

Write-Log "Script gestart"

# Forceer Azure AD registratie
Write-Log "Azure AD registratie gestart..."
$Result = dsregcmd.exe /join
$ExitCode = $LASTEXITCODE

if ($ExitCode -eq 0) {
    Write-Log "Azure AD registratie succesvol."
} else {
    Write-Log "FOUT: Azure AD registratie mislukt. ExitCode: $ExitCode"
    Write-Log "Resultaat: $Result"
}


# Forceer groepsbeleid update
Write-Log "Groepsbeleid update gestart..."
gpupdate /force
$ExitCode = $LASTEXITCODE

# Controleer resultaat
if ($ExitCode -eq 0) {
    Write-Log "Groepsbeleid update geslaagd."
    Write-Log "Computer wordt opnieuw opgestart."
    Restart-Computer -Force
} else {
    Write-Log "FOUT: Groepsbeleid update mislukt. ExitCode: $ExitCode"
    Write-Log "Computer wordt NIET opnieuw opgestart."
}

Write-Log "Script geëindigd"
