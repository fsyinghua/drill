# 版本发布流程规范

**文档版本**: 1.0  
**生效日期**: 2026-01-30  
**当前版本**: v1.0.0

---

## 1. 版本号规则

采用语义化版本号 (Semantic Versioning):

```
主版本号.次版本号.修订号
   v        X        Y        Z
```

| 版本号类型 | 规则 | 示例 |
|:---------|:----|:----|
| **主版本 (Major)** | 不兼容的变更 | v1.0.0 → v2.0.0 |
| **次版本 (Minor)** | 新功能（向下兼容） | v1.0.0 → v1.1.0 |
| **修订号 (Patch)** | Bug修复（向下兼容） | v1.0.0 → v1.0.1 |

---

## 2. 当前版本状态

| 项目 | 值 |
|:----|:----|
| 当前版本 | **v1.1.8** |
| 发布日期 | 2026-01-31 |
| 状态 | 🔄 开发中 |
| GitHub Release | https://github.com/fsyinghua/drill/releases/tag/v1.1.8 |

---

## 3. 版本历史

### v1.1.8 (2026-01-31) - Bug修复（使用正确的Reprotect命令）

**状态**: 🔄 开发中

**问题修复**:
- 远程机器上确认 `Update-AzRecoveryServicesAsrProtectionDirection` 存在但参数集冲突
- 通过 `Get-Command` 分析确认正确的参数集用法：
  - **简单参数集**（无 PCM）：`-ReplicationProtectedItem $protectedItem -Direction RecoveryToPrimary`
  - **AzureToAzure 参数集**（有 PCM）：`-AzureToAzure -ProtectionContainerMapping $pcm -LogStorageAccountId $logId -ReplicationProtectedItem $protectedItem`

**变更说明**:
- 所有 4 处 reprotect 调用改用 `Update-AzRecoveryServicesAsrProtectionDirection`
- 根据是否找到 ProtectionContainerMapping 自动选择参数集
- 更新执行计划显示，描述正确的参数集选项

**包含文件变更**:
- `drill.ps1` - 更新 Step 3/6 的 reprotect 命令（serial 和 parallel 模式）
- `RELEASE.md` - 更新版本说明
- 移除了复杂的 `-AzureToAzure` 和 `-ProtectionContainerMapping` 参数

**包含文件变更**:
- `drill.ps1` - 使用 Start-AzRecoveryServicesAsrResynchronizeReplicationJob

### v1.1.7 (2026-01-31) - Bug修复（添加-AzureToAzure参数）

**状态**: ✅ 已发布

**问题修复**:
- `AzureToAzure` 参数集**必须**使用 `-AzureToAzure` 开关参数
- 没有 `-AzureToAzure` 参数时，无法使用 `-ProtectionContainerMapping`
- 添加 `-AzureToAzure` 参数到所有 4 处 reprotect 调用

**变更说明**:
- 未找到 PCM 时：`-AzureToAzure -ReplicationProtectedItem $protectedItem`
- 找到 PCM 时：`-AzureToAzure -ProtectionContainerMapping $pcm -ReplicationProtectedItem $protectedItem`

**包含文件变更**:
- `drill.ps1` - 添加 `-AzureToAzure` 参数

### v1.1.6 (2026-01-31) - Bug修复（简化Reprotect命令参数）

**状态**: ✅ 已发布

**问题修复**:
- 移除了 `-Direction RecoveryToPrimary` 参数
- 使用简单的 ByRPIObject 参数集：`-ReplicationProtectedItem $protectedItem`
- 确认 `Start-AzRecoveryServicesAsrReprotectJob` 命令不存在于 Az.RecoveryServices 7.11.0
- 使用 `Update-AzRecoveryServicesAsrProtectionDirection` 作为替代命令

**变更说明**:
- 未找到 ProtectionContainerMapping 时：`-ReplicationProtectedItem $protectedItem`
- 找到 ProtectionContainerMapping 时：`-ProtectionContainerMapping $pcm -ReplicationProtectedItem $protectedItem`
- 修复 4 处：串行 Step 3/6，并行 Step 3/6

**包含文件变更**:
- `drill.ps1` - 简化 reprotect 命令参数

### v1.1.5 (2026-01-31) - Bug修复（参数集冲突）

**状态**: ✅ 已发布

