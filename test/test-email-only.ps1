<#
.SYNOPSIS
    ASR Drill Email Notification Test Script
.DESCRIPTION
    Tests email sending functionality only, no Azure ASR operations
.PARAMETER vmName
    Virtual machine name to test
.PARAMETER step
    Drill step (1-6) or "All"
.EXAMPLE
    .\test-email-only.ps1 -vmName CA01SSEGHK -step 1
.EXAMPLE
    .\test-email-only.ps1 -vmName CA01SSEGHK -step All
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$vmName,
    [Parameter(Mandatory=$false)]
    [ValidateSet(1,2,3,4,5,6,"All")]
    [string]$step = "All"
)

function Read-Ini {
    param([string]$FilePath)
    (Get-Content $FilePath) -replace ' ', '' -join "`n" | ConvertFrom-StringData
}

function Send-DrillEmail {
    param(
        [string]$TargetVm,
        [int]$Step,
        [string]$SmtpServer,
        [int]$Port,
        [PSCredential]$Credential,
        [string]$From,
        [string[]]$To,
        [string]$Body
    )

    $subject = "[DRILL] $TargetVm step $Step"

    try {
        $mailParams = @{
            SmtpServer = $SmtpServer
            Port = $Port
            UseSsl = $true
            Credential = $Credential
            From = $From
            To = $To
            Subject = $subject
            Body = $Body
            BodyAsHtml = $false
            Encoding = [System.Text.Encoding]::UTF8
            ErrorAction = "Stop"
        }

        Send-MailMessage @mailParams

        Write-Host "[OK] Email sent: $subject" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "[FAIL] Email failed: $subject" -ForegroundColor Red
        Write-Host "Error: $_" -ForegroundColor Yellow
        return $false
    }
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "[EMAIL TEST] Email Function Test" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$emailConfig = Read-Ini -FilePath "email-config.ini"

if (-not $emailConfig) {
    Write-Error "Cannot read email-config.ini"
    exit 1
}

Write-Host "[CFG] Email config loaded"
Write-Host "  - SMTP Server: $($emailConfig.smtpServer)"
Write-Host "  - Port: $($emailConfig.port)"
Write-Host "  - From: $($emailConfig.username)"
Write-Host "  - To: $($emailConfig.to)"

# Prepare credentials
$securePassword = ConvertTo-SecureString $emailConfig.password -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential(
    $emailConfig.username,
    $securePassword
)

$toList = $emailConfig.to.Split(',')

# Determine test steps
$stepsToTest = @()
if ($step -eq "All") {
    $stepsToTest = 1,2,3,4,5,6
} else {
    $stepsToTest = @([int]$step)
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "[TEST] Start Email Test" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "VM Name: $vmName"
Write-Host "Test Steps: $($stepsToTest -join ', ')"
Write-Host ""

$successCount = 0
$failCount = 0

foreach ($s in $stepsToTest) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $body = @"
ASR Drill Email Notification Test

Test Info:
- VM: $vmName
- Step: $s
- Time: $timestamp
- Status: Test Email

This is a test email to verify ASR drill script notification function.
If you received this email, the mail configuration is correct.
"@

    Write-Host "--- Step $s ---" -ForegroundColor White

    $result = Send-DrillEmail `
        -TargetVm $vmName `
        -Step $s `
        -SmtpServer $emailConfig.smtpServer `
        -Port $emailConfig.port `
        -Credential $cred `
        -From $emailConfig.username `
        -To $toList `
        -Body $body

    if ($result) {
        $successCount++
    } else {
        $failCount++
    }

    Write-Host ""

    # Add delay to avoid email flooding
    Start-Sleep -Seconds 3
}

# Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "[RESULT] Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total Tests: $($stepsToTest.Count)"
Write-Host "Success: $successCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($failCount -eq 0) {
    Write-Host "[OK] All email tests passed!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "[FAIL] Some email tests failed. Check mail server config." -ForegroundColor Red
    exit 1
}
