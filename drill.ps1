param(
    [string]$vmName,
    [string]$InputFile,
    [ValidateRange(1,6)][int]$step,
    [switch]$WhatIf,
    [switch]$Parallel
)

$ErrorActionPreference = "Stop"

function Read-Ini {
    (Get-Content $args[0]) -replace ' ', '' -join "`n" | ConvertFrom-StringData
}

function Wait-AsrJob {
    param([object]$Job)

    if ($null -eq $Job) {
        throw "ASR Job was not created"
    }

    Write-Host "  Job started: $($Job.Name) - State: $($Job.State)" -ForegroundColor Gray

    $maxWaitMinutes = 60
    $startTime = Get-Date

    while ($Job.State -eq "InProgress" -or $Job.State -eq "NotStarted") {
        $elapsed = (Get-Date) - $startTime
        if ($elapsed.TotalMinutes -gt $maxWaitMinutes) {
            throw "ASR Job timeout after $maxWaitMinutes minutes"
        }

        Start-Sleep -Seconds 15
        try {
            $Job = Get-AzRecoveryServicesAsrJob -Job $Job
        } catch {
            Write-Host "  Warning: Failed to refresh job status: $_" -ForegroundColor Yellow
        }
        Write-Host "  Job status: $($Job.State) (Elapsed: $([math]::Round($elapsed.TotalMinutes, 1)) min)" -ForegroundColor Gray
    }

    if ($Job.State -ne "Completed" -and $Job.State -ne "Succeeded") {
        $errorMsg = $Job.ErrorDescription
        if ([string]::IsNullOrEmpty($errorMsg)) {
            $errorMsg = "State: $($Job.State)"
        }
        throw "ASR Job failed: $errorMsg"
    }

    Write-Host "  Job completed: $($Job.Name)" -ForegroundColor Gray
    return $Job
}

$vmConfig = Read-Ini vm-config.ini
$emailConfig = Read-Ini email-config.ini

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

