# ChlorMe — iOS 本地小模型部署 & 高自定义 AI 伴侣软件

**ChlorMe** 是一款面向苹果生态（特别针对 iPhone 17 Pro / 12GB 统一内存深度优化）的开源本地小模型部署工具与高自定义伴侣聊天应用。

- **纯端侧隐私**：基于 `llama.cpp`（Metal GPU 加速 + Q8/Q4 KV Cache 量化）运行本地 `.gguf` 模型，同时支持无缝切换 **OpenAI 兼容远程接口**（如连家中 Mac 的 Ollama / llama-server）。
- **伴侣级双层记忆系统**：单文件 SQLite（WAL + FTS5 中文双字分词 + Accelerate `vDSP` 向量混合检索），支持**核心档案常驻 + 共同回忆日记 + 自动去重合并 + 滚动摘要 + 可视化回忆手账**。
- **高自定义角色工坊**：支持 **Character Card V2（JSON / PNG）导入导出**、关键词触发**世界书（Lorebook）**、多套**我的身份（Persona）**、拖拽式 **Prompt 编排器**、**实时 Prompt 透视**、**Min-P / DRY 防复读采样预设**、**Swipe 左滑重生成**与**微信式多段气泡**。
- **免装 Xcode 云端出包**：内置 GitHub Actions 流水线，Push 代码后 3–5 分钟自动编译 `ChlorMe-unsigned.ipa`，直接自签安装到 iPhone 17 Pro。

---

## 快速开始：免装 Xcode 云端编译 `.ipa` 并安装到 iPhone

### 1. 推送到你的 GitHub 仓库
```bash
git init
git add .
git commit -m "feat: initial ChlorMe iOS companion app"
git branch -M main
git remote add origin https://github.com/<你的用户名>/ChlorMe.git
git push -u origin main
```

### 2. 下载云端编译好的 `.ipa`
1. 打开 GitHub 仓库顶部的 **Actions** 标签页。
2. 等待 **Build ChlorMe iOS IPA** 运行完成（绿勾，约 3–5 分钟）。
3. 点击进入该次运行记录，在底部 **Artifacts** 区域下载 `ChlorMe-iOS-IPA`，解压得到 `ChlorMe-unsigned.ipa`。

### 3. 自签安装到 iPhone 17 Pro
任选一种你顺手的工具将 `ChlorMe-unsigned.ipa` 签名装入手机：
- **Sideloadly**（Mac/Windows）：插上数据线，拖入 `.ipa`，登录 Apple ID 一键签名安装。
- **SideStore / AltStore**：支持在手机端无线续签（免费 Apple ID 每 7 天续一次）。
- **付费开发者账号 / 自签证书工具**：可完整保留 `com.apple.developer.kernel.increased-memory-limit` 大内存权限，在 iPhone 17 Pro 上可流畅驾驭 7B–8B Q4 模型 + 8K 上下文。

---

## 首次打开使用建议

1. 进入底部 **「模型」** Tab：
   - 可直接在「精选开源伴侣模型」点击下载 `Qwen2.5-7B-Instruct (Q4_K_M)` 或 `Qwen3-4B (Q4_K_M)`；
   - 或点右上角 `+` 使用 **局域网 Wi-Fi 电脑拖传**，在电脑浏览器里把你本机已有的 `.gguf` 直接拖进手机；
   - 或点右上角 `+` 添加一个 **OpenAI 兼容远程 API** 先体验全套伴侣与记忆功能。
2. 回到 **「对话」** Tab，打开默认伴侣 **「苏晚」** 开始聊天：
   - 点击右上角 🧠 随时查看/修改「核心档案」与「共同回忆录」，或一键触发回忆整理；
   - 点击右上角 ⚙️ 可实时切换模型、采样参数，并展开 **「实时 Prompt 透视」** 查看每一轮发给模型的真实上下文；
   - 左滑 AI 回复即可 **Swipe 重生成** 多版本候选，长按可编辑原文或一键记入回忆。

---

## 项目目录结构

```text
├── Packages/ChlorCore/         # 纯 Swift 核心引擎（SQLite 数据库、vDSP 混合记忆、Prompt 编排、V2 角色卡、OpenAI 后端 + 单元测试）
├── ChlorMeApp/                 # iOS SwiftUI 原生界面 + llama.cpp Objective-C++ 桥接 + Wi-Fi 传输服务
├── project.yml                 # XcodeGen 工程描述文件
└── .github/workflows/          # GitHub Actions 自动编译与打包 .ipa 工作流
```
