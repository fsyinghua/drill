param(
    [string]$vmName,
    [ValidateRange(1,6)][int]$step,
    [switch]$WhatIf
)

function Read-Ini {
    (Get-Content $args[0]) -replace ' ', '' -join "`n" | ConvertFrom-StringData
}

$vmConfig = Read-Ini vm-config.ini
$emailConfig = Read-Ini email-config.ini

Import-Module Az.RecoveryServices

Write-Host "[CFG] : Subscription $($vmConfig.subscriptionId)" -ForegroundColor Cyan
Select-AzSubscription -SubscriptionId $vmConfig.subscriptionId -ErrorAction Stop

Write-Host "[ASR] : $($vmConfig.vaultName)" -ForegroundColor Cyan
$vault = Get-AzRecoveryServicesVault -Name $vmConfig.vaultName -ResourceGroupName $vmConfig.resourceGroup -ErrorAction Stop

$vaultSettingsDir = Join-Path $env:TEMP "vault-settings-$($vmConfig.vaultName)"
New-Item -ItemType Directory -Force -Path $vaultSettingsDir | Out-Null
$vaultSettingsFile = Get-AzRecoveryServicesVaultSettingsFile -Vault $vault -Path $vaultSettingsDir -ErrorAction Stop
Import-AzRecoveryServicesAsrVaultSettingsFile -Path $vaultSettingsFile.FilePath -ErrorAction Stop

# Get protection container
$container = Get-AzRecoveryServicesAsrFabric -Name $vmConfig.fabricName | 
    Get-AzRecoveryServicesAsrProtectionContainer -Name $vmConfig.containerName

# Find protected item
$protectedItem = Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $container |
    Where-Object { $_.FriendlyName -eq $vmName }


if (-not $protectedItem) {
    Write-Error "VM not found: $vmName"
    exit 1
}

# Execute failover step
switch ($step) {
    1 { 
        if ($WhatIf) {
            Write-Host "[] : Start-AzRecoveryServicesAsrUnplannedFailoverJob -ProtectionObject `$protectedItem -Direction PrimaryToRecovery -PerformSourceSideActions -ShutDownSourceServer" -ForegroundColor Yellow
        } else {
            Start-AzRecoveryServicesAsrUnplannedFailoverJob -ProtectionObject $protectedItem `
                -Direction PrimaryToRecovery `
                -PerformSourceSideActions `
                -ShutDownSourceServer
        }
    }
    2 { 
        if ($WhatIf) {
            Write-Host "[] : Start-AzRecoveryServicesAsrCommitFailoverJob -ProtectionObject `$protectedItem" -ForegroundColor Yellow
        } else {
            Start-AzRecoveryServicesAsrCommitFailoverJob -ProtectionObject $protectedItem
        }
    }
    3 { 
        if ($WhatIf) {
            Write-Host "[] : Start-AzRecoveryServicesAsrReprotectJob -ProtectionObject `$protectedItem" -ForegroundColor Yellow
        } else {
            Start-AzRecoveryServicesAsrReprotectJob -ProtectionObject $protectedItem
        }
    }
    4 { 
        if ($WhatIf) {
            Write-Host "[] : Start-AzRecoveryServicesAsrUnplannedFailoverJob -ProtectionObject `$protectedItem -Direction RecoveryToPrimary -PerformSourceSideActions -ShutDownSourceServer" -ForegroundColor Yellow
        } else {
            Start-AzRecoveryServicesAsrUnplannedFailoverJob -ProtectionObject $protectedItem `
                -Direction RecoveryToPrimary `
                -PerformSourceSideActions `
                -ShutDownSourceServer
        }
    }
    5 { 
        if ($WhatIf) {
            Write-Host "[] : Start-AzRecoveryServicesAsrCommitFailoverJob -ProtectionObject `$protectedItem" -ForegroundColor Yellow
        } else {
            Start-AzRecoveryServicesAsrCommitFailoverJob -ProtectionObject $protectedItem
        }
    }
    6 { 
        if ($WhatIf) {
            Write-Host "[] : Start-AzRecoveryServicesAsrReprotectJob -ProtectionObject `$protectedItem" -ForegroundColor Yellow
        } else {
            Start-AzRecoveryServicesAsrReprotectJob -ProtectionObject $protectedItem
        }
    }
}

# Send email notification
$securePassword = ConvertTo-SecureString $emailConfig.password -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential(
    $emailConfig.username,
    $securePassword
)

if (-not $WhatIf) {
    Send-MailMessage -SmtpServer $emailConfig.smtpServer `
        -Port $emailConfig.port -UseSsl -Credential $cred `
        -From $emailConfig.username `
        -To $emailConfig.to.Split(',') `
        -Subject "[DRILL] $vmName step $step" `
        -Body "Operation completed for $vmName (step $step)\nTimestamp: $(Get-Date)"
} else {
    Write-Host "[WHATIF] : Send-MailMessage -SmtpServer $($emailConfig.smtpServer) -Port $($emailConfig.port) -From $($emailConfig.username) -Subject '[DRILL] $vmName step $step'" -ForegroundColor Yellow
}