if ($Parallel -and $vmList.Count -gt 1) {
    Write-Host "[PARALLEL] Starting $($vmList.Count) parallel jobs..." -ForegroundColor Cyan
    Write-Host ""

    $jobs = @()
    $logDir = Join-Path $env:TEMP "drill-logs-$([guid]::NewGuid().ToString('N')[0..7])"
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null

    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "[EXECUTION PLAN]" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Subscription: $($vmConfig.subscriptionId)" -ForegroundColor Gray
    Write-Host "Vault: $($vmConfig.vaultName)" -ForegroundColor Gray
    Write-Host "Resource Group: $($vmConfig.resourceGroup)" -ForegroundColor Gray
    Write-Host "Fabric: $($vmConfig.fabricName)" -ForegroundColor Gray
    Write-Host "Container: $($vmConfig.containerName)" -ForegroundColor Gray
    Write-Host "Step: $step" -ForegroundColor Gray
    Write-Host "WhatIf: $WhatIf" -ForegroundColor Gray
    Write-Host "Log Directory: $logDir" -ForegroundColor Gray
    Write-Host ""
    Write-Host "[VMs TO PROCESS]" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $stepCmd = @("",
        "Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction PrimaryToRecovery -PerformSourceSideAction",
        "Start-AzRecoveryServicesAsrCommitFailoverJob",
        "Update-AzRecoveryServicesAsrProtectionDirection -AzureToAzure",
        "Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction RecoveryToPrimary -PerformSourceSideAction",
        "Start-AzRecoveryServicesAsrCommitFailoverJob",
        "Update-AzRecoveryServicesAsrProtectionDirection -AzureToAzure")[$step]

    $executionPlan = @()

    foreach ($targetVm in $vmList) {
        $logFile = Join-Path $logDir "$targetVm.log"

        Write-Host "VM: $targetVm" -ForegroundColor Yellow
        Write-Host "  Command: $stepCmd" -ForegroundColor Gray
        Write-Host "  Log File: $logFile" -ForegroundColor Gray
        Write-Host "  Temp Script: job-$targetVm.ps1" -ForegroundColor Gray
        Write-Host ""

        $executionPlan += @{
            VM = $targetVm
            Command = $stepCmd
            LogFile = $logFile
            TempScript = "job-$targetVm.ps1"
        }

        $scriptContent = @"
ErrorActionPreference = "Stop"

$vmConfig = @{subscriptionId="$($vmConfig.subscriptionId)";vaultName="$($vmConfig.vaultName)";resourceGroup="$($vmConfig.resourceGroup)";fabricName="$($vmConfig.fabricName)";containerName="$($vmConfig.containerName)"}
$emailConfig = @{smtpServer="$($emailConfig.smtpServer)";port="$($emailConfig.port)";username="$($emailConfig.username)";password="$($emailConfig.password)";to="$($emailConfig.to)"}

$targetVm = "$targetVm"
$step = $step
$WhatIf = $$WhatIf
$logFile = "$logFile"

$operationStartTime = Get-Date

New-Item -ItemType File -Path $logFile -Force | Out-Null

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $Message = "[$timestamp] $Message"
    $Message | Out-File -FilePath $logFile -Encoding UTF8 -Append
    [Console]::WriteLine($Message)
    [Console]::Out.Flush()
}

function Get-ElapsedTime {
    param([DateTime]$StartTime, [DateTime]$EndTime)
    $duration = $EndTime - $StartTime
    if ($duration.TotalHours -ge 1) {
        return "$([math]::Round($duration.TotalHours, 2)) hours"
    } elseif ($duration.TotalMinutes -ge 1) {
        return "$([math]::Round($duration.TotalMinutes, 2)) minutes"
    } else {
        return "$([math]::Round($duration.TotalSeconds, 2)) seconds"
    }
}

function Wait-AsrJob {
    param([object]$Job)

    if ($null -eq $Job) {
        throw "ASR Job was not created"
    }

    $jobStartTime = Get-Date
    Write-Log "  Job started: $($Job.Name) - State: $($Job.State)"

    $maxWaitMinutes = 60
    $startTime = Get-Date

    while ($Job.State -eq "InProgress" -or $Job.State -eq "NotStarted") {
        $elapsed = (Get-Date) - $startTime
        if ($elapsed.TotalMinutes -gt $maxWaitMinutes) {
            throw "ASR Job timeout after $maxWaitMinutes minutes"
        }

        Start-Sleep -Seconds 15
        try {
            $Job = Get-AzRecoveryServicesAsrJob -Job $Job
        } catch {
            Write-Log "  Warning: Failed to refresh job status: $_"
        }
        Write-Log "  Job status: $($Job.State) (Elapsed: $([math]::Round($elapsed.TotalMinutes, 1)) min)"
    }

    if ($Job.State -ne "Completed" -and $Job.State -ne "Succeeded") {
        $errorMsg = $Job.ErrorDescription
        if ([string]::IsNullOrEmpty($errorMsg)) {
            $errorMsg = "State: $($Job.State)"
        }
        throw "ASR Job failed: $errorMsg"
    }

    $jobEndTime = Get-Date
    $duration = $jobEndTime - $jobStartTime
    $durationText = Get-ElapsedTime -StartTime $jobStartTime -EndTime $jobEndTime

    Write-Log "  Job completed: $($Job.Name) (Duration: $durationText)"
    return @{
        Job = $Job
        StartTime = $jobStartTime
        EndTime = $jobEndTime
        Duration = $durationText
    }
}

Import-Module Az.RecoveryServices -ErrorAction Stop

Write-Log "[START] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Log "[CFG] Subscription: $($vmConfig.subscriptionId)"

Select-AzSubscription -SubscriptionId $vmConfig.subscriptionId -ErrorAction Stop

$vault = Get-AzRecoveryServicesVault -Name $vmConfig.vaultName -ResourceGroupName $vmConfig.resourceGroup -ErrorAction Stop

$vaultSettingsDir = Join-Path $env:TEMP "vault-settings-$(New-Guid)"
New-Item -ItemType Directory -Force -Path $vaultSettingsDir | Out-Null
$vaultSettingsFile = Get-AzRecoveryServicesVaultSettingsFile -Vault $vault -Path $vaultSettingsDir -ErrorAction Stop
Import-AzRecoveryServicesAsrVaultSettingsFile -Path $vaultSettingsFile.FilePath -ErrorAction Stop

$container = Get-AzRecoveryServicesAsrFabric -Name $vmConfig.fabricName |
    Get-AzRecoveryServicesAsrProtectionContainer -Name $vmConfig.containerName

$protectedItem = Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $container |
    Where-Object { $_.FriendlyName -eq $targetVm }

if (-not $protectedItem) {
    Write-Log "[ERROR] VM not found: $targetVm"
    exit 1
}

Write-Log "[VM] Processing: $targetVm"

switch ($step) {
    1 {
        if ($WhatIf) {
            Write-Log "[WHATIF] Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction PrimaryToRecovery -PerformSourceSideAction"
            Start-Sleep -Milliseconds 500
        } else {
            $job = Start-AzRecoveryServicesAsrUnplannedFailoverJob -ReplicationProtectedItem $protectedItem -Direction PrimaryToRecovery -PerformSourceSideAction
            Write-Log "[RUN] Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction PrimaryToRecovery"
            $jobResult = Wait-AsrJob -Job $job -ErrorAction Stop | Out-Null
            Write-Log "[DONE] Failover completed"
        }
    }
    2 {
        if ($WhatIf) {
            Write-Log "[WHATIF] Start-AzRecoveryServicesAsrCommitFailoverJob"
            Start-Sleep -Milliseconds 500
        } else {
            $job = Start-AzRecoveryServicesAsrCommitFailoverJob -ReplicationProtectedItem $protectedItem
            Write-Log "[RUN] Start-AzRecoveryServicesAsrCommitFailoverJob"
            $jobResult = Wait-AsrJob -Job $job -ErrorAction Stop | Out-Null
            Write-Log "[DONE] Commit completed"
        }
    }
    3 {
        if ($WhatIf) {
            Write-Log "[WHATIF] Update-AzRecoveryServicesAsrProtectionDirection -ReplicationProtectedItem -Direction RecoveryToPrimary"
            Start-Sleep -Milliseconds 500
        } else {
            Write-Log "[INFO] Getting protection container mapping..."
            $pcm = Get-AzRecoveryServicesAsrProtectionContainerMapping -ProtectionContainer $container | Where-Object { $_.Name -match $vmConfig.protectionContainerMapping } | Select-Object -First 1

            if (-not $pcm) {
                Write-Log "[WARNING] Protection container mapping not found. Using default parameters."
                Write-Log "[CMD] Start-AzRecoveryServicesAsrResynchronizeReplicationJob -ReplicationProtectedItem `$protectedItem"
                $job = Start-AzRecoveryServicesAsrResynchronizeReplicationJob `
                    -ReplicationProtectedItem $protectedItem
            } else {
                Write-Log "[INFO] Using protection container mapping: $($pcm.Name)"
                $logStorageId = $vmConfig.logStorageAccountId
                if ([string]::IsNullOrEmpty($logStorageId)) {
                    Write-Log "[CMD] Start-AzRecoveryServicesAsrResynchronizeReplicationJob -ReplicationProtectedItem `$protectedItem"
                    $job = Start-AzRecoveryServicesAsrResynchronizeReplicationJob `
                        -ReplicationProtectedItem $protectedItem
                } else {
                    Write-Log "[CMD] Start-AzRecoveryServicesAsrResynchronizeReplicationJob -ReplicationProtectedItem `$protectedItem"
                    $job = Start-AzRecoveryServicesAsrResynchronizeReplicationJob `
                        -ReplicationProtectedItem $protectedItem
                }
            }

            Write-Log "[RUN] Start-AzRecoveryServicesAsrResynchronizeReplicationJob"
            $jobResult = Wait-AsrJob -Job $job -ErrorAction Stop | Out-Null
            Write-Log "[DONE] Reprotect completed"
        }
    }
    4 {
        if ($WhatIf) {
            Write-Log "[WHATIF] Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction RecoveryToPrimary -PerformSourceSideAction"
            Start-Sleep -Milliseconds 500
        } else {
            $job = Start-AzRecoveryServicesAsrUnplannedFailoverJob -ReplicationProtectedItem $protectedItem -Direction RecoveryToPrimary -PerformSourceSideAction
            Write-Log "[RUN] Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction RecoveryToPrimary"
            $jobResult = Wait-AsrJob -Job $job -ErrorAction Stop | Out-Null
            Write-Log "[DONE] Failback completed"
        }
    }
    5 {
        if ($WhatIf) {
            Write-Log "[WHATIF] Start-AzRecoveryServicesAsrCommitFailoverJob"
            Start-Sleep -Milliseconds 500
        } else {
            $job = Start-AzRecoveryServicesAsrCommitFailoverJob -ReplicationProtectedItem $protectedItem
            Write-Log "[RUN] Start-AzRecoveryServicesAsrCommitFailoverJob"
            $jobResult = Wait-AsrJob -Job $job -ErrorAction Stop | Out-Null
            Write-Log "[DONE] Commit failback completed"
        }
    }
    6 {
        if ($WhatIf) {
            Write-Log "[WHATIF] Update-AzRecoveryServicesAsrProtectionDirection -ReplicationProtectedItem -Direction RecoveryToPrimary"
            Start-Sleep -Milliseconds 500
        } else {
            Write-Log "[INFO] Getting protection container mapping..."
            $pcm = Get-AzRecoveryServicesAsrProtectionContainerMapping -ProtectionContainer $container | Where-Object { $_.Name -match $vmConfig.protectionContainerMapping } | Select-Object -First 1

            if (-not $pcm) {
                Write-Log "[WARNING] Protection container mapping not found. Using default parameters."
                Write-Log "[CMD] Start-AzRecoveryServicesAsrResynchronizeReplicationJob -ReplicationProtectedItem `$protectedItem"
                $job = Start-AzRecoveryServicesAsrResynchronizeReplicationJob `
                    -ReplicationProtectedItem $protectedItem
            } else {
                Write-Log "[INFO] Using protection container mapping: $($pcm.Name)"
                $logStorageId = $vmConfig.logStorageAccountId
                if ([string]::IsNullOrEmpty($logStorageId)) {
                    Write-Log "[CMD] Start-AzRecoveryServicesAsrResynchronizeReplicationJob -ReplicationProtectedItem `$protectedItem"
                    $job = Start-AzRecoveryServicesAsrResynchronizeReplicationJob `
                        -ReplicationProtectedItem $protectedItem
                } else {
                    Write-Log "[CMD] Start-AzRecoveryServicesAsrResynchronizeReplicationJob -ReplicationProtectedItem `$protectedItem"
                    $job = Start-AzRecoveryServicesAsrResynchronizeReplicationJob `
                        -ReplicationProtectedItem $protectedItem
                }
            }

            Write-Log "[RUN] Start-AzRecoveryServicesAsrResynchronizeReplicationJob"
            $jobResult = Wait-AsrJob -Job $job -ErrorAction Stop | Out-Null
            Write-Log "[DONE] Reprotect restore completed"
        }
    }
}

if (-not $WhatIf) {
    $securePassword = ConvertTo-SecureString $emailConfig.password -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential($emailConfig.username, $securePassword)
    $toList = $emailConfig.to.Split(',')

    $startTimeFormatted = $operationStartTime.ToString('yyyy-MM-dd HH:mm:ss')
    $endTimeFormatted = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $totalDuration = Get-ElapsedTime -StartTime $operationStartTime -EndTime (Get-Date)

    $body = "Operation completed for $targetVm (step $step)`n`nStart Time: $startTimeFormatted`nEnd Time: $endTimeFormatted`nDuration: $totalDuration`n`nTimestamp: $(Get-Date)"

    Send-MailMessage -SmtpServer $emailConfig.smtpServer -Port $emailConfig.port -UseSsl -Credential $cred -From $emailConfig.username -To $toList -Subject "[DRILL] $targetVm step $step" -Body $body -Encoding UTF8
    Write-Log "[EMAIL] Notification sent"
} else {
    Write-Log "[WHATIF] Send-MailMessage -Subject '[DRILL] $targetVm step $step'"
}

Write-Log "[END] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
"@

        $tempScript = Join-Path $logDir "job-$targetVm.ps1"
        $scriptContent | Out-File -FilePath $tempScript -Encoding UTF8

        $job = Start-Job -ScriptBlock {
            param($ScriptPath)
            pwsh -File $ScriptPath
        } -ArgumentList $tempScript -Name $targetVm

        $jobs += @{
            Name = $targetVm
            Job = $job
            LogFile = $logFile
        }
    }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "[STARTING PARALLEL JOBS]" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Total VMs: $($vmList.Count)"
    Write-Host "Execution Mode: Parallel (All VMs run simultaneously)"
    Write-Host ""
    Write-Host "[MONITOR] Job Status (updates every 1 second)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $firstRun = $true
    $running = $true
    while ($running) {
        $running = $false
        $completed = 0
        $failed = 0

        if (-not $firstRun) {
            Write-Host ""
        }
        $firstRun = $false

        foreach ($item in $jobs) {
            $job = $item.Job
            $jobState = $job.State

            if ($jobState -eq "Running") {
                $running = $true
                $status = "RUNNING"
            } elseif ($jobState -eq "Completed") {
                $status = "DONE"
                $completed++
            } elseif ($jobState -eq "Failed") {
                $status = "FAILED"
                $failed++
            } else {
                $status = $jobState
                $running = $true
            }

            $statusColor = if ($status -eq "DONE") { "Green" } elseif ($status -eq "FAILED") { "Red" } elseif ($status -eq "RUNNING") { "Yellow" } else { "Gray" }
            Write-Host "  [$status] $($item.Name)" -ForegroundColor $statusColor
        }

        if ($running) {
            Start-Sleep -Seconds 1
        }
    }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "[RESULT] Parallel Execution Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Total VMs: $($jobs.Count)"
    Write-Host "Completed: $completed" -ForegroundColor Green
    Write-Host "Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
    Write-Host ""

    Write-Host "[LOG FILES]" -ForegroundColor Cyan
    foreach ($item in $jobs) {
        if (Test-Path $item.LogFile) {
            $content = Get-Content $item.LogFile
            if ($content -match "\[ERROR\]") {
                Write-Host "  $($item.Name): ERROR FOUND" -ForegroundColor Red
            } else {
                Write-Host "  $($item.Name): OK" -ForegroundColor Green
            }
        }
    }
    Write-Host ""

    if ($failed -eq 0) {
        Write-Host "[OK] All parallel jobs completed successfully!" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] Some jobs failed. Check log files for details." -ForegroundColor Red
    }

    exit 0
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

$securePassword = ConvertTo-SecureString $emailConfig.password -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential(
    $emailConfig.username,
    $securePassword
)

$operationStartTime = Get-Date

foreach ($targetVm in $vmList) {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "[VM] Processing: $targetVm" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $container = Get-AzRecoveryServicesAsrFabric -Name $vmConfig.fabricName |
        Get-AzRecoveryServicesAsrProtectionContainer -Name $vmConfig.containerName

    $protectedItem = Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $container |
        Where-Object { $_.FriendlyName -eq $targetVm }

    if (-not $protectedItem) {
        Write-Error "VM not found: $targetVm"
        continue
    }

    $vmStartTime = Get-Date

    switch ($step) {
        1 {
            if ($WhatIf) {
                Write-Host "[WHATIF] : Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction PrimaryToRecovery -PerformSourceSideAction" -ForegroundColor Yellow
            } else {
                $job = Start-AzRecoveryServicesAsrUnplannedFailoverJob -ReplicationProtectedItem $protectedItem `
                    -Direction PrimaryToRecovery `
                    -PerformSourceSideAction
                Write-Host "[RUN] : Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction PrimaryToRecovery" -ForegroundColor Cyan
                Wait-AsrJob -Job $job -ErrorAction Stop | Out-Null
                Write-Host "[DONE] : Failover completed" -ForegroundColor Green
            }
        }
        2 {
            if ($WhatIf) {
                Write-Host "[WHATIF] : Start-AzRecoveryServicesAsrCommitFailoverJob" -ForegroundColor Yellow
            } else {
                $job = Start-AzRecoveryServicesAsrCommitFailoverJob -ReplicationProtectedItem $protectedItem
                Write-Host "[RUN] : Start-AzRecoveryServicesAsrCommitFailoverJob" -ForegroundColor Cyan
                Wait-AsrJob -Job $job -ErrorAction Stop | Out-Null
                Write-Host "[DONE] : Commit completed" -ForegroundColor Green
            }
        }
        3 {
            if ($WhatIf) {
                Write-Host "[WHATIF] : Update-AzRecoveryServicesAsrProtectionDirection -AzureToAzure" -ForegroundColor Yellow
            } else {
                Write-Host "[INFO] : Getting protection container mapping..." -ForegroundColor Cyan
                $pcm = Get-AzRecoveryServicesAsrProtectionContainerMapping -ProtectionContainer $container | Where-Object { $_.Name -match $vmConfig.protectionContainerMapping } | Select-Object -First 1

                if (-not $pcm) {
                    Write-Warning "Protection container mapping not found. Using default parameters."
                    Write-Host "[CMD] : Start-AzRecoveryServicesAsrResynchronizeReplicationJob -ReplicationProtectedItem `$protectedItem" -ForegroundColor Magenta
                    $job = Start-AzRecoveryServicesAsrResynchronizeReplicationJob `
                        -ReplicationProtectedItem $protectedItem
                } else {
                    Write-Host "[INFO] : Using protection container mapping: $($pcm.Name)" -ForegroundColor Cyan
                    $logStorageId = $vmConfig.logStorageAccountId
                    if ([string]::IsNullOrEmpty($logStorageId)) {
                        Write-Host "[CMD] : Start-AzRecoveryServicesAsrResynchronizeReplicationJob -ReplicationProtectedItem `$protectedItem" -ForegroundColor Magenta
                        $job = Start-AzRecoveryServicesAsrResynchronizeReplicationJob `
                            -ReplicationProtectedItem $protectedItem
                    } else {
                        Write-Host "[CMD] : Start-AzRecoveryServicesAsrResynchronizeReplicationJob -ReplicationProtectedItem `$protectedItem" -ForegroundColor Magenta
                        $job = Start-AzRecoveryServicesAsrResynchronizeReplicationJob `
                            -ReplicationProtectedItem $protectedItem
                    }
                }

                Write-Host "[RUN] : Update-AzRecoveryServicesAsrProtectionDirection" -ForegroundColor Cyan
                Wait-AsrJob -Job $job -ErrorAction Stop | Out-Null
                Write-Host "[DONE] : Reprotect completed" -ForegroundColor Green
            }
        }
        4 {
            if ($WhatIf) {
                Write-Host "[WHATIF] : Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction RecoveryToPrimary -PerformSourceSideAction" -ForegroundColor Yellow
            } else {
                $job = Start-AzRecoveryServicesAsrUnplannedFailoverJob -ReplicationProtectedItem $protectedItem `
                    -Direction RecoveryToPrimary `
                    -PerformSourceSideAction
                Write-Host "[RUN] : Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction RecoveryToPrimary" -ForegroundColor Cyan
                Wait-AsrJob -Job $job -ErrorAction Stop | Out-Null
                Write-Host "[DONE] : Failback completed" -ForegroundColor Green
            }
        }
        5 {
            if ($WhatIf) {
                Write-Host "[WHATIF] : Start-AzRecoveryServicesAsrCommitFailoverJob" -ForegroundColor Yellow
            } else {
                $job = Start-AzRecoveryServicesAsrCommitFailoverJob -ReplicationProtectedItem $protectedItem
                Write-Host "[RUN] : Start-AzRecoveryServicesAsrCommitFailoverJob" -ForegroundColor Cyan
                Wait-AsrJob -Job $job -ErrorAction Stop | Out-Null
                Write-Host "[DONE] : Commit failback completed" -ForegroundColor Green
            }
        }
        6 {
            if ($WhatIf) {
                Write-Host "[WHATIF] : Update-AzRecoveryServicesAsrProtectionDirection -AzureToAzure" -ForegroundColor Yellow
            } else {
                Write-Host "[INFO] : Getting protection container mapping..." -ForegroundColor Cyan
                $pcm = Get-AzRecoveryServicesAsrProtectionContainerMapping -ProtectionContainer $container | Where-Object { $_.Name -match $vmConfig.protectionContainerMapping } | Select-Object -First 1

                if (-not $pcm) {
                    Write-Warning "Protection container mapping not found. Using default parameters."
                    Write-Host "[CMD] : Start-AzRecoveryServicesAsrResynchronizeReplicationJob -ReplicationProtectedItem `$protectedItem" -ForegroundColor Magenta
                    $job = Start-AzRecoveryServicesAsrResynchronizeReplicationJob `
                        -ReplicationProtectedItem $protectedItem
                } else {
                    Write-Host "[INFO] : Using protection container mapping: $($pcm.Name)" -ForegroundColor Cyan
                    $logStorageId = $vmConfig.logStorageAccountId
                    if ([string]::IsNullOrEmpty($logStorageId)) {
                        Write-Host "[CMD] : Start-AzRecoveryServicesAsrResynchronizeReplicationJob -ReplicationProtectedItem `$protectedItem" -ForegroundColor Magenta
                        $job = Start-AzRecoveryServicesAsrResynchronizeReplicationJob `
                            -ReplicationProtectedItem $protectedItem
                    } else {
                        Write-Host "[CMD] : Start-AzRecoveryServicesAsrResynchronizeReplicationJob -ReplicationProtectedItem `$protectedItem" -ForegroundColor Magenta
                        $job = Start-AzRecoveryServicesAsrResynchronizeReplicationJob `
                            -ReplicationProtectedItem $protectedItem
                    }
                }

                Write-Host "[RUN] : Start-AzRecoveryServicesAsrResynchronizeReplicationJob" -ForegroundColor Cyan
                Wait-AsrJob -Job $job -ErrorAction Stop | Out-Null
                Write-Host "[DONE] : Reprotect restore completed" -ForegroundColor Green
            }
        }
    }

    if (-not $WhatIf) {
        $vmEndTime = Get-Date
        $vmDuration = Get-ElapsedTime -StartTime $vmStartTime -EndTime $vmEndTime

        $toList = $emailConfig.to.Split(',')
        Send-MailMessage -SmtpServer $emailConfig.smtpServer `
            -Port $emailConfig.port -UseSsl -Credential $cred `
            -From $emailConfig.username `
            -To $toList `
            -Subject "[DRILL] $targetVm step $step" `
            -Body "Operation completed for $targetVm (step $step)`n`nStart Time: $($vmStartTime.ToString('yyyy-MM-dd HH:mm:ss'))`nEnd Time: $($vmEndTime.ToString('yyyy-MM-dd HH:mm:ss'))`nDuration: $vmDuration`n`nTimestamp: $(Get-Date)" `
            -Encoding UTF8
        Write-Host "[EMAIL] : Notification sent" -ForegroundColor Cyan
    } else {
        Write-Host "[WHATIF] : Send-MailMessage -Subject '[DRILL] $targetVm step $step'" -ForegroundColor Yellow
    }
}

