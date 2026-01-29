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

# 设置上下文（关键三步）
Write-Host "[上下文] 正在切换订阅: $($vmConfig.subscriptionId)" -ForegroundColor Cyan
Select-AzSubscription -SubscriptionId $vmConfig.subscriptionId -ErrorAction Stop

Write-Host "[上下文] 正在定位保险库: $($vmConfig.vaultName)" -ForegroundColor Cyan
$vault = Get-AzRecoveryServicesVault -Name $vmConfig.vaultName -ResourceGroupName $vmConfig.resourceGroup -ErrorAction Stop

Write-Host "[上下文] 正在设置ASR上下文" -ForegroundColor Cyan
Set-AzRecoveryServicesAsrVaultContext -Vault $vault -ErrorAction Stop

# 获取保护容器
$container = Get-AzRecoveryServicesAsrFabric -Name $vmConfig.fabricName | 
    Get-AzRecoveryServicesAsrProtectionContainer -Name $vmConfig.containerName

# 查找目标虚拟机
$protectedItem = Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $container |
    Where-Object { $_.FriendlyName -eq $vmName }


if (-not $protectedItem) {
    Write-Error "未找到虚拟机: $vmName"
    exit 1
}

# 执行操作
switch ($step) {
    1 { 
        if ($WhatIf) {
            Write-Host "[模拟] 将执行: Start-AzRecoveryServicesAsrUnplannedFailoverJob -ProtectionObject `$protectedItem -Direction PrimaryToRecovery -PerformSourceSideActions -ShutDownSourceServer" -ForegroundColor Yellow
        } else {
            Start-AzRecoveryServicesAsrUnplannedFailoverJob -ProtectionObject $protectedItem `
                -Direction PrimaryToRecovery `
                -PerformSourceSideActions `
                -ShutDownSourceServer
        }
    }
    2 { 
        if ($WhatIf) {
            Write-Host "[模拟] 将执行: Start-AzRecoveryServicesAsrCommitFailoverJob -ProtectionObject `$protectedItem" -ForegroundColor Yellow
        } else {
            Start-AzRecoveryServicesAsrCommitFailoverJob -ProtectionObject $protectedItem
        }
    }
    3 { 
        if ($WhatIf) {
            Write-Host "[模拟] 将执行: Start-AzRecoveryServicesAsrReprotectJob -ProtectionObject `$protectedItem" -ForegroundColor Yellow
        } else {
            Start-AzRecoveryServicesAsrReprotectJob -ProtectionObject $protectedItem
        }
    }
    4 { 
        if ($WhatIf) {
            Write-Host "[模拟] 将执行: Start-AzRecoveryServicesAsrUnplannedFailoverJob -ProtectionObject `$protectedItem -Direction RecoveryToPrimary -PerformSourceSideActions -ShutDownSourceServer" -ForegroundColor Yellow
        } else {
            Start-AzRecoveryServicesAsrUnplannedFailoverJob -ProtectionObject $protectedItem `
                -Direction RecoveryToPrimary `
                -PerformSourceSideActions `
                -ShutDownSourceServer
        }
    }
    5 { 
        if ($WhatIf) {
            Write-Host "[模拟] 将执行: Start-AzRecoveryServicesAsrCommitFailoverJob -ProtectionObject `$protectedItem" -ForegroundColor Yellow
        } else {
            Start-AzRecoveryServicesAsrCommitFailoverJob -ProtectionObject $protectedItem
        }
    }
    6 { 
        if ($WhatIf) {
            Write-Host "[模拟] 将执行: Start-AzRecoveryServicesAsrReprotectJob -ProtectionObject `$protectedItem" -ForegroundColor Yellow
        } else {
            Start-AzRecoveryServicesAsrReprotectJob -ProtectionObject $protectedItem
        }
    }
}

# 发送邮件
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
    Write-Host "[模拟] 将执行: Send-MailMessage -SmtpServer $($emailConfig.smtpServer) -Port $($emailConfig.port) -From $($emailConfig.username) -Subject \"[DRILL] $vmName step $step\"" -ForegroundColor Yellow
}