param(
    [string]$vmName,
    [string]$InputFile,
    [ValidateRange(1,6)][int]$step,
    [switch]$WhatIf,
    [switch]$Parallel,
    [int]$MaxRetries = 3,
    [int]$RetryDelay = 5,
    [int]$Timeout = 0
)

$ErrorActionPreference = "Stop"

$script:LogFile = $null
$script:LogErrors = @()

function Initialize-Log {
    param(
        [string]$BaseName = "drill"
    )

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $logDir = Join-Path $PWD "logs"
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    }

    $script:LogFile = Join-Path $logDir "${BaseName}-${timestamp}.log"
    New-Item -ItemType File -Path $script:LogFile -Force | Out-Null

    Write-Log -Module "Main" -Action "Initialize" -Command "Log file created: $($script:LogFile)" -Status "INFO"
}

function Write-Log {
    param(
        [string]$Module,
        [string]$Action,
        [string]$Command = "",
        [string]$Status = "SUCCESS",
        [string]$ErrorDetail = "",
        [string]$TargetVm = ""
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $vmInfo = if ($TargetVm) { "[$TargetVm] " } else { "" }
    $cmdInfo = if ($Command) { " | Command: $Command" } else { "" }
    $errorInfo = if ($ErrorDetail) { " | Error: $ErrorDetail" } else { "" }

    $logLine = "$timestamp | $vmInfo$Module | $Action$cmdInfo | $Status$errorInfo"

    $logLine | Out-File -FilePath $script:LogFile -Encoding UTF8 -Append

    $hostInfo = if ($Status -eq "FAILED") { "Red" } elseif ($Status -eq "SUCCESS") { "Green" } elseif ($Status -eq "RETRY") { "Yellow" } else { "Cyan" }
    Write-Host $logLine -ForegroundColor $hostInfo

    if ($Status -eq "FAILED") {
        $script:LogErrors += @{
            Timestamp = $timestamp
            Module = $Module
            Action = $Action
            TargetVm = $TargetVm
            Error = $ErrorDetail
        }
    }
}

function Get-LogSummary {
    $errors = $script:LogErrors
    $totalLines = (Get-Content $script:LogFile).Count

    $summary = @"
========================================
LOG SUMMARY
========================================
Log File: $($script:LogFile)
Total Entries: $totalLines
Errors: $($errors.Count)

ERROR DETAILS:
"@

    if ($errors.Count -gt 0) {
        foreach ($e in $errors) {
            $summary += "`n[$($e.Timestamp)] $($e.Module) - $($e.Action) - $($e.TargetVm)"
            $summary += "`n  Error: $($e.Error)`n"
        }
    } else {
        $summary += "No errors recorded."
    }

    return $summary
}

function Write-ProgressBar {
    param(
        [int]$PercentComplete,
        [string]$Status,
        [string]$CurrentOperation,
        [int]$SecondsRemaining
    )

    $activity = "ASR Drill Progress"
    if ($SecondsRemaining -gt 0) {
        $eta = "ETA: $([math]::Floor($SecondsRemaining / 60))m $($SecondsRemaining % 60)s"
    } else {
        $eta = ""
    }

    Write-Progress -Activity $activity -Status $Status -PercentComplete $PercentComplete -CurrentOperation $CurrentOperation -SecondsRemaining $SecondsRemaining
}

function Invoke-WithRetry {
    param(
        [scriptblock]$ScriptBlock,
        [int]$MaxRetries = 3,
        [int]$RetryDelay = 5,
        [string]$OperationName = "Operation",
        [string]$Module = "Main",
        [string]$TargetVm = ""
    )

    $attempt = 1
    $lastError = $null

    while ($attempt -le $MaxRetries) {
        try {
            $result = & $ScriptBlock
            return $result
        }
        catch {
            $lastError = $_
            Write-Log -Module $Module -Action $OperationName -Status "RETRY" -ErrorDetail "Attempt $attempt/$MaxRetries failed: $($_.Exception.Message)" -TargetVm $TargetVm

            if ($attempt -lt $MaxRetries) {
                Start-Sleep -Seconds $RetryDelay
            }
            $attempt++
        }
    }

    throw $lastError
}

function Format-ErrorDetail {
    param([System.Exception]$Exception)

    $errorInfo = @"
Type: $($Exception.GetType().FullName)
Message: $($Exception.Message)
Stack: $($Exception.StackTrace)
"@
    return $errorInfo
}

function Read-Ini {
    param([string]$FilePath)

    $content = Get-Content $FilePath -Raw
    Write-Log -Module "Config" -Action "ReadIni" -Command "File: $FilePath" -Status "INFO"

    $data = ($content -replace ' ', '' -join "`n") | ConvertFrom-StringData
    return $data
}

$vmConfig = Read-Ini -FilePath "vm-config.ini"
$emailConfig = Read-Ini -FilePath "email-config.ini"

Initialize-Log -BaseName "drill-step$step"

Write-Log -Module "Main" -Action "StartDrill" -Command "step=$step, parallel=$Parallel, whatif=$WhatIf, vms=$($vmList.Count)" -Status "INFO"
Write-Log -Module "Config" -Action "LoadConfig" -Command "subscription=$($vmConfig.subscriptionId), vault=$($vmConfig.vaultName)" -Status "INFO"

$vmList = @()
if ($InputFile) {
    if (-not (Test-Path $InputFile)) {
        Write-Log -Module "Main" -Action "LoadInputFile" -Status "FAILED" -ErrorDetail "Input file not found: $InputFile"
        exit 1
    }
    $vmList = Get-Content $InputFile | Where-Object { $_ -match '\S' }
    if (-not $vmList) {
        Write-Log -Module "Main" -Action "LoadInputFile" -Status "FAILED" -ErrorDetail "No VM names found in input file"
        exit 1
    }
    Write-Log -Module "Main" -Action "LoadInputFile" -Command "file=$InputFile, count=$($vmList.Count)" -Status "SUCCESS"
} elseif (-not $vmName) {
    Write-Log -Module "Main" -Action "ValidateInput" -Status "FAILED" -ErrorDetail "No VM name or input file specified"
    exit 1
} else {
    $vmList = @($vmName)
    Write-Log -Module "Main" -Action "LoadInputFile" -Command "vm=$vmName" -Status "SUCCESS"
}

if ($Parallel -and $vmList.Count -gt 1) {
    Write-Log -Module "Parallel" -Action "StartParallel" -Command "count=$($vmList.Count)" -Status "INFO"

    $jobs = @()
    $tempLogDir = Join-Path $env:TEMP "drill-logs-$([guid]::NewGuid().ToString('N')[0..7])"
    New-Item -ItemType Directory -Force -Path $tempLogDir | Out-Null

    $startTime = Get-Date
    $totalVms = $vmList.Count

    $stepCmd = @("",
        "Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction PrimaryToRecovery",
        "Start-AzRecoveryServicesAsrCommitFailoverJob",
        "Start-AzRecoveryServicesAsrReprotectJob",
        "Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction RecoveryToPrimary",
        "Start-AzRecoveryServicesAsrCommitFailoverJob",
        "Start-AzRecoveryServicesAsrReprotectJob")[$step]

    foreach ($targetVm in $vmList) {
        $tempLogFile = Join-Path $tempLogDir "$targetVm.log"

        $scriptContent = @"
ErrorActionPreference = "Stop"

`$vmConfig = @{subscriptionId="$($vmConfig.subscriptionId)";vaultName="$($vmConfig.vaultName)";resourceGroup="$($vmConfig.resourceGroup)";fabricName="$($vmConfig.fabricName)";containerName="$($vmConfig.containerName)"}
`$emailConfig = @{smtpServer="$($emailConfig.smtpServer)";port="$($emailConfig.port)";username="$($emailConfig.username)";password="$($emailConfig.password)";to="$($emailConfig.to)"}

`$targetVm = "$targetVm"
`$step = $step
`$WhatIf = `$$WhatIf
`$tempLogFile = "$tempLogFile"
`$MaxRetries = $MaxRetries
`$RetryDelay = $RetryDelay

New-Item -ItemType File -Path `$tempLogFile -Force | Out-Null

`$logLine = { param([string]`$Line)
    `$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    "`$timestamp | [`$targetVm] `$Line" | Out-File -FilePath `$tempLogFile -Encoding UTF8 -Append
    [Console]::WriteLine("[$targetVm] `$Line")
    [Console]::Out.Flush()
}

`$retryCmd = { param([scriptblock]`$Sb, [int]`$Retries, [int]`$Delay, [string]`$OpName)
    `$attempts = 1
    while (`$attempts -le `$Retries) {
        try {
            & `$Sb
            return
        }
        catch {
            & `$logLine -Line "RETRY | `$OpName failed (attempt `$attempts/`$Retries): `$(`$_.Exception.Message)"
            if (`$attempts -lt `$Retries) {
                Start-Sleep -Seconds `$Delay
            }
            `$attempts++
        }
    }
    throw
}

& `$logLine -Line "INFO | Main | StartJob | step=`$step"

try {
    Import-Module Az.RecoveryServices -ErrorAction Stop
    & `$logLine -Line "SUCCESS | Azure | ImportModule | Az.RecoveryServices"

    Select-AzSubscription -SubscriptionId `$vmConfig.subscriptionId -ErrorAction Stop
    & `$logLine -Line "SUCCESS | Azure | SelectSubscription | subscriptionId=`$($vmConfig.subscriptionId)"

    `$vault = Get-AzRecoveryServicesVault -Name `$vmConfig.vaultName -ResourceGroupName `$vmConfig.resourceGroup -ErrorAction Stop
    & `$logLine -Line "SUCCESS | Azure | ConnectVault | vault=`$($vmConfig.vaultName)"

    `$vaultSettingsDir = Join-Path `$env:TEMP "vault-settings-$(New-Guid)"
    New-Item -ItemType Directory -Force -Path `$vaultSettingsDir | Out-Null
    `$vaultSettingsFile = Get-AzRecoveryServicesVaultSettingsFile -Vault `$vault -Path `$vaultSettingsDir -ErrorAction Stop
    Import-AzRecoveryServicesAsrVaultSettingsFile -Path `$vaultSettingsFile.FilePath -ErrorAction Stop
    & `$logLine -Line "SUCCESS | Azure | ImportVaultSettings"

    `$container = Get-AzRecoveryServicesAsrFabric -Name `$vmConfig.fabricName |
        Get-AzRecoveryServicesAsrProtectionContainer -Name `$vmConfig.containerName

    `$protectedItem = Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer `$container |
        Where-Object { `$_.FriendlyName -eq `$targetVm }

    if (-not `$protectedItem) {
        throw "VM not found: `$targetVm"
    }
    & `$logLine -Line "SUCCESS | ASR | FindProtectedItem | vm=`$targetVm"

    switch (`$step) {
        1 {
            if (`$WhatIf) {
                & `$logLine -Line "INFO | ASR | Failover | Command: Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction PrimaryToRecovery -PerformSourceSideActions -ShutDownSourceServer"
            } else {
                & `$retryCmd -Sb {
                    Start-AzRecoveryServicesAsrUnplannedFailoverJob -ProtectionObject `$protectedItem -Direction PrimaryToRecovery -PerformSourceSideActions -ShutDownSourceServer
                } -Retries `$MaxRetries -Delay `$RetryDelay -OpName "Failover"
                & `$logLine -Line "RUNNING | ASR | StartFailoverJob | Command: Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction PrimaryToRecovery"
                `$job = Start-AzRecoveryServicesAsrUnplannedFailoverJob -ProtectionObject `$protectedItem -Direction PrimaryToRecovery -PerformSourceSideActions -ShutDownSourceServer
                `$job | Wait-AzRecoveryServicesAsrJob -ErrorAction Stop | Out-Null
                & `$logLine -Line "SUCCESS | ASR | FailoverCompleted"
            }
        }
        2 {
            if (`$WhatIf) {
                & `$logLine -Line "INFO | ASR | CommitFailover | Command: Start-AzRecoveryServicesAsrCommitFailoverJob"
            } else {
                & `$retryCmd -Sb {
                    Start-AzRecoveryServicesAsrCommitFailoverJob -ProtectionObject `$protectedItem
                } -Retries `$MaxRetries -Delay `$RetryDelay -OpName "CommitFailover"
                & `$logLine -Line "RUNNING | ASR | StartCommitFailoverJob"
                `$job = Start-AzRecoveryServicesAsrCommitFailoverJob -ProtectionObject `$protectedItem
                `$job | Wait-AzRecoveryServicesAsrJob -ErrorAction Stop | Out-Null
                & `$logLine -Line "SUCCESS | ASR | CommitCompleted"
            }
        }
        3 {
            if (`$WhatIf) {
                & `$logLine -Line "INFO | ASR | Reprotect | Command: Start-AzRecoveryServicesAsrReprotectJob"
            } else {
                & `$retryCmd -Sb {
                    Start-AzRecoveryServicesAsrReprotectJob -ProtectionObject `$protectedItem
                } -Retries `$MaxRetries -Delay `$RetryDelay -OpName "Reprotect"
                & `$logLine -Line "RUNNING | ASR | StartReprotectJob"
                `$job = Start-AzRecoveryServicesAsrReprotectJob -ProtectionObject `$protectedItem
                `$job | Wait-AzRecoveryServicesAsrJob -ErrorAction Stop | Out-Null
                & `$logLine -Line "SUCCESS | ASR | ReprotectCompleted"
            }
        }
        4 {
            if (`$WhatIf) {
                & `$logLine -Line "INFO | ASR | Failback | Command: Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction RecoveryToPrimary"
            } else {
                & `$retryCmd -Sb {
                    Start-AzRecoveryServicesAsrUnplannedFailoverJob -ProtectionObject `$protectedItem -Direction RecoveryToPrimary -PerformSourceSideActions -ShutDownSourceServer
                } -Retries `$MaxRetries -Delay `$RetryDelay -OpName "Failback"
                & `$logLine -Line "RUNNING | ASR | StartFailbackJob"
                `$job = Start-AzRecoveryServicesAsrUnplannedFailoverJob -ProtectionObject `$protectedItem -Direction RecoveryToPrimary -PerformSourceSideActions -ShutDownSourceServer
                `$job | Wait-AzRecoveryServicesAsrJob -ErrorAction Stop | Out-Null
                & `$logLine -Line "SUCCESS | ASR | FailbackCompleted"
            }
        }
        5 {
            if (`$WhatIf) {
                & `$logLine -Line "INFO | ASR | CommitFailback | Command: Start-AzRecoveryServicesAsrCommitFailoverJob"
            } else {
                & `$retryCmd -Sb {
                    Start-AzRecoveryServicesAsrCommitFailoverJob -ProtectionObject `$protectedItem
                } -Retries `$MaxRetries -Delay `$RetryDelay -OpName "CommitFailback"
                & `$logLine -Line "RUNNING | ASR | StartCommitFailbackJob"
                `$job = Start-AzRecoveryServicesAsrCommitFailoverJob -ProtectionObject `$protectedItem
                `$job | Wait-AzRecoveryServicesAsrJob -ErrorAction Stop | Out-Null
                & `$logLine -Line "SUCCESS | ASR | CommitFailbackCompleted"
            }
        }
        6 {
            if (`$WhatIf) {
                & `$logLine -Line "INFO | ASR | RestoreReprotect | Command: Start-AzRecoveryServicesAsrReprotectJob"
            } else {
                & `$retryCmd -Sb {
                    Start-AzRecoveryServicesAsrReprotectJob -ProtectionObject `$protectedItem
                } -Retries `$MaxRetries -Delay `$RetryDelay -OpName "RestoreReprotect"
                & `$logLine -Line "RUNNING | ASR | StartRestoreReprotectJob"
                `$job = Start-AzRecoveryServicesAsrReprotectJob -ProtectionObject `$protectedItem
                `$job | Wait-AzRecoveryServicesAsrJob -ErrorAction Stop | Out-Null
                & `$logLine -Line "SUCCESS | ASR | RestoreCompleted"
            }
        }
    }

    if (-not `$WhatIf) {
        `$securePassword = ConvertTo-SecureString `$emailConfig.password -AsPlainText -Force
        `$cred = New-Object System.Management.Automation.PSCredential(`$emailConfig.username, `$securePassword)
        `$toList = `$emailConfig.to.Split(',')

        `$body = "Operation completed for `$targetVm (step `$step)`nTimestamp: `$(Get-Date)"

        Send-MailMessage -SmtpServer `$emailConfig.smtpServer -Port `$emailConfig.port -UseSsl -Credential `$cred -From `$emailConfig.username -To `$toList -Subject "[DRILL] `$targetVm step `$step" -Body `$body -Encoding UTF8
        & `$logLine -Line "SUCCESS | Email | NotificationSent"
    } else {
        & `$logLine -Line "INFO | Email | WhatIfMode"
    }

    & `$logLine -Line "SUCCESS | Main | JobCompleted"
}
catch {
    & `$logLine -Line "FAILED | Main | JobFailed | Error: `$(`$_.Exception.Message)"
    exit 1
}
"@

        $tempScript = Join-Path $tempLogDir "job-$targetVm.ps1"
        $scriptContent | Out-File -FilePath $tempScript -Encoding UTF8

        $job = Start-Job -ScriptBlock {
            param($ScriptPath)
            pwsh -File $ScriptPath
        } -ArgumentList $tempScript -Name $targetVm

        $jobs += @{
            Name = $targetVm
            Job = $job
            LogFile = $tempLogFile
            StartTime = $startTime
        }

        Write-Host "[PARALLEL] $targetVm : $stepCmd" -ForegroundColor Cyan
        Write-Log -Module "Parallel" -Action "StartJob" -Command $stepCmd -TargetVm $targetVm -Status "INFO"
    }

    Write-Host ""
    Write-Log -Module "Parallel" -Action "MonitorJobs" -Command "total=$totalVms" -Status "INFO"

    $firstRun = $true
    $running = $true
    $completed = 0
    $failed = 0

    while ($running) {
        $running = $false
        $completed = 0
        $failed = 0
        $currentRunning = @()

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
                $currentRunning += $item.Name
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

        $elapsed = (Get-Date) - $startTime
        $completedCount = $completed + $failed
        if ($completedCount -gt 0 -and $running) {
            $avgTimePerVm = $elapsed.TotalSeconds / $completedCount
            $remainingVms = $totalVms - $completedCount
            $etaSeconds = [math]::Floor($avgTimePerVm * $remainingVms)
        } else {
            $etaSeconds = 0
        }

        $percentComplete = [math]::Floor(($completedCount / $totalVms) * 100)
        $operation = if ($currentRunning.Count -gt 0) { "Running: $($currentRunning -join ', ')" } else { "Waiting..." }

        Write-ProgressBar -PercentComplete $percentComplete -Status "$percentComplete% Complete" -CurrentOperation $operation -SecondsRemaining $etaSeconds

        if ($running) {
            Start-Sleep -Seconds 1
        }
    }

    Write-Progress -Activity "ASR Drill Progress" -Completed -Status "Done"

    $elapsed = (Get-Date) - $startTime
    $elapsedStr = "{0:D2}m {1:D2}s" -f [math]::Floor($elapsed.TotalMinutes), $elapsed.Seconds

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "[RESULT] Parallel Execution Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    Write-Log -Module "Parallel" -Action "Summary" -Command "total=$totalVms, completed=$completed, failed=$failed, duration=$elapsedStr" -Status $(if ($failed -eq 0) { "SUCCESS" } else { "FAILED" })

    Write-Host "Total VMs: $totalVms"
    Write-Host "Completed: $completed" -ForegroundColor Green
    Write-Host "Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
    Write-Host "Duration: $elapsedStr" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "[MERGING LOGS]" -ForegroundColor Cyan
    Write-Log -Module "Parallel" -Action "MergeLogs" -Status "INFO"

    $errorCount = 0
    foreach ($item in $jobs) {
        if (Test-Path $item.LogFile) {
            $content = Get-Content $item.LogFile -ErrorAction SilentlyContinue
            $normalizedLines = $content | ForEach-Object {
                $_ -replace '^\[(.+?)\] ', '$1 | '
            }
            $normalizedLines | Out-File -FilePath $script:LogFile -Encoding UTF8 -Append

            if ($content -match "FAILED") {
                Write-Host "  $($item.Name): ERRORS FOUND" -ForegroundColor Red
                $errorCount++
            } else {
                Write-Host "  $($item.Name): OK" -ForegroundColor Green
            }
        }
    }
    Write-Host ""

    Write-Host "[LOG FILE]" -ForegroundColor Cyan
    Write-Host "  $($script:LogFile)" -ForegroundColor White
    Write-Host ""

    if ($failed -eq 0 -and $errorCount -eq 0) {
        Write-Host "[OK] All $totalVms parallel jobs completed successfully!" -ForegroundColor Green
        Write-Log -Module "Parallel" -Action "AllCompleted" -Command "count=$totalVms" -Status "SUCCESS"
    } else {
        Write-Host "[FAIL] $failed jobs failed, $errorCount with errors. Check log file for details." -ForegroundColor Red
        Write-Log -Module "Parallel" -Action "SomeFailed" -Command "failed=$failed, errors=$errorCount" -Status "FAILED"
    }

    Get-LogSummary | Out-File -FilePath "$($script:LogFile).summary.txt" -Encoding UTF8

    exit 0
}

