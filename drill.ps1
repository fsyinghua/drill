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

# 邮箱配置
Write-Host "[] : $($vmConfig.subscriptionId)" -ForegroundColor Cyan
Select-AzSubscription -SubscriptionId $vmConfig.subscriptionId -ErrorAction Stop

Write-Host "[] : $($vmConfig.vaultName)" -ForegroundColor Cyan
$vault = Get-AzRecoveryServicesVault -Name $vmConfig.vaultName -ResourceGroupName $vmConfig.resourceGroup -ErrorAction Stop

Write-Host "[] ASR" -ForegroundColor Cyan
Set-AzRecoveryServicesAsrVaultContext -Name $vmConfig.vaultName -ErrorAction Stop

# 获取容器
$container = Get-AzRecoveryServicesAsrFabric -Name $vmConfig.fabricName | 
    Get-AzRecoveryServicesAsrProtectionContainer -Name $vmConfig.containerName

# 
$protectedItem = Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $container |
    Where-Object { $_.FriendlyName -eq $vmName }


if (-not $protectedItem) {
    Write-Error "未找到虚拟机: $vmName"
    exit 1
}

# 
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

# 
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
