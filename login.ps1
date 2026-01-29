if (-not (Get-AzContext -ErrorAction SilentlyContinue)) {
    $config = Get-Content vm-config.ini | ConvertFrom-StringData
    Connect-AzAccount -UseDeviceAuthentication -Subscription $config.subscriptionId
}