function Invoke-WithRetry {
    param(
        `$ScriptBlock,
        [int]`$MaxRetries = 3,
        [int]`$RetryDelay = 5,
        [string]`$OperationName = "Operation"
    )

    `$attempt = 1
    `$lastError = `$null

    while (`$attempt -le `$MaxRetries) {
        try {
            `$result = & `$ScriptBlock
            return `$result
        }
        catch {
            `$lastError = `$_
            Write-Log "[ERROR] `$OperationName failed (attempt `$attempt/`$MaxRetries): `$(`$_.Exception.Message)"
            if (`$attempt -lt `$MaxRetries) {
                Start-Sleep -Seconds `$RetryDelay
            }
            `$attempt++
        }
    }
    throw " $OperationName failed after `$MaxRetries attempts"
}

Write-Log "[START] Step `$step for `$targetVm"

try {
    Import-Module Az.RecoveryServices -ErrorAction Stop
    Write-Log "[OK] Az.RecoveryServices module loaded"

    Select-AzSubscription -SubscriptionId `$vmConfig.subscriptionId -ErrorAction Stop
    Write-Log "[OK] Subscriptionselected: `$($vmConfig.subscriptionId)"

    `$vault = Get-AzRecoveryServicesVault -Name `$vmConfig.vaultName -ResourceGroupName `$vmConfig.resourceGroup -ErrorAction Stop
    Write-Log "[OK] Vault connected: $($vmConfig.vaultName)"

    `$vaultSettingsDir = Join-Path `$env:TEMP "vault-settings-$(New-Guid)"
    New-Item -ItemType Directory -Force -Path `$vaultSettingsDir | Out-Null
    `$vaultSettingsFile = Get-AzRecoveryServicesVaultSettingsFile -Vault `$vault -Path `$vaultSettingsDir -ErrorAction Stop
    Import-AzRecoveryServicesAsrVaultSettingsFile -Path `$vaultSettingsFile.FilePath -ErrorAction Stop
    Write-Log "[OK] Vault settings imported"

    `$container = Get-AzRecoveryServicesAsrFabric -Name `$vmConfig.fabricName |
        Get-AzRecoveryServicesAsrProtectionContainer -Name `$vmConfig.containerName

    `$protectedItem = Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer `$container |
        Where-Object { `$_.FriendlyName -eq `$targetVm }

    if (-not `$protectedItem) {
        throw "VM not found in protection container: $targetVm"
    }
    Write-Log "[OK] Protected item found: $targetVm"

    switch (`$step) {
        1 {
            if (`$WhatIf) {
                Write-Log "[WHATIF] Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction PrimaryToRecovery"
            } else {
                `$job = Invoke-WithRetry -ScriptBlock {
                    Start-AzRecoveryServicesAsrUnplannedFailoverJob -ProtectionObject `$protectedItem -Direction PrimaryToRecovery -PerformSourceSideActions -ShutDownSourceServer
                } -OperationName "Failover job" -MaxRetries $MaxRetries -RetryDelay $RetryDelay
                Write-Log "[RUN] Failover job started"
                `$job | Wait-AzRecoveryServicesAsrJob -ErrorAction Stop | Out-Null
                Write-Log "[DONE] Failover completed successfully"
            }
        }
        2 {
            if (`$WhatIf) {
                Write-Log "[WHATIF] Start-AzRecoveryServicesAsrCommitFailoverJob"
            } else {
                `$job = Invoke-WithRetry -ScriptBlock {
                    Start-AzRecoveryServicesAsrCommitFailoverJob -ProtectionObject `$protectedItem
                } -OperationName "Commit failover job" -MaxRetries $MaxRetries -RetryDelay $RetryDelay
                Write-Log "[RUN] Commit job started"
                `$job | Wait-AzRecoveryServicesAsrJob -ErrorAction Stop | Out-Null
                Write-Log "[DONE] Commit completed successfully"
            }
        }
        3 {
            if (`$WhatIf) {
                Write-Log "[WHATIF] Start-AzRecoveryServicesAsrReprotectJob"
            } else {
                `$job = Invoke-WithRetry -ScriptBlock {
                    Start-AzRecoveryServicesAsrReprotectJob -ProtectionObject `$protectedItem
                } -OperationName "Reprotect job" -MaxRetries $MaxRetries -RetryDelay $RetryDelay
                Write-Log "[RUN] Reprotect job started"
                `$job | Wait-AzRecoveryServicesAsrJob -ErrorAction Stop | Out-Null
                Write-Log "[DONE] Reprotect completed successfully"
            }
        }
        4 {
            if (`$WhatIf) {
                Write-Log "[WHATIF] Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction RecoveryToPrimary"
            } else {
                `$job = Invoke-WithRetry -ScriptBlock {
                    Start-AzRecoveryServicesAsrUnplannedFailoverJob -ProtectionObject `$protectedItem -Direction RecoveryToPrimary -PerformSourceSideActions -ShutDownSourceServer
                } -OperationName "Failback job" -MaxRetries $MaxRetries -RetryDelay $RetryDelay
                Write-Log "[RUN] Failback job started"
                `$job | Wait-AzRecoveryServicesAsrJob -ErrorAction Stop | Out-Null
                Write-Log "[DONE] Failback completed successfully"
            }
        }
        5 {
            if (`$WhatIf) {
                Write-Log "[WHATIF] Start-AzRecoveryServicesAsrCommitFailoverJob"
            } else {
                `$job = Invoke-WithRetry -ScriptBlock {
                    Start-AzRecoveryServicesAsrCommitFailoverJob -ProtectionObject `$protectedItem
                } -OperationName "Commit failback job" -MaxRetries $MaxRetries -RetryDelay $RetryDelay
                Write-Log "[RUN] Commit failback job started"
                `$job | Wait-AzRecoveryServicesAsrJob -ErrorAction Stop | Out-Null
                Write-Log "[DONE] Commit failback completed successfully"
            }
        }
        6 {
            if (`$WhatIf) {
                Write-Log "[WHATIF] Start-AzRecoveryServicesAsrReprotectJob"
            } else {
                `$job = Invoke-WithRetry -ScriptBlock {
                    Start-AzRecoveryServicesAsrReprotectJob -ProtectionObject `$protectedItem
                } -OperationName "Restore reprotect job" -MaxRetries $MaxRetries -RetryDelay $RetryDelay
                Write-Log "[RUN] Restore reprotect job started"
                `$job | Wait-AzRecoveryServicesAsrJob -ErrorAction Stop | Out-Null
                Write-Log "[DONE] Restore completed successfully"
            }
        }
    }

    if (-not `$WhatIf) {
        `$securePassword = ConvertTo-SecureString `$emailConfig.password -AsPlainText -Force
        `$cred = New-Object System.Management.Automation.PSCredential(`$emailConfig.username, `$securePassword)
        `$toList = `$emailConfig.to.Split(',')

        `$body = "Operation completed for `$targetVm (step `$step)`nTimestamp: $(Get-Date)"

        Send-MailMessage -SmtpServer `$emailConfig.smtpServer -Port `$emailConfig.port -UseSsl -Credential `$cred -From `$emailConfig.username -To `$toList -Subject "[DRILL] `$targetVm step `$step" -Body `$body -Encoding UTF8
        Write-Log "[EMAIL] Notification sent"
    } else {
        Write-Log "[WHATIF] Send-MailMessage skipped"
    }

    Write-Log "[END] Completed successfully"
}
catch {
    Write-Log "[ERROR] $($_ | Out-String)"
    Write-Log "[END] Failed with error"
    exit 1
}
"@

        $tempScript = Join-Path $logDir "job-$targetVm.ps1"
        $scriptContent | Out-File -FilePath $tempScript -Encoding UTF8

        $stepCmd = @("",
            "Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction PrimaryToRecovery",
            "Start-AzRecoveryServicesAsrCommitFailoverJob",
            "Start-AzRecoveryServicesAsrReprotectJob",
            "Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction RecoveryToPrimary",
            "Start-AzRecoveryServicesAsrCommitFailoverJob",
            "Start-AzRecoveryServicesAsrReprotectJob")[$step]

        $job = Start-Job -ScriptBlock {
            param($ScriptPath)
            pwsh -File $ScriptPath
        } -ArgumentList $tempScript -Name $targetVm

        $jobs += @{
            Name = $targetVm
            Job = $job
            LogFile = $logFile
            StartTime = $startTime
        }

        Write-Host "[PARALLEL] $targetVm : $stepCmd" -ForegroundColor Cyan
    }

    Write-Host ""
    Write-Host "[MONITOR] All $totalVms jobs started. Waiting for completion..." -ForegroundColor Cyan
    Write-Host ""

    $firstRun = $true
    $running = $true
    $completed = 0
    $failed = 0

    while ($running) {
        $running = $false
        $completed = 0
        $failed = 0
        $currentRunning = @()

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
                $currentRunning += $item.Name
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

        $elapsed = (Get-Date) - $startTime
        $completedCount = $completed + $failed
        if ($completedCount -gt 0 -and $running) {
            $avgTimePerVm = $elapsed.TotalSeconds / $completedCount
            $remainingVms = $totalVms - $completedCount
            $etaSeconds = [math]::Floor($avgTimePerVm * $remainingVms)
        } else {
            $etaSeconds = 0
        }

        $percentComplete = [math]::Floor(($completedCount / $totalVms) * 100)
        $operation = if ($currentRunning.Count -gt 0) { "Running: $($currentRunning -join ', ')" } else { "Waiting..." }

        Write-ProgressBar -PercentComplete $percentComplete -Status "$percentComplete% Complete" -CurrentOperation $operation -SecondsRemaining $etaSeconds

        if ($running) {
            Start-Sleep -Seconds 1
        }
    }

    Write-Progress -Activity "ASR Drill Progress" -Completed -Status "Done"

    $elapsed = (Get-Date) - $startTime
    $elapsedStr = "{0:D2}m {1:D2}s" -f [math]::Floor($elapsed.TotalMinutes), $elapsed.Seconds

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "[RESULT] Parallel Execution Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Total VMs: $totalVms"
    Write-Host "Completed: $completed" -ForegroundColor Green
    Write-Host "Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
    Write-Host "Duration: $elapsedStr" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "[LOG FILES]" -ForegroundColor Cyan
    $errorCount = 0
    foreach ($item in $jobs) {
        if (Test-Path $item.LogFile) {
            $content = Get-Content $item.LogFile -ErrorAction SilentlyContinue
            if ($content -match "\[ERROR\]") {
                Write-Host "  $($item.Name): ERRORS FOUND" -ForegroundColor Red
                $errorCount++
            } else {
                Write-Host "  $($item.Name): OK" -ForegroundColor Green
            }
        }
    }
    Write-Host ""

    if ($failed -eq 0 -and $errorCount -eq 0) {
        Write-Host "[OK] All $totalVms parallel jobs completed successfully!" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $failed jobs failed, $errorCount with errors. Check log files for details." -ForegroundColor Red
    }

    exit 0
}

