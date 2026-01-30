param($vmName, $step)

Write-Host "[]  $step ($vmName)" -ForegroundColor Cyan

$vmConfig = @{
    protectedItemPrefix = 'pc'
    vaultName = 'drill-rsv'
}

switch ($step) {
    1 {
        Write-Host " VM ($vmConfig.protectedItemPrefix$vmName)"
        Write-Host " VM ($vmConfig.protectedItemPrefix$vmName-drill)"
        Write-Host "  Azure 'Failover in progress'"
    }
    2 {
        Write-Host " "
        Write-Host "  Azure 'Protected (Failover completed)'"
    }
    3 {
        Write-Host " "
        Write-Host "  "
    }
    4 {
        Write-Host " VM ($vmConfig.protectedItemPrefix$vmName-drill)"
        Write-Host " VM ($vmConfig.protectedItemPrefix$vmName)"
        Write-Host "  Azure 'Failback in progress'"
    }
    5 {
        Write-Host " "
        Write-Host "  "
    }
    6 {
        Write-Host " "
        Write-Host "  "
    }
    default {
        Write-Host " 1-6" -ForegroundColor Red
        exit 1
    }
}

Write-Host " "
