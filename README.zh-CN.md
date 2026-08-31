# cc-sync

[English](README.md)

通过 SSH 在多台电脑之间同步 [Claude Code](https://claude.com/claude-code)
的会话和配置——离开工位、打开笔记本，`claude --resume` 无缝接着聊。
以 Claude Code 技能形态交付：你说话，Claude 编排，迁什么由你挑。

Claude Code 的每个会话都存在它运行的那台机器上（`~/.claude/projects/…`）。
换台电脑，你的对话、子智能体记录、计划文档、自动记忆就全留在原地了。
这个技能把它们安全、可校验地搬过去——连同 git 带不走的那些会话依赖一起。

## 安装

**零成本方式**——把一句话粘贴给任意 Claude Code 会话：

> 帮我安装并配置 https://github.com/ikook-wang/cc-sync ，然后把最近的会话同步到 `user@host`

AI 会读这份 README 自己完成剩下的事（给它的指引在下方）。

也可以自己跑安装器：

```bash
curl -fsSL https://raw.githubusercontent.com/ikook-wang/cc-sync/main/install.sh | bash
```

安装器做三件事：

1. 把技能装进 `~/.claude/skills/cc-sync`（重复运行即更新）；
2. 检测 **Tailscale**，没装就问你要不要装——可选，但装上之后跨网络迁移
   （公司 ↔ 家里）和局域网 SSH 完全一样；
3. 可选配置**默认配对机**（`~/.claude/cc-sync.conf`）和一个 `SessionEnd`
   钩子——**每个会话结束时自动同步到配对机**：静默、带分叉守卫、对端离线
   也绝不阻塞。（非交互安装：`CC_SYNC_PEER=user@host bash install.sh`。）

也可以手动安装：

```bash
git clone https://github.com/ikook-wang/cc-sync ~/.claude/skills/cc-sync
```

### 给 AI 智能体的指引

如果用户让你安装或使用 cc-sync，按以下步骤执行：

1. **安装**：运行 `curl -fsSL https://raw.githubusercontent.com/ikook-wang/cc-sync/main/install.sh | bash`。
   无终端环境下 Tailscale 和自动同步的询问会自动跳过——这是安全的预期行为。
2. **验证**：确认 `~/.claude/skills/cc-sync/SKILL.md` 存在，并用
   `bash ~/.claude/skills/cc-sync/scripts/list-sessions.sh "$PWD" 20`
   冒烟测试能列出当前项目的近期会话。
3. **使用**：阅读 `~/.claude/skills/cc-sync/SKILL.md` 并照做——它是完整的
   操作手册（预检 → 列表/挑选/同步 → 依赖审计 → 记忆合并）。如果你的环境
   已加载 `cc-sync` 技能，直接调用即可。绝不替用户挑会话，永远先展示列表。
4. **配置（可选）**：向用户询问配对机（`user@host`，Tailscale 主机名可用）。
   要开启会话结束自动同步，运行
   `CC_SYNC_PEER=<user@host> bash ~/.claude/skills/cc-sync/install.sh`。
5. **交还需要人的部分**：Tailscale 的安装登录需要 sudo 和浏览器——把确切
   命令交给用户亲手执行（`brew install --cask tailscale-app`，然后打开 App
   登录），不要在非交互环境里硬试。

## 使用

在任意 Claude Code 会话里直接说：

> 把最近 20 天的会话迁移到 ikook@my-laptop
>
> 换电脑继续，目标是 steve@home-imac

Claude 会走一套四阶段流程，迁哪些会话由你挑选：

| 阶段 | 做什么 |
|---|---|
| **预检** | SSH 连通性、两端路径一致性、远端 claude CLI 与版本核对 |
| **列表 / 挑选 / 同步** | 枚举工作区**及其子目录项目**的近期会话，你来挑，逐个复制（转录 + 子智能体附属目录）并用 sha256 校验 |
| **依赖审计** | 提取会话足迹 → 核对仓库 HEAD、倒推构建/发布脚本依赖的 gitignore 密钥、整体同步非 git 产物目录、检查工具链 |
| **记忆合并** | 合并 `MEMORY.md` 索引，两边条目都保留；改写远端前先备份 |

另外还支持：**配置同步**（CLAUDE.md、commands/、skills/——settings.json
先 diff 再选择性合并，绝不盲目覆盖）。开启自动同步后，日常使用零命令：
会话一结束，另一台机器上就已经有了。

### 安全保证

- **分叉守卫**——目标机上的同一会话如果更大（说明在那边续用过），同步会以
  `DIVERGED` 拒绝执行，绝不摧毁更新的历史。任何东西都不会被静默覆盖。
- **密钥不泄露**——审计只报告文件名、大小、哈希，内容绝不打印进对话。
- **绝不删除**——合并只做加法，远端索引改写前先备份。

### 唯一的纪律

**同一会话只在一台机器上续用。** 转录是追加式的，两台机器同时往一个会话追加
就会长出无法合并的两份历史。迁移之后，目标机就是那个会话的家。
（技能是对称的——反向迁移就在另一台机器上跑一遍。）

## 环境要求

- 两端 macOS 或 Linux；`ssh`（密钥认证）和 `rsync`
- 目标机装有 Claude Code CLI 并已登录
- 两台机器上**项目绝对路径必须一致**——会话按启动目录归档
- 同步时两端在线（装了 Tailscale 后在哪个网络都无所谓）

## 工作原理

会话存在 `~/.claude/projects/<槽位>/`，槽位名 = 项目绝对路径中非字母数字字符
全部替换为 `-`。每个会话是一个 `<uuid>.jsonl` 追加式转录，外加一个可选的同名
附属目录（子智能体转录、工具结果）。附带脚本（`scripts/`）负责枚举、复制、
校验和足迹提取；判断性工作——迁什么、哪些密钥要同步、记忆怎么合并——
在与你的对话中完成。格式细节见 [references/internals.md](references/internals.md)。

## 卸载

```bash
bash ~/.claude/skills/cc-sync/uninstall.sh
```

删除技能、自动同步钩子和配置文件；已同步的数据绝不动。

## 协议

[MIT](LICENSE)
