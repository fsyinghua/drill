# 单机ASR演练测试报告

---

**测试日期**: 2026-01-30  
**测试VM**: CA01SSEGHK  
**执行模式**: WhatIf (预览)  
**测试结果**: ✅ 全部通过

---

## 环境配置

| 配置项 | 值 |
|:-----|:---|
| 订阅ID | `f9481766-cf8e-400c-80f2-37f18ad1c094` |
| 恢复服务保管库 | `RSV-GIT-S-ASR-R-SEA-001` |
| 资源组 | `RGP-GIT-S-ASR-R-SEA-002` |
| 区域 | East Asia |

---

## 测试结果汇总

| 步骤 | 操作类型 | 方向 | ASR Cmdlet | 状态 |
|:---:|:-------:|:---:|:----------|:---:|
| 1 | 计划性故障转移 | Primary → Recovery | `Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction PrimaryToRecovery -PerformSourceSideActions -ShutDownSourceServer` | ✅ |
| 2 | 确认故障转移 | - | `Start-AzRecoveryServicesAsrCommitFailoverJob` | ✅ |
| 3 | 逆向同步 | Recovery → Primary | `Start-AzRecoveryServicesAsrReprotectJob` | ✅ |
| 4 | 故障还原 | Recovery → Primary | `Start-AzRecoveryServicesAsrUnplannedFailoverJob -Direction RecoveryToPrimary -PerformSourceSideActions -ShutDownSourceServer` | ✅ |
| 5 | 确认故障还原 | - | `Start-AzRecoveryServicesAsrCommitFailoverJob` | ✅ |
| 6 | 恢复正向同步 | Primary → Recovery | `Start-AzRecoveryServicesAsrReprotectJob` | ✅ |

---

## 流程图

```
┌─────────────┐    Step 1    ┌─────────────┐
│   Primary   │ ───────────► │  Recovery   │
│  (East Asia)│   Failover   │  (East Asia)│
└─────────────┘              └─────────────┘
       ▲                           │
       │                           ▼ Step 3
       │                    ┌─────────────┐
       │                    │  Reprotect  │
       │◄────────────────── │ (逆向同步)  │
       │    Step 4          └─────────────┘
       │    Failback              │
       │                           ▼ Step 5
       │                    ┌─────────────┐
       └─────────────────── │  Commit     │
            Step 6          │  Failback   │
                    ┌───────│             │
                    │       └─────────────┘
                    ▼
              ┌─────────────┐
              │  Reprotect  │
              │ (正向同步恢复)│
              └─────────────┘
```

---

## 结论

✅ **所有6个步骤的WhatIf预览输出符合设计预期**  
✅ ASR cmdlet调用参数正确  
✅ 邮件通知功能正常  
✅ **脚本已准备就绪，可在生产环境执行真实演练**

---

*报告生成时间: 2026-01-30*
