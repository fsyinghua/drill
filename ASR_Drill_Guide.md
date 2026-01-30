# Azure 灾难恢复演练脚本使用手册

## 一、快速入门
```powershell
# 1. 设备登录认证
.\login.ps1

# 2. 执行演练（示例：对pc1执行步骤1）
.\drill.ps1 pc1 1
```

## 二、配置文件说明
### 1. 虚拟机配置 (`vm-config.ini`)
```ini
resourceGroup=drill-rg
vaultName=drill-rsv
fabricName=primary-fabric
containerName=vm-container
protectedItemPrefix=pc
```
**命名规则**：保护项名称 = `protectedItemPrefix` + 虚拟机名（如 `pc1` → `pcpc1`）

### 2. 邮件配置 (`email-config.ini`)
```ini
smtpServer=smtp.qq.com
port=587
username=your@qq.com
password=QQ邮箱授权码
to=admin1@qq.com,admin2@qq.com
```

## 三、执行模式说明

### 1. 真实执行模式（⚠️ 立即生效）
```powershell
.\drill.ps1 <虚拟机名> <步骤>
# 示例：.\drill.ps1 CA01SSEGHK 1
```
**真实输出示例**：
```
ResourceGroupName : RGP-GIT-S-ASR-R-SEA-002
Name              : 4d9c8e3f-1a2b-4c3d-8e7f-9a0b1c2d3e4f
Id                : /Subscriptions/f9481766-.../replicationJobs/4d9c8e3f-...
Type              : Microsoft.RecoveryServices/vaults/replicationJobs
JobType           : UnplannedFailover
State             : InProgress
```
> ⚠️ **关键事实**：
> - **不加 `-WhatIf` = 立即执行真实操作**（源VM将关机）
> - **无法撤销**，必须按流程走完6步
> - **等待 `State : Completed`** 才算成功

### 2. 模拟执行模式 (-WhatIf)
```powershell
.\drill.ps1 <虚拟机名> <步骤> -WhatIf
# 示例：.\drill.ps1 CA01SSEGHK 1 -WhatIf
```
**模拟输出示例**：
```
[模拟] 将执行: Start-AzRecoveryServicesAsrUnplannedFailoverJob -ProtectionObject $protectedItem -Direction PrimaryToRecovery -PerformSourceSideActions -ShutDownSourceServer
[模拟] 将执行: Send-MailMessage -SmtpServer smtp.qq.com -Port 587 -From your@qq.com -Subject "[DRILL] CA01SSEGHK step 1"
```
> ✅ **模拟模式特点**：
> - 显示**完整待执行命令**（可直接复制验证）
> - **不调用任何 Azure API**（零风险）
> - 仍验证虚拟机是否存在（配置有效性检查）

### 3. 模式对比表
| 操作                | 真实执行                  | 模拟执行 (-WhatIf)         |
|---------------------|---------------------------|----------------------------|
| **VM 关机**         | ✅ 真实关机               | ❌ 仅显示命令              |
| **ASR 状态变更**    | ✅ 立即生效               | ❌ 无任何变更              |
| **邮件发送**        | ✅ 真实发送               | ❌ 仅显示 SMTP 配置       |
| **输出标识**        | Azure 原生作业输出        | **黄色 [模拟] 前缀**     |

## 四、安全操作强制流程
1️⃣ **无变更工单时必须执行**：
```powershell
# 第一步：生成命令快照（邮件备案）
.\drill.ps1 CA01SSEGHK 1 -WhatIf > drill-plan.txt

# 第二步：仅当确认无误后执行
.\drill.ps1 CA01SSEGHK 1
```

2️⃣ **真实执行时必查**：
- 等待输出中出现 `State : Completed`（非 `InProgress`）
- 立即检查 Azure 门户：`保险库 → 作业 → 最近作业`

> 📌 **审计合规提示**：
> - 所有真实操作前必须保留 `-WhatIf` 输出记录
> - 建议在业务低峰期执行，并提前通知相关方

## 五、关键上下文设置（必须先执行）
在执行任何ASR操作前，必须按顺序完成以下三步：

