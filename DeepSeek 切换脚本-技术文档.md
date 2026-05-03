# DeepSeek 切换脚本 - 技术文档

## 1. 概述

本脚本用于将 Claude Code 配置从 Anthropic 官方切换至 DeepSeek 兼容接入，反之亦然。

### 1.1 脚本信息

| 属性 | 值 |
|------|-----|
| 名称 | `switch-deepseek.ps1` |
| 语言 | PowerShell |
| 最低版本 | PowerShell 5.1 (Windows 10+) |
| 作用对象 | `~/.claude/settings.json` |

### 1.2 DeepSeek 目标配置

| 字段 | 目标值 |
|------|--------|
| `env.ANTHROPIC_BASE_URL` | `https://api.deepseek.com/anthropic` |
| `env.ANTHROPIC_MODEL` | `deepseek-v4-flash` |
| `env.ANTHROPIC_API_KEY` | `sk-d4ed88714cd54c31b0d01d371c5f32c1` |
| `env.ANTHROPIC_DEFAULT_HAIKU_MODEL` | `deepseek-v4-flash` |
| `env.ANTHROPIC_DEFAULT_SONNET_MODEL` | `deepseek-v4-flash` |
| `env.ANTHROPIC_DEFAULT_OPUS_MODEL` | `deepseek-v4-flash` |

## 2. 命令规格

### 2.1 `status`

```
./switch-deepseek.ps1 status
```

**功能**：查看当前配置状态，无任何写操作。

**输出内容**：
- 主配置文件路径
- 备份文件路径
- 备份文件是否存在
- 当前状态判定（`claude-like` / `deepseek-like` / `unknown`）
- 关键字段摘要（不暴露 token/key 明文）

**状态判定规则**：

| 状态 | 判定条件 |
|------|----------|
| `deepseek-like` | `BASE_URL` = `https://api.deepseek.com/anthropic` **且** `MODEL` = `deepseek-v4-flash` |
| `claude-like` | 不满足 `deepseek-like` 且模型命名明显属于 Claude |
| `unknown` | 无法归入上述两类 |

### 2.2 `switch`

```
./switch-deepseek.ps1 switch
```

**功能**：将配置切换至 DeepSeek 目标配置。

**前置检查**：
1. `~/.claude/settings.json` 存在
2. 文件可读
3. 文件内容为合法 JSON 对象

**备份策略**：
- 仅当备份文件不存在时创建备份
- 备份路径：`~/.claude/settings.json.deepseek-switch.backup`
- 备份内容：切换前完整的 `settings.json`

**patch 规则**：
- 确保顶层 `env` 对象存在（不存在则创建）
- 仅修改白名单字段（见本文档第 3 节）
- 其他字段原样保留

**安全写入**：
1. 读取原文件 → 解析 JSON
2. 生成新内容 → 写入临时文件 `settings.json.tmp`
3. 原子替换原文件

### 2.3 `restore`

```
./switch-deepseek.ps1 restore
```

**功能**：从备份恢复原始配置。

**前置检查**：
1. 备份文件存在
2. 备份文件可读
3. 备份内容为合法 JSON 对象

**恢复策略**：
- 完整覆盖 `settings.json`（非字段级 merge）
- 恢复完成后提示成功

## 3. Patch 字段白名单

| 字段路径 | 说明 |
|----------|------|
| `env.ANTHROPIC_BASE_URL` | DeepSeek 入口地址 |
| `env.ANTHROPIC_MODEL` | 主模型 |
| `env.ANTHROPIC_API_KEY` | API 认证密钥 |
| `env.ANTHROPIC_DEFAULT_HAIKU_MODEL` | Haiku 默认模型 |
| `env.ANTHROPIC_DEFAULT_SONNET_MODEL` | Sonnet 默认模型 |
| `env.ANTHROPIC_DEFAULT_OPUS_MODEL` | Opus 默认模型 |

**保留字段**（不受 switch 影响）：
- `statusLine`
- `hooks`
- `permissions`
- `plugins`
- `theme`
- `outputStyle`
- `includeCoAuthoredBy`
- `cleanupPeriodDays`
- `env` 中非白名单的其他键

## 4. 错误处理

### 4.1 必须报错退出的场景

| 场景 | 退出码 |
|------|--------|
| 主配置文件不存在（switch 时） | 1 |
| 主配置文件不可读 | 1 |
| 主配置文件 JSON 非法 | 1 |
| `env` 存在但非对象 | 1 |
| 备份创建失败 | 1 |
| 临时文件写入失败 | 1 |
| 文件原子替换失败 | 1 |
| 备份不存在（restore 时） | 1 |
| 备份 JSON 非法（restore 时） | 1 |

### 4.2 仅告警但继续的场景

- 状态判定为 `unknown`
- 备份已存在（不再重复备份）
- 当前已是 `deepseek-like` 仍执行 switch

## 5. 幂等性

| 命令 | 幂等性 |
|------|--------|
| `status` | 天然幂等 |
| `switch` | 重复执行结果稳定，不破坏非白名单字段 |
| `restore` | 多次恢复结果一致（以备份为准） |

## 6. 输出规范

- 成功：简洁说明操作与结果
- 失败：说明失败步骤、文件、原因
- 敏感信息（token/key）：不输出明文，仅显示"已设置/未设置"

## 7. 依赖

- `jq`（用于 JSON 解析，通过 `jq` 命令或 PowerShell 原生方式实现）
- 无其他外部依赖

## 8. 文件路径约定

| 文件 | 路径 |
|------|------|
| 主配置 | `~/.claude/settings.json` |
| 备份文件 | `~/.claude/settings.json.deepseek-switch.backup` |
| 临时文件 | `~/.claude/settings.json.tmp`（实现细节，不暴露给用户） |