try {
    Import-Module Az.RecoveryServices -ErrorAction Stop
    Write-Log -Module "Azure" -Action "ImportModule" -Command "Az.RecoveryServices" -Status "SUCCESS"

    Select-AzSubscription -SubscriptionId $vmConfig.subscriptionId -ErrorAction Stop
    Write-Log -Module "Azure" -Action "SelectSubscription" -Command "subscriptionId=$($vmConfig.subscriptionId)" -Status "SUCCESS"

    $vault = Get-AzRecoveryServicesVault -Name $vmConfig.vaultName -ResourceGroupName $vmConfig.resourceGroup -ErrorAction Stop
    Write-Log -Module "Azure" -Action "ConnectVault" -Command "vault=$($vmConfig.vaultName)" -Status "SUCCESS"

    $vaultSettingsDir = Join-Path $env:TEMP "vault-settings-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Force -Path $vaultSettingsDir | Out-Null
    $vaultSettingsFile = Get-AzRecoveryServicesVaultSettingsFile -Vault $vault -Path $vaultSettingsDir -ErrorAction Stop
    Import-AzRecoveryServicesAsrVaultSettingsFile -Path $vaultSettingsFile.FilePath -ErrorAction Stop
    Write-Log -Module "Azure" -Action "ImportVaultSettings" -Status "SUCCESS"

    $securePassword = ConvertTo-SecureString $emailConfig.password -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential(
        $emailConfig.username,
        $securePassword
    )

    foreach ($targetVm in $vmList) {
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "[VM] Processing: $targetVm" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan

        Write-Log -Module "Main" -Action "ProcessVm" -Command "vm=$targetVm" -Status "INFO" -TargetVm $targetVm

        $container = Get-AzRecoveryServicesAsrFabric -Name $vmConfig.fabricName |
            Get-AzRecoveryServicesAsrProtectionContainer -Name $vmConfig.containerName

        $protectedItem = Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $container |
            Where-Object { $_.FriendlyName -eq $targetVm }

        if (-not $protectedItem) {
            $errorMsg = "VM not found in protection container: $targetVm"
            Write-Log -Module "ASR" -Action "FindProtectedItem" -Status "FAILED" -ErrorDetail $errorMsg -TargetVm $targetVm
            throw $errorMsg
        }
        Write-Log -Module "ASR" -Action "FindProtectedItem" -Command "vm=$targetVm" -Status "SUCCESS" -TargetVm $targetVm

        switch ($step) {
            1 {
                $cmd = "Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction PrimaryToRecovery -PerformSourceSideActions -ShutDownSourceServer"
                if ($WhatIf) {
                    Write-Log -Module "ASR" -Action "Failover" -Command $cmd -Status "WHATIF" -TargetVm $targetVm
                } else {
                    Write-Log -Module "ASR" -Action "StartFailoverJob" -Command $cmd -Status "RUNNING" -TargetVm $targetVm
                    $job = Invoke-WithRetry -ScriptBlock {
                        Start-AzRecoveryServicesAsrUnplannedFailoverJob -ProtectionObject $protectedItem -Direction PrimaryToRecovery -PerformSourceSideActions -ShutDownSourceServer
                    } -OperationName "Failover" -Module "ASR" -MaxRetries $MaxRetries -RetryDelay $RetryDelay -TargetVm $targetVm
                    $job | Wait-AzRecoveryServicesAsrJob -ErrorAction Stop | Out-Null
                    Write-Log -Module "ASR" -Action "FailoverCompleted" -Status "SUCCESS" -TargetVm $targetVm
                }
            }
            2 {
                $cmd = "Start-AzRecoveryServicesAsrCommitFailoverJob"
                if ($WhatIf) {
                    Write-Log -Module "ASR" -Action "CommitFailover" -Command $cmd -Status "WHATIF" -TargetVm $targetVm
                } else {
                    Write-Log -Module "ASR" -Action "StartCommitFailoverJob" -Command $cmd -Status "RUNNING" -TargetVm $targetVm
                    $job = Invoke-WithRetry -ScriptBlock {
                        Start-AzRecoveryServicesAsrCommitFailoverJob -ProtectionObject $protectedItem
                    } -OperationName "CommitFailover" -Module "ASR" -MaxRetries $MaxRetries -RetryDelay $RetryDelay -TargetVm $targetVm
                    $job | Wait-AzRecoveryServicesAsrJob -ErrorAction Stop | Out-Null
                    Write-Log -Module "ASR" -Action "CommitCompleted" -Status "SUCCESS" -TargetVm $targetVm
                }
            }
            3 {
                $cmd = "Start-AzRecoveryServicesAsrReprotectJob"
                if ($WhatIf) {
                    Write-Log -Module "ASR" -Action "Reprotect" -Command $cmd -Status "WHATIF" -TargetVm $targetVm
                } else {
                    Write-Log -Module "ASR" -Action "StartReprotectJob" -Command $cmd -Status "RUNNING" -TargetVm $targetVm
                    $job = Invoke-WithRetry -ScriptBlock {
                        Start-AzRecoveryServicesAsrReprotectJob -ProtectionObject $protectedItem
                    } -OperationName "Reprotect" -Module "ASR" -MaxRetries $MaxRetries -RetryDelay $RetryDelay -TargetVm $targetVm
                    $job | Wait-AzRecoveryServicesAsrJob -ErrorAction Stop | Out-Null
                    Write-Log -Module "ASR" -Action "ReprotectCompleted" -Status "SUCCESS" -TargetVm $targetVm
                }
            }
            4 {
                $cmd = "Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction RecoveryToPrimary -PerformSourceSideActions -ShutDownSourceServer"
                if ($WhatIf) {
                    Write-Log -Module "ASR" -Action "Failback" -Command $cmd -Status "WHATIF" -TargetVm $targetVm
                } else {
                    Write-Log -Module "ASR" -Action "StartFailbackJob" -Command $cmd -Status "RUNNING" -TargetVm $targetVm
                    $job = Invoke-WithRetry -ScriptBlock {
                        Start-AzRecoveryServicesAsrUnplannedFailoverJob -ProtectionObject $protectedItem -Direction RecoveryToPrimary -PerformSourceSideActions -ShutDownSourceServer
                    } -OperationName "Failback" -Module "ASR" -MaxRetries $MaxRetries -RetryDelay $RetryDelay -TargetVm $targetVm
                    $job | Wait-AzRecoveryServicesAsrJob -ErrorAction Stop | Out-Null
                    Write-Log -Module "ASR" -Action "FailbackCompleted" -Status "SUCCESS" -TargetVm $targetVm
                }
            }
            5 {
                $cmd = "Start-AzRecoveryServicesAsrCommitFailoverJob"
                if ($WhatIf) {
                    Write-Log -Module "ASR" -Action "CommitFailback" -Command $cmd -Status "WHATIF" -TargetVm $targetVm
                } else {
                    Write-Log -Module "ASR" -Action "StartCommitFailbackJob" -Command $cmd -Status "RUNNING" -TargetVm $targetVm
                    $job = Invoke-WithRetry -ScriptBlock {
                        Start-AzRecoveryServicesAsrCommitFailoverJob -ProtectionObject $protectedItem
                    } -OperationName "CommitFailback" -Module "ASR" -MaxRetries $MaxRetries -RetryDelay $RetryDelay -TargetVm $targetVm
                    $job | Wait-AzRecoveryServicesAsrJob -ErrorAction Stop | Out-Null
                    Write-Log -Module "ASR" -Action "CommitFailbackCompleted" -Status "SUCCESS" -TargetVm $targetVm
                }
            }
            6 {
                $cmd = "Start-AzRecoveryServicesAsrReprotectJob"
                if ($WhatIf) {
                    Write-Log -Module "ASR" -Action "RestoreReprotect" -Command $cmd -Status "WHATIF" -TargetVm $targetVm
                } else {
                    Write-Log -Module "ASR" -Action "StartRestoreReprotectJob" -Command $cmd -Status "RUNNING" -TargetVm $targetVm
                    $job = Invoke-WithRetry -ScriptBlock {
                        Start-AzRecoveryServicesAsrReprotectJob -ProtectionObject $protectedItem
                    } -OperationName "RestoreReprotect" -Module "ASR" -MaxRetries $MaxRetries -RetryDelay $RetryDelay -TargetVm $targetVm
                    $job | Wait-AzRecoveryServicesAsrJob -ErrorAction Stop | Out-Null
                    Write-Log -Module "ASR" -Action "RestoreCompleted" -Status "SUCCESS" -TargetVm $targetVm
                }
            }
        }

        if (-not $WhatIf) {
            $toList = $emailConfig.to.Split(',')
            $emailCmd = "Send-MailMessage -Subject '[DRILL] $targetVm step $step'"
            Write-Log -Module "Email" -Action "SendNotification" -Command $emailCmd -Status "RUNNING" -TargetVm $targetVm

            $body = "Operation completed for $targetVm (step $step)`nTimestamp: $(Get-Date)"

            Send-MailMessage -SmtpServer $emailConfig.smtpServer `
                -Port $emailConfig.port -UseSsl -Credential $cred `
                -From $emailConfig.username `
                -To $toList `
                -Subject "[DRILL] $targetVm step $step" `
                -Body $body `
                -Encoding UTF8

            Write-Log -Module "Email" -Action "NotificationSent" -Status "SUCCESS" -TargetVm $targetVm
        } else {
            Write-Log -Module "Email" -Action "SkipNotification" -Status "WHATIF" -TargetVm $targetVm
        }

        Write-Log -Module "Main" -Action "VmCompleted" -Command "vm=$targetVm" -Status "SUCCESS" -TargetVm $targetVm
    }

    Write-Log -Module "Main" -Action "AllCompleted" -Status "SUCCESS"
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "[RESULT] All operations completed successfully" -ForegroundColor Green
    Write-Host "Log file: $($script:LogFile)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    Get-LogSummary | Out-File -FilePath "$($script:LogFile).summary.txt" -Encoding UTF8
    Write-Host "Summary: $($script:LogFile).summary.txt" -ForegroundColor Cyan
}
catch {
    $errorDetail = Format-ErrorDetail -Exception $_.Exception
    Write-Log -Module "Main" -Action "Failed" -Status "FAILED" -ErrorDetail $errorDetail
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "[ERROR] Operation failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Check log file: $($script:LogFile)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Red
    exit 1
}

    switch ($step) {
        1 {
            if ($WhatIf) {
                Write-Host "[WHATIF] : Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction PrimaryToRecovery -PerformSourceSideActions -ShutDownSourceServer" -ForegroundColor Yellow
            } else {
                $job = Start-AzRecoveryServicesAsrUnplannedFailoverJob -ProtectionObject $protectedItem `
                    -Direction PrimaryToRecovery `
                    -PerformSourceSideActions `
                    -ShutDownSourceServer
                Write-Host "[RUN] : Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction PrimaryToRecovery" -ForegroundColor Cyan
                $job | Wait-AzRecoveryServicesAsrJob -ErrorAction Stop | Out-Null
                Write-Host "[DONE] : Failover completed" -ForegroundColor Green
            }
        }
        2 {
            if ($WhatIf) {
                Write-Host "[WHATIF] : Start-AzRecoveryServicesAsrCommitFailoverJob" -ForegroundColor Yellow
            } else {
                $job = Start-AzRecoveryServicesAsrCommitFailoverJob -ProtectionObject $protectedItem
                Write-Host "[RUN] : Start-AzRecoveryServicesAsrCommitFailoverJob" -ForegroundColor Cyan
                $job | Wait-AzRecoveryServicesAsrJob -ErrorAction Stop | Out-Null
                Write-Host "[DONE] : Commit completed" -ForegroundColor Green
            }
        }
        3 {
            if ($WhatIf) {
                Write-Host "[WHATIF] : Start-AzRecoveryServicesAsrReprotectJob" -ForegroundColor Yellow
            } else {
                $job = Start-AzRecoveryServicesAsrReprotectJob -ProtectionObject $protectedItem
                Write-Host "[RUN] : Start-AzRecoveryServicesAsrReprotectJob" -ForegroundColor Cyan
                $job | Wait-AzRecoveryServicesAsrJob -ErrorAction Stop | Out-Null
                Write-Host "[DONE] : Reprotect completed" -ForegroundColor Green
            }
        }
        4 {
            if ($WhatIf) {
                Write-Host "[WHATIF] : Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction RecoveryToPrimary -PerformSourceSideActions -ShutDownSourceServer" -ForegroundColor Yellow
            } else {
                $job = Start-AzRecoveryServicesAsrUnplannedFailoverJob -ProtectionObject $protectedItem `
                    -Direction RecoveryToPrimary `
                    -PerformSourceSideActions `
                    -ShutDownSourceServer
                Write-Host "[RUN] : Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction RecoveryToPrimary" -ForegroundColor Cyan
                $job | Wait-AzRecoveryServicesAsrJob -ErrorAction Stop | Out-Null
                Write-Host "[DONE] : Failback completed" -ForegroundColor Green
            }
        }
        5 {
            if ($WhatIf) {
                Write-Host "[WHATIF] : Start-AzRecoveryServicesAsrCommitFailoverJob" -ForegroundColor Yellow
            } else {
                $job = Start-AzRecoveryServicesAsrCommitFailoverJob -ProtectionObject $protectedItem
                Write-Host "[RUN] : Start-AzRecoveryServicesAsrCommitFailoverJob" -ForegroundColor Cyan
                $job | Wait-AzRecoveryServicesAsrJob -ErrorAction Stop | Out-Null
                Write-Host "[DONE] : Commit failback completed" -ForegroundColor Green
            }
        }
        6 {
            if ($WhatIf) {
                Write-Host "[WHATIF] : Start-AzRecoveryServicesAsrReprotectJob" -ForegroundColor Yellow
            } else {
                $job = Start-AzRecoveryServicesAsrReprotectJob -ProtectionObject $protectedItem
                Write-Host "[RUN] : Start-AzRecoveryServicesAsrReprotectJob" -ForegroundColor Cyan
                $job | Wait-AzRecoveryServicesAsrJob -ErrorAction Stop | Out-Null
                Write-Host "[DONE] : Reprotect restore completed" -ForegroundColor Green
            }
        }
    }

    if (-not $WhatIf) {
        $toList = $emailConfig.to.Split(',')
        Send-MailMessage -SmtpServer $emailConfig.smtpServer `
            -Port $emailConfig.port -UseSsl -Credential $cred `
            -From $emailConfig.username `
            -To $toList `
            -Subject "[DRILL] $targetVm step $step" `
            -Body "Operation completed for $targetVm (step $step)`nTimestamp: $(Get-Date)" `
            -Encoding UTF8
        Write-Host "[EMAIL] : Notification sent" -ForegroundColor Cyan
    } else {
        Write-Host "[WHATIF] : Send-MailMessage -Subject '[DRILL] $targetVm step $step'" -ForegroundColor Yellow
    }
}