**问题修复**:
- 修复 `-Direction` 和 `-ProtectionContainerMapping` 参数集冲突问题
- 这两个参数不能同时使用，属于不同的参数集
- ByRPIObject 参数集：`-ReplicationProtectedItem`, `-Direction`
- AzureToAzure 参数集：`-ProtectionContainerMapping`, `-ReplicationProtectedItem`

**变更说明**:
- 未找到 ProtectionContainerMapping 时：使用 `-Direction RecoveryToPrimary`
- 找到 ProtectionContainerMapping 时：使用 `-ProtectionContainerMapping` (不含 `-Direction`)
- 修复 4 处：串行 Step 3/6，并行 Step 3/6
- 添加命令打印功能，执行前显示完整命令便于调试

**包含文件变更**:
- `drill.ps1` - 分离参数集使用，添加命令显示

### v1.1.4 (2026-01-31) - Bug修复（正确的Reprotect命令）

**状态**: ✅ 已发布

**问题修复**:
- 修复 Step 3 和 Step 6 的 reprotect 命令问题
- 原来的命令 `Start-AzRecoveryServicesAsrReverseReplicationJob` 和 `Start-AzRecoveryServicesAsrReprotectJob` 都不存在
- 使用正确的命令 `Update-AzRecoveryServicesAsrProtectionDirection -AzureToAzure` 替换
- 在 Az.RecoveryServices 模块版本 7.11.0 中已验证该命令可用

**变更说明**:
- 串行执行模式 Step 3：使用 `Update-AzRecoveryServicesAsrProtectionDirection -AzureToAzure`
- 串行执行模式 Step 6：使用 `Update-AzRecoveryServicesAsrProtectionDirection -AzureToAzure`
- 并行执行模式 Step 3：使用 `Update-AzRecoveryServicesAsrProtectionDirection -AzureToAzure`
- 并行执行模式 Step 6：使用 `Update-AzRecoveryServicesAsrProtectionDirection -AzureToAzure`
- 更新执行计划显示，使用正确的命令名称
- 添加自动获取 ProtectionContainerMapping 的逻辑
- 添加配置参数 `protectionContainerMapping` 和 `logStorageAccountId`

**包含文件变更**:
- `drill.ps1` - 替换所有 reprotect 命令为正确的 `Update-AzRecoveryServicesAsrProtectionDirection`
- `vm-config.ini` - 添加 `protectionContainerMapping` 和 `logStorageAccountId` 配置参数

**参考信息**:
- 错误命令（不存在）: `Start-AzRecoveryServicesAsrReverseReplicationJob`
- 错误命令（不存在）: `Start-AzRecoveryServicesAsrReprotectJob`
- 正确命令: `Update-AzRecoveryServicesAsrProtectionDirection -AzureToAzure`
- 作用: 更新保护方向以实现重新保护/反向复制操作

### v1.1.3 (2026-01-30) - 邮件通知增强

**状态**: ✅ 已发布

**增强**:
- 邮件通知添加开始时间、结束时间和执行时长
- 添加 Get-ElapsedTime 函数计算执行时长（小时/分钟/秒）
- 所有日志条目添加时间戳
- Wait-AsrJob 函数返回详细的时间信息
- 邮件内容包含完整的时间信息（Start Time, End Time, Duration）

**包含文件变更**:
- `drill.ps1` - 邮件通知和日志时间增强

### v1.1.2 (2026-01-30) - Bug修复和输出增强

**状态**: ✅ 已发布

**修复**:
- 修正 ASR 重新保护命令名称（ReprotectJob → ReverseReplicationJob）
- 修复 step 3 和 step 6 的无效命令错误
- 更新并行模式和串行模式中的所有相关命令

**增强**:
- 并行模式添加详细的执行计划输出
- 显示所有配置参数（订阅、保管库、资源组等）
- 显示每个 VM 的完整命令和日志路径
- 改进监控部分的可读性

**包含文件变更**:
- `drill.ps1` - 修正命令名称和增强输出

### v1.1.1 (2026-01-30) - Bug修复

**状态**: ✅ 已发布

**修复**:
- 修复 Wait-AsrJob 函数超时和错误处理问题
- 添加 60 分钟超时机制，防止无限等待
- 添加 try-catch 捕获作业状态刷新错误
- 支持多种成功状态（Completed 和 Succeeded）
- 显示作业执行进度和已用时间
- 修正函数调用语法（从管道改为参数传递）
- 并行执行脚本同步添加 Wait-AsrJob 函数

