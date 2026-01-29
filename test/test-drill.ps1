param($vmName, $step)

Write-Host "[模拟模式] 正在执行步骤 $step ($vmName)" -ForegroundColor Cyan

$vmConfig = @{
    protectedItemPrefix = 'pc'
    vaultName = 'drill-rsv'
}

switch ($step) {
    1 {
        Write-Host "✅ 模拟故障转移：关闭源VM ($vmConfig.protectedItemPrefix$vmName)"
        Write-Host "✅ 模拟启动灾备VM ($vmConfig.protectedItemPrefix$vmName-drill)"
        Write-Host "ℹ️  Azure门户应显示 'Failover in progress'"
    }
    2 {
        Write-Host "✅ 模拟提交故障转移：复制关系已提交"
        Write-Host "ℹ️  Azure门户应显示 'Protected (Failover completed)'"
    }
    3 {
        Write-Host "✅ 模拟重新保护：建立恢复站点→主站点复制链路"
        Write-Host "ℹ️  开始反向数据同步"
    }
    4 {
        Write-Host "✅ 模拟故障恢复：关闭灾备VM ($vmConfig.protectedItemPrefix$vmName-drill)"
        Write-Host "✅ 模拟启动主VM ($vmConfig.protectedItemPrefix$vmName)"
        Write-Host "ℹ️  Azure门户应显示 'Failback in progress'"
    }
    5 {
        Write-Host "✅ 模拟提交故障恢复：反向复制环境清理完成"
        Write-Host "ℹ️  恢复原始主从关系"
    }
    6 {
        Write-Host "✅ 模拟最终重新保护：恢复主→灾备复制方向"
        Write-Host "ℹ️  开始正向数据同步"
    }
    default {
        Write-Host "❌ 无效步骤编号，请指定1-6" -ForegroundColor Red
        exit 1
    }
}

Write-Host "📧 模拟发送邮件通知（实际未发送）"