# HyperOS Boot Animation Module

**一款通过 Magisk / KernelSU / APatch 替换开机动画的模块。**

**A lightweight Magisk / KernelSU / APatch module for customizing device boot animations.**

> 🤖 本 README 由 AI 生成，内容基于 v2.4.0 实际功能整理。

---

## 简介 | Introduction

这是一个用来**替换系统开机动画**的模块，**不修改系统分区**，通过 Bind Mount 实现效果。

**v2.4.0** 是本模块的当前版本，两版底层已统一，仅内置动画不同。重新加入了状态与日志面板，方便开发调试；实验性功能新增了改分辨率、偏移、帧率、导入开机音频等能力。

This module replaces your boot animation **without modifying system partitions**, using Bind Mount. **v2.4.0** unifies the two variants (only built-in animation differs), re-adds status & logs for debugging, and introduces experimental features such as resolution / offset / fps editing and boot audio import.

---

## 支持 | Support

- **米系**：MIUI / HyperOS（Redmi / Xiaomi）
- **欧加系**：ColorOS / OxygenOS（OPPO / OnePlus / realme）
- **Root 方案**：Magisk / KernelSU / APatch
- **不支持**：三星（Samsung）—— 系统机制完全不同，**绝对无效**

- **Xiaomi**: MIUI / HyperOS
- **OnePlus family**: ColorOS / OxygenOS
- **Root**: Magisk / KernelSU / APatch
- **Not supported**: Samsung — completely different mechanism, **will not work**

---

## 功能 | Features

- 🎬 **自定义开机动画**：导入任意 bootanimation zip 并应用
- 🔄 **随机 / 顺序播放**：多套动画随机或按顺序轮换
- ✏️ **改分辨率 / 偏移 / 帧率**（实验性）：为动画修改 `desc.txt`
- 🔊 **导入开机音频**（实验性）：Android 9+ 内嵌，≤ Android 9 挂载，MIUI 单独安装
- 🖥️ **WebUI**：内置图形界面，支持切换动画、主题、语言
- 📋 **状态与日志**：查看运行状态、挂载信息、错误日志
- 🌐 **双语**：中文 / English，一键切换

- 🎬 **Custom boot animation**: import any bootanimation zip
- 🔄 **Random / Sequential**: rotate or randomize multiple animations
- ✏️ **Resolution / Offset / FPS editor** (experimental): modifies `desc.txt`
- 🔊 **Boot audio import** (experimental): embedded for Android 9+, mounted for ≤ 9, separate install for MIUI
- 🖥️ **WebUI**: built-in UI for switching animations, theme, language
- 📋 **Status & logs**: runtime state, mount info, error logs
- 🌐 **Bilingual**: Chinese / English

---

## 版本 | Versions

| 变体 | 品牌 | 内置动画 |
|------|------|----------|
| **HyperOS 变体** | xiaomi | `MIUI粒子效果.zip` |
| **一加变体** | oneplus | `MIUI粒子动画oneplus.zip` |

两版**底层代码完全一致**，仅 `payload/.brand` 和内置动画不同。

| Variant | Brand | Built-in animation |
|---------|-------|--------------------|
| **HyperOS** | xiaomi | `MIUI粒子效果.zip` |
| **OnePlus** | oneplus | `MIUI粒子动画oneplus.zip` |

Both variants share **identical code**, differing only in `payload/.brand` and the bundled animation.

---

## 安装 | Installation

1. 下载对应变体的模块 ZIP
2. 打开 Magisk / KernelSU / APatch 管理器
3. **模块** → **从存储安装**
4. 刷入后**重启设备**

> ⚠️ 首次使用建议先备份当前开机动画。

---

## 使用 | Usage

### WebUI

模块安装后，在管理器里打开模块设置即可进入 WebUI。可以：

- 切换动画
- 导入新动画
- 随机 / 顺序播放
- 修改分辨率、偏移、帧率
- 导入开机音频
- 切换主题 / 语言
- 查看状态与日志

### 导入动画

**方式一**：WebUI 里点"选择 ZIP 文件"直接导入

**方式二**：把 zip 放到 `/sdcard/Download` 或 `/sdcard`，在 WebUI 里点"扫描手机存储"导入

---

## 从源码构建 | Building from Source

### 目录结构

```
.
├── bin/                  # shell 脚本
│   ├── common.sh         # 公共函数
│   ├── bootanimctl.sh    # WebUI 命令入口
│   └── module-desc.sh    # 更新 module.prop
├── webroot/              # WebUI
│   ├── index.html
│   └── theme.css
├── payload/              # 开机动画
│   ├── MIUI粒子效果/      # 动画目录（不含 zip）
│   ├── MIUI粒子动画oneplus/
│   ├── pack.sh           # 打 zip 脚本
│   └── README.md
├── META-INF/             # 刷机脚本
├── build.sh              # 打包工具
├── push.sh               # 推送工具（开发测试）
├── customize.sh          # 安装脚本
├── post-fs-data.sh
├── post-mount.sh
├── service.sh
├── uninstall.sh
├── module.prop           # 模块信息
└── README.md
```

### 打包

```bash
# 1. 进入 payload 打动画 zip（首次）
cd payload
bash pack.sh
cd ..

# 2. 打包
bash build.sh
```

选：

- `1` 打全部（HyperOS + 一加）
- `2` 只打 HyperOS 变体
- `3` 只打 一加变体

输出在 `dist/`。

### 为什么要先跑 `pack.sh`

仓库**不包含动画 zip**（避免大文件），只包含**解压后的动画目录**。`pack.sh` 会把目录打回 zip，供 `build.sh` 使用。

详见 `payload/README.md`。

---

## 更新日志 | Changelog

详见 [开机动画切换更新日志.md](开机动画切换更新日志.md)。

### v2.4.0

- 两版底层合为一体，仅内置动画不同
- 重新加入状态与日志
- 加入新版界面作为主题
- 实验性功能：改分辨率、偏移、fps、导入开机音频
- 优化双语

---

## 工作原理 | How It Works

模块通过 **Bind Mount** 把自定义开机动画挂载到系统默认的 `bootanimation.zip` 路径，**不修改系统分区**。

启动时依次执行：

1. `post-fs-data.sh`：早期挂载
2. `post-mount.sh`：分区挂载后
3. `service.sh`：开机完成后

WebUI 通过 `bin/bootanimctl.sh` 操作动画、配置、音频。

---

## 贡献 | Contributing

欢迎提交 Issue 与 Pull Request。

1. Fork 本仓库
2. 新建分支：`git checkout -b feature/your-feature`
3. 提交：`git commit -m "Add your feature"`
4. 推送：`git push origin feature/your-feature`
5. 发起 Pull Request

---

## 致谢 | Credits

- **wqv9008**（酷安）— [开机动画模块？！](https://www.coolapk.com/feed/73474325)
- **小雨不是雨呀**（酷安）— [澎湃OS开机启动动画切换模块](https://www.coolapk.com/feed/73108234)
- **Saigetsu13**（酷安）— [搓了一个小米HyperOS3开机动画](https://www.coolapk.com/feed/71452187)

---

## 开源协议 | License

本项目遵循仓库内 [LICENSE](LICENSE) 文件所声明的协议。

---

## 免责声明 | Disclaimer

**刷机有风险，操作需谨慎。** 使用本模块造成的任何设备损坏、数据丢失或无法开机，作者与贡献者不承担责任。请确保你了解 Magisk 模块的基本操作并有能力在出问题时恢复设备。

**Flash at your own risk.** The authors and contributors are not responsible for any device damage, data loss, or boot failure caused by this module.