**包含文件变更**:
- `drill.ps1` - Wait-AsrJob 函数增强

### v1.1.0 (2026-01-30) - 并行执行功能

**状态**: ✅ 已发布

**功能**:
- 新增 `-Parallel` 参数，支持批量VM并行执行
- 使用 Start-Job 实现 PowerShell 5.1 兼容的并行处理
- 每个VM独立进程、独立Azure上下文
- 实时状态监控和独立日志文件
- 邮件通知并行发送
- 启动时显示完整执行命令

**包含文件变更**:
- `drill.ps1` - 添加并行执行模式
- `report/drill-parallel-test-report.md` - 并行测试报告

### v1.0.0 (2026-01-30) - 初始发布

**状态**: ✅ 已发布

**功能**:
- 单机ASR演练6步自动化脚本
- 批量VM演练支持 (-InputFile)
- 邮件通知功能
- WhatIf预览模式

**测试状态**:
- 单机6步测试: ✅ 通过
- 批量16VM测试: ✅ 通过
- 邮件功能测试: ✅ 通过

**包含文件**:
```
drill.ps1              # 主脚本
test-email-only.ps1    # 邮件测试脚本
vm-config.ini          # VM配置
email-config.ini       # 邮件配置
vms.txt                # 批量VM列表
README.md              # 说明文档
report/*.md            # 测试报告
```

---

## 4. 发布流程

### 4.1 发布前检查清单

- [ ] 所有功能测试通过
- [ ] 代码无语法错误
- [ ] 文档已更新
- [ ] 无敏感信息泄露
- [ ] 本地测试通过

### 4.2 发布步骤

```powershell
# 1. 确认当前分支
git checkout main

# 2. 获取最新代码
git pull origin main

# 3. 创建新Tag (按版本号规则)
git tag -a v1.0.1 -m "Release v1.0.1"

# 4. 推送到GitHub
git push origin v1.0.1

# 5. 在GitHub创建Release
# 访问: https://github.com/fsyinghua/drill/releases/new?tag=v1.0.1
```

### 4.3 GitHub Release 填写内容

```markdown
## What's Changed

- Feature: [新功能描述]
- Fix: [修复内容]
- Docs: [文档更新]

## Test Results

- 单机测试: ✅ 通过
- 批量测试: ✅ 通过
- 邮件测试: ✅ 通过

## Files Changed

- `drill.ps1` - Main script updated
- `test-email-only.ps1` - Email test improved
- `report/*.md` - Reports added
```

---

## 5. 后续版本规划

| 版本 | 计划内容 | 状态 |
|:----|:--------|:----:|
| v1.1.3 | 邮件通知增强 | ✅ 已发布 |
| v1.1.4 | 预期：Bug修复和小改进 | 待开发 |
| v1.2.0 | 预期：日志增强、进度显示 | 待开发 |
| v2.0.0 | 预期：重大功能更新 | 待规划 |

---

## 6. 分支策略

```
main (稳定分支)
    │
    ├── v1.1.0 ──── 已发布 (tag) - 并行执行
    │
    ├── v1.1.1 ──── 下一个版本 (tag)
    │
    └── 开发中代码
```

**原则**:
- 长期分支: 仅 `main`
- 发布标记: 使用 Tag
- 不创建长期 release 分支

---

## 7. 常见问题

### Q: 已发布的Tag可以修改吗?
**A**: ❌ 绝对不可以。已发布Tag是快照，修改会导致历史混乱。

### Q: 如何回滚到旧版本?
```powershell
git checkout v1.0.0
```

### Q: 如何查看所有版本?
```powershell
git tag -l
# 或访问 https://github.com/fsyinghua/drill/releases
```

### Q: 什么时候用 Major vs Minor vs Patch?
- **Patch**: 修复bug、优化代码
- **Minor**: 新功能（不破坏现有功能）
- **Major**: 破坏性变更、API不兼容

---

## 8. 链接

- GitHub Releases: https://github.com/fsyinghua/drill/releases
- 当前版本: v1.1.3
- 下一个版本: v1.1.4

---

*文档更新: 2026-01-30*
*当前版本: v1.1.0*