## 四、关键上下文设置（必须先执行）
在执行任何ASR操作前，必须按顺序完成以下三步：
```powershell
# 1. 选择订阅
Select-AzSubscription -SubscriptionId $vmConfig.subscriptionId
# 2. 定位保险库
$vault = Get-AzRecoveryServicesVault -Name $vmConfig.vaultName -ResourceGroupName $vmConfig.resourceGroup
# 3. 设置ASR上下文
Set-AzRecoveryServicesAsrVaultContext -Vault $vault
```

> ⚠️ **致命错误预防**：
> - 缺少任一步骤会导致 `Get-AzRecoveryServicesAsrProtectionContainer` 失败
> - 错误示例：`No vault context selected`

## 三、操作步骤详解
| 步骤 | 操作                | 关键命令                                                                 | 验证方式                                                                 |
|------|---------------------|--------------------------------------------------------------------------|--------------------------------------------------------------------------|
| 1    | 故障转移             | `Start-AzRecoveryServicesAsrAzureToAzureFailover`                        | Azure门户显示 **"Failover in progress"**                               |
| 2    | 提交故障转移         | `Update-AzRecoveryServicesAsrProtection`                                 | 门户状态变为 **"Protected (Failover completed)"**                      |
| 3    | 停用复制             | `Disable-AzRecoveryServicesAsrReplicationProtectedItem`                  | 门户显示 **"Not protected"**                                           |
| 4    | 回退故障转移         | `Start-AzRecoveryServicesAsrUnplannedFailoverJob`                        | 门户显示 **"Failback in progress"**                                    |
| 5    | 提交回退             | `Start-AzRecoveryServicesAsrCommitFailoverJob`                           | 门户状态变为 **"Protected (Failback completed)"**
| 6    | 完成重新保护         | `Start-AzRecoveryServicesAsrReprotectJob`                                | 门户状态恢复为 **"Protected"**

## 四、完整演练样例
```powershell
# 1. 登录认证
.\login.ps1

# 2. 执行故障转移（步骤1）
.\drill.ps1 pc1 1
# 预期：自动关闭原pc1 → pc1-drill虚拟机启动

# 3. 检查作业状态
Get-AzRecoveryServicesAsrJob | Where-Object Operation -eq 'Failover'

# 4. 提交故障转移（步骤2）
.\drill.ps1 pc1 2

# 5. 执行故障恢复（步骤4）
.\drill.ps1 pc1 4
# 预期：自动关闭pc1-drill → 原pc1重新启动

# 6. 完成完整流程（步骤5+6）
.\drill.ps1 pc1 5
.\drill.ps1 pc1 6
```

## 五、本地测试指南（无需Azure连接）
### 运行环境要求
| 项目 | 要求 |
|------|------|
| PowerShell | 5.1+ 或 7.0+ |
| 控制台编码 | UTF-8（解决中文乱码） |
| 依赖模块 | 无需Azure模块 |

### 测试步骤
```powershell
# 1. 设置UTF-8编码（解决乱码）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 2. 运行模拟测试（示例：步骤1）
.\test\test-drill.ps1 pc1 1

# 3. 验证关键输出
✅ 模拟故障转移：关闭源VM (pcpc1)
✅ 模拟启动灾备VM (pcpc1-drill)
```

### 预期输出样例
```
[模拟模式] 正在执行步骤 1 (pc1)
✅ 模拟故障转移：关闭源VM (pcpc1)
✅ 模拟启动灾备VM (pcpc1-drill)
ℹ️  Azure门户应显示 'Failover in progress'
📧 模拟发送邮件通知（实际未发送）
```

### 打印测试报告
```powershell
# 生成可打印的纯文本报告
.\test\test-drill.ps1 pc1 1 | Out-File -Encoding utf8 test-report.txt

# 打印内容预览
Get-Content test-report.txt
```

## 六、日志排查
### 关键检查点
1. **源VM关机状态**：
   ```powershell
   # 检查步骤1/4的关机操作是否执行
   Get-AzRecoveryServicesAsrJob | Where-Object {$_.Operation -match 'Failover' -and $_.AllowedActions -contains 'ShutDownSourceServer'}
   ```
2. **Azure门户**：`Recovery Services vault → 监视 → 作业`
3. **常见问题**：
   - 若VM未关机：确认是否安装Azure VM Agent（必需来宾关机权限）
   - 需跳过关机：在脚本中添加 `-SkipSourceSideOperations` 参数