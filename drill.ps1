param(
    [string]$vmName,
    [string]$InputFile,
    [ValidateRange(1,6)][int]$step,
    [switch]$WhatIf
)

function Read-Ini {
    (Get-Content $args[0]) -replace ' ', '' -join "`n" | ConvertFrom-StringData
}

$vmConfig = Read-Ini vm-config.ini
$emailConfig = Read-Ini email-config.ini

# Load VM list from input file
$vmList = @()
if ($InputFile) {
    if (-not (Test-Path $InputFile)) {
        Write-Error "Input file not found: $InputFile"
        exit 1
    }
    $vmList = Get-Content $InputFile | Where-Object { $_ -match '\S' }
    if (-not $vmList) {
        Write-Error "No VM names found in input file"
        exit 1
    }
    Write-Host "[BATCH] Loaded $($vmList.Count) VMs from $InputFile" -ForegroundColor Green
} elseif (-not $vmName) {
    Write-Error "Please specify -vmName or -InputFile"
    exit 1
} else {
    $vmList = @($vmName)
}

Import-Module Az.RecoveryServices

Write-Host "[CFG] : Subscription $($vmConfig.subscriptionId)" -ForegroundColor Cyan
Select-AzSubscription -SubscriptionId $vmConfig.subscriptionId -ErrorAction Stop

Write-Host "[ASR] : $($vmConfig.vaultName)" -ForegroundColor Cyan
$vault = Get-AzRecoveryServicesVault -Name $vmConfig.vaultName -ResourceGroupName $vmConfig.resourceGroup -ErrorAction Stop

$vaultSettingsDir = Join-Path $env:TEMP "vault-settings-$($vmConfig.vaultName)"
New-Item -ItemType Directory -Force -Path $vaultSettingsDir | Out-Null
$vaultSettingsFile = Get-AzRecoveryServicesVaultSettingsFile -Vault $vault -Path $vaultSettingsDir -ErrorAction Stop
Import-AzRecoveryServicesAsrVaultSettingsFile -Path $vaultSettingsFile.FilePath -ErrorAction Stop

# Prepare email credentials
$securePassword = ConvertTo-SecureString $emailConfig.password -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential(
    $emailConfig.username,
    $securePassword
)

# Process each VM
foreach ($targetVm in $vmList) {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "[VM] Processing: $targetVm" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    # Get protection container
    $container = Get-AzRecoveryServicesAsrFabric -Name $vmConfig.fabricName |
        Get-AzRecoveryServicesAsrProtectionContainer -Name $vmConfig.containerName

    # Find protected item
    $protectedItem = Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $container |
        Where-Object { $_.FriendlyName -eq $targetVm }

    if (-not $protectedItem) {
        Write-Error "VM not found: $targetVm"
        continue
    }

    # Execute failover step
    switch ($step) {
        1 {
            if ($WhatIf) {
                Write-Host "[WHATIF] : Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction PrimaryToRecovery -PerformSourceSideActions -ShutDownSourceServer" -ForegroundColor Yellow
            } else {
                Start-AzRecoveryServicesAsrUnplannedFailoverJob -ProtectionObject $protectedItem `
                    -Direction PrimaryToRecovery `
                    -PerformSourceSideActions `
                    -ShutDownSourceServer
            }
        }
        2 {
            if ($WhatIf) {
                Write-Host "[WHATIF] : Start-AzRecoveryServicesAsrCommitFailoverJob" -ForegroundColor Yellow
            } else {
                Start-AzRecoveryServicesAsrCommitFailoverJob -ProtectionObject $protectedItem
            }
        }
        3 {
            if ($WhatIf) {
                Write-Host "[WHATIF] : Start-AzRecoveryServicesAsrReprotectJob" -ForegroundColor Yellow
            } else {
                Start-AzRecoveryServicesAsrReprotectJob -ProtectionObject $protectedItem
            }
        }
        4 {
            if ($WhatIf) {
                Write-Host "[WHATIF] : Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction RecoveryToPrimary -PerformSourceSideActions -ShutDownSourceServer" -ForegroundColor Yellow
            } else {
                Start-AzRecoveryServicesAsrUnplannedFailoverJob -ProtectionObject $protectedItem `
                    -Direction RecoveryToPrimary `
                    -PerformSourceSideActions `
                    -ShutDownSourceServer
            }
        }
        5 {
            if ($WhatIf) {
                Write-Host "[WHATIF] : Start-AzRecoveryServicesAsrCommitFailoverJob" -ForegroundColor Yellow
            } else {
                Start-AzRecoveryServicesAsrCommitFailoverJob -ProtectionObject $protectedItem
            }
        }
        6 {
            if ($WhatIf) {
                Write-Host "[WHATIF] : Start-AzRecoveryServicesAsrReprotectJob" -ForegroundColor Yellow
            } else {
                Start-AzRecoveryServicesAsrReprotectJob -ProtectionObject $protectedItem
            }
        }
    }

    # Send email notification
    if (-not $WhatIf) {
        Send-MailMessage -SmtpServer $emailConfig.smtpServer `
            -Port $emailConfig.port -UseSsl -Credential $cred `
            -From $emailConfig.username `
            -To $emailConfig.to.Split(',') `
            -Subject "[DRILL] $targetVm step $step" `
            -Body "Operation completed for $targetVm (step $step)`nTimestamp: $(Get-Date)"
    } else {
        Write-Host "[WHATIF] : Send-MailMessage -Subject '[DRILL] $targetVm step $step'" -ForegroundColor Yellow
    }
}
