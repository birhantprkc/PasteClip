<p align="center">
  <img src="PasteClip/Resources/Assets.xcassets/AppIcon.appiconset/256.png" width="128" height="128" alt="PasteClip 图标">
</p>

<h1 align="center">PasteClip</h1>

<p align="center">
  <strong>免费开源的 macOS 原生剪贴板管理器</strong>
  <br>
  卡片式界面类似付费应用 Paste，数据完全本地存储。
</p>

<p align="center">
  <a href="README.md">English</a> | 简体中文
</p>

<p align="center">
  <a href="https://github.com/minsang-alt/PasteClip/releases/latest"><img src="https://img.shields.io/github/v/release/minsang-alt/PasteClip?style=flat-square" alt="最新版本"></a>
  <a href="https://github.com/minsang-alt/PasteClip/releases"><img src="https://img.shields.io/github/downloads/minsang-alt/PasteClip/total?style=flat-square" alt="下载量"></a>
  <a href="https://github.com/minsang-alt/PasteClip/stargazers"><img src="https://img.shields.io/github/stars/minsang-alt/PasteClip?style=flat-square" alt="GitHub stars"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/minsang-alt/PasteClip?style=flat-square" alt="许可证"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue?style=flat-square" alt="macOS 14+">
</p>

<p align="center">
  <img src="docs/assets/pasteclip-demo.gif" width="800" alt="PasteClip 演示：按 ⌘⇧V 打开面板，单击卡片即复制，随后 ⌘V 粘贴">
</p>

## 简介

PasteClip 是一款免费开源（GPL-3.0）的 macOS 剪贴板管理器，用原生 Swift 6 + SwiftUI 编写，卡片式界面类似付费应用 Paste。数据完全本地存储，无账号、无服务器、无遥测。

## 主要功能

- **卡片式剪贴板历史**：支持文本、富文本、HTML、图片、链接、文件、颜色和代码片段
- **不打断工作流**：`⌘⇧V` 唤出非激活面板，当前应用保持焦点；单击卡片即复制到剪贴板并自动收起面板，回到当前应用直接 `⌘V` 粘贴
- **Pinboards 收藏夹**：把常用内容整理成命名收藏夹，支持拖拽排序
- **快速预览**：按 `空格` 进行 Quick Look 预览，支持全键盘操作
- **隐私控制**：可排除指定应用（如密码管理器），历史上限可配置、自动清理
- **对终端友好**：图片以 PNG + file URL 方式写入剪贴板，可以可靠地粘贴到 Ghostty / iTerm2
- **完全本地**：基于 SwiftData 本地存储，唯一的网络请求是 Sparkle 检查更新

## 截图

<p align="center">
  <img src="docs/assets/screenshot-history-panel.png" width="900" alt="PasteClip 历史面板">
</p>

## 安装

要求 **macOS 14 Sonoma 或更高版本**。

### Homebrew（推荐）

```bash
brew install --cask minsang-alt/tap/pasteclip
```

### 手动下载

从 [GitHub Releases](https://github.com/minsang-alt/PasteClip/releases/latest) 下载最新 `.dmg`，拖入「应用程序」文件夹。

> **注意**：应用暂未经过 Apple 公证，首次启动可能被 macOS 拦截。请在 **系统设置 → 隐私与安全性** 中点击「仍要打开」。

## 更多内容

键盘快捷键、隐私说明、从源码构建、参与贡献等完整文档请参阅 [英文 README](README.md)。

## 许可证

[GNU General Public License v3.0](LICENSE)
