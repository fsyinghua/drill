# Azure ASR 灾备演练六步流程详解

## 步骤1：启动故障转移（生产→灾备）
- **调用Cmdlet**：`Start-AzRecoveryServicesAsrUnplannedFailoverJob`
- **关键参数**：`-Direction PrimaryToRecovery -ShutDownSourceServer`
- **执行效果**：
  ✅ 关闭源生产VM
  ✅ 启动灾备环境VM
  ✅ 触发网络配置切换
- **状态变化**：`Protected` → `Failover in progress`
- **验证方式**：
  ```powershell
  Get-AzRecoveryServicesAsrJob | Where-Object {$_.Operation -eq 'Failover'}
  ```
- **⚠️ 注意事项**：
  - 必须安装Azure VM Guest Agent（控制来宾关机）
  - 需等待`State : Completed`再执行下一步

## 步骤2：提交故障转移
- **调用Cmdlet**：`Start-AzRecoveryServicesAsrCommitFailoverJob`
- **执行效果**：
  ✅ 确认故障转移结果
  ✅ 释放临时资源
  ✅ 固化灾备VM配置
- **状态变化**：`Failover in progress` → `Protected (Failover completed)`
- **验证方式**：
  Azure门户 → 保险库 → **复制保护的项** → 状态列
- **📌 关键点**：
  - 此操作**不可逆**
  - 必须在业务验证完成后执行

## 步骤3：启动反向复制
- **调用Cmdlet**：`Start-AzRecoveryServicesAsrReprotectJob`
- **执行效果**：
  ✅ 建立灾备→生产的复制通道
  ✅ 初始化反向同步
  ✅ 准备故障回切
- **状态变化**：`Protected (Failover completed)` → `Replicating`
- **验证方式**：
  ```powershell
  Get-AzRecoveryServicesAsrProtectionDirection
  ```
- **🔧 技术说明**：
  - 实际启动`Enable-AzRecoveryServicesAsrProtection`流程
  - 需要5-15分钟完成初始同步

## 步骤4：启动回切（灾备→生产）
- **调用Cmdlet**：`Start-AzRecoveryServicesAsrUnplannedFailoverJob`
- **关键参数**：`-Direction RecoveryToPrimary -ShutDownSourceServer`
- **执行效果**：
  ✅ 关闭灾备VM
  ✅ 重启原始生产VM
  ✅ 恢复网络配置
- **状态变化**：`Replicating` → `Failback in progress`
- **验证方式**：
  Azure门户 → **作业** → 查看过滤`Failback`
- **⚠️ 风险提示**：
  - 生产VM可能有数据差异（需提前验证）
  - DNS切换需额外操作

## 步骤5：提交回切
- **调用Cmdlet**：`Start-AzRecoveryServicesAsrCommitFailoverJob`
- **执行效果**：
  ✅ 确认回切结果
  ✅ 释放灾备环境资源
  ✅ 完成业务系统切换
- **状态变化**：`Failback in progress` → `Protected (Failback completed)`
- **验证方式**：
  ```powershell
  (Get-AzRecoveryServicesAsrReplicationProtectedItem).ProtectionState
  ```
- **📌 强制要求**：
  - 必须完成业务功能验证
  - 需检查所有依赖服务状态

## 步骤6：重建正向复制
- **调用Cmdlet**：`Start-AzRecoveryServicesAsrReprotectJob`
- **执行效果**：
  ✅ 重建生产→灾备的复制链路
  ✅ 恢复常规保护状态
  ✅ 重置RPO监控
- **状态变化**：`Protected (Failback completed)` → `Protected`
- **验证方式**：
  Azure门户 → **复制保护的项** → **运行状况** 列显示绿色
- **✅ 完成标志**：
  - 出现`State : Completed`日志
  - 邮件收到`[DRILL] step 6`通知

## 流程验证矩阵
| 步骤 | 门户状态变化 | 必须验证项 | 风险等级 |
|------|--------------|------------|----------|
| 1 | Protected → Failover | 源VM关机状态 | ⚠️⚠️⚠️ |
| 2 | Failover → Failover completed | 业务功能可用性 | ⚠️⚠️⚠️ |
| 3 | Failover completed → Replicating | 反向同步进度 | ⚠️⚠️ |
| 4 | Replicating → Failback | DNS/网络配置 | ⚠️⚠️⚠️ |
| 5 | Failback → Failback completed | 生产环境稳定性 | ⚠️⚠️⚠️ |
| 6 | Failback completed → Protected | RPO监控恢复 | ⚠️ |

> **审计要求**：所有步骤执行前必须保留`-WhatIf`输出记录，真实操作需邮件备案