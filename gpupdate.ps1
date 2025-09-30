# Forceer een groepsbeleid update
Write-Output "Groepsbeleid wordt bijgewerkt..."
gpupdate /force

Write-Output "Groepsbeleid update uitgevoerd. De computer wordt nu opnieuw opgestart."
Restart-Computer -Force
