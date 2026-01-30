function Read-Ini {
    (Get-Content $args[0]) -replace ' ', '' -join "`n" | ConvertFrom-StringData
}

$emailConfig = Read-Ini (Join-Path $PSScriptRoot '..\email-config.ini')

$securePassword = ConvertTo-SecureString $emailConfig.password -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential(
    $emailConfig.username,
    $securePassword
)

Send-MailMessage -SmtpServer $emailConfig.smtpServer `
    -Port $emailConfig.port -UseSsl -Credential $cred `
    -From $emailConfig.username `
    -To $emailConfig.to.Split(',') `
    -Subject "[TEST] Azure Drill Notification" `
    -Body "This is a test email from Azure disaster recovery drill script.\nTimestamp: $(Get-Date)" `
    -DeliveryNotificationOption OnSuccess
