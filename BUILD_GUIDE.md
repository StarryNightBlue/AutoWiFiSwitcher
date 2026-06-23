# AutoWiFiSwitcher 构建与安装指南

## 概述

iOS 端的自动 WiFi 切换工具（非越狱版）。基于 `NEHotspotConfigurationManager` 实现，
按优先级列表自动切换 WiFi（每次需手动确认系统弹窗）。

---

## 项目结构

```
AutoWiFiSwitcher/
├── project.yml                       # XcodeGen 配置
├── .github/workflows/build-ipa.yml   # GitHub Actions CI 配置
└── AutoWiFiSwitcher/
    ├── AutoWiFiSwitcherApp.swift      # App 入口
    ├── Info.plist                     # 应用配置 + 权限声明
    ├── AutoWiFiSwitcher.entitlements  # HotspotConfiguration 权限
    ├── Models/
    │   └── WiFiNetwork.swift          # 数据模型
    ├── Services/
    │   ├── WiFiManager.swift          # WiFi 读取/连接/网络状态监测
    │   ├── WiFiAutoSwitchService.swift # 自动切换逻辑
    │   └── KeychainHelper.swift       # Keychain 密码存储
    └── Views/
        ├── ContentView.swift          # 主界面
        └── WiFiFormView.swift         # 添加 WiFi 表单
```

---

## 完整操作流程

### 第一步：准备环境（Windows）

需要安装：
- **Git** — 管理代码
- **Sideloadly**（https://sideloadly.io）— 用于将 IPA 安装到 iPhone
- **Apple ID**（免费即可，无需付费开发者账号）

### 第二步：提交代码到 GitHub

```bash
cd AutoWiFiSwitcher
git init
git add .
git commit -m "Initial commit"
git remote add origin https://github.com/你的用户名/AutoWiFiSwitcher.git
git push -u origin main
```

> ⚠️ 如果 `git push` 报错 `Could not connect to server`，说明 GitHub 被墙：
> ```bash
> # 配置代理（端口改成你 VPN/Clash/v2ray 的实际端口）
> git config --global http.proxy http://127.0.0.1:7890
> git config --global https.proxy http://127.0.0.1:7890
> ```
> 常见端口：Clash 默认 7890，v2ray 默认 1080，SS 默认 1080

### 第三步：自动构建

Push 到 GitHub 后，Actions 自动触发：

1. 打开仓库页面 → **Actions** 标签
2. 点击正在运行的 workflow
3. 等待 **Build IPA (for sideloading)** 完成（约 3-5 分钟）
4. 展开底部 **Artifacts** → 下载 `AutoWiFiSwitcher.zip`
5. 解压得到 `AutoWiFiSwitcher.ipa`

### 第四步：安装到 iPhone

1. 手机连电脑，打开 **Sideloadly**
2. 拖入 `.ipa` 文件
3. 输入你的 **Apple ID** 和密码
4. 点击 **Start** → 等待安装完成
5. 手机上：**设置 → 通用 → VPN 与设备管理 → 点击你的 Apple ID → 信任**

> ⚠️ 免费 Apple ID 签名的 App 7 天后过期，需要重新侧载。
> Sideloadly 支持保存 Apple ID 方便续签。

### 第五步：使用

1. 打开 AutoWiFi
2. **允许位置权限**（读取当前 WiFi 名称必需）
3. 点击 **Add Network** 添加常用 WiFi（SSID + 密码）
4. 拖拽排序（#1 优先级最高）
5. 开启 **Auto-Switch** 开关
6. App 每 10 秒检测一次，发现更高优先级的 WiFi 时自动发起连接
7. ⚠️ **系统会弹出"加入网络"对话框，需要手动点"加入"**

---

## 踩坑记录

### ❌ 坑 1：onChange API 版本错误

**现象**：构建失败，exit code 65  
**原因**：使用了 iOS 17+ 的 `onChange(of:) { _, newValue in }` 双参数语法，但目标系统 iOS 18 用 Xcode 新版本编译时依旧报错  
**修复**：改用单参数 `onChange(of:) { newValue in }`

### ❌ 坑 2：removeAllConfigurations() 不存在

**现象**：编译错误 `value of type 'NEHotspotConfigurationManager' has no member 'removeAllConfigurations'`  
**原因**：这个 API 不存在，是我凭印象写的  
**修复**：直接删掉该方法（App 内也未使用）

### ❌ 坑 3：GitHub 连接失败

**现象**：push 时报 `Failed to connect to github.com port 443`  
**原因**：国内访问 GitHub 不稳定/被墙  
**修复**：配置 git 代理 `git config --global http.proxy http://127.0.0.1:7890`

### ❌ 坑 4：Sideloadly 报 Guru Meditation

**现象**：`Guru Meditation f6b5043 invalid file`  
**原因**：`CODE_SIGNING_ALLOWED=NO` 构建出的 IPA 完全没有签名，Sideloadly 无法处理  
**第一次修复**：改用 `CODE_SIGN_IDENTITY="-"`（ad-hoc 签名）  
**❌ 坑 4.1**：iOS 26.5 SDK 禁止了 ad-hoc 签名，报 `Ad Hoc code signing is not allowed with SDK 'iOS 26.5'`  
**最终修复**：构建时完全禁止签名 + 用 `ldid` 工具打上伪签名，Sideloadly 接手后再用自己的证书重签

### ❌ 坑 5：分支名不一致

**现象**：`error: src refspec main does not match any`  
**原因**：GitHub 新建仓库默认分支是 `main`，本地是 `master`  
**修复**：`git branch -M main`

### ❌ 坑 6：GitHub Actions 的 Homebrew 警告

**现象**：`The following taps are not trusted: aws/tap azure/bicep`  
**影响**：不影响构建，只是 Homebrew 的安全警告  
**忽略**：不用管

---

## 技术限制（非越狱版）

| 限制 | 说明 |
|------|------|
| 切换需手动确认 | 每次连接 WiFi 都会弹出系统对话框，无法绕过 |
| 无法读信号强度 | iOS 未公开 RSSI API，无法根据信号强弱触发切换 |
| 无法扫描网络 | 需要特殊 entitlement（NEHotspotHelper），普通开发者拿不到 |
| 后台运行有限 | iOS 会在 3 分钟左右暂停 App 后台活动 |
| 7 天过期 | 免费 Apple ID 签名的 App 7 天后失效，需用 Sideloadly 续签 |

---

## 越狱版可选

如果需要**完全自动切换（无弹窗）+ 读取 RSSI + 后台常驻**，只能走越狱路线。
代码需使用 `MobileWiFi` 私有框架 + `SBWiFiManager`，用 Theos 工具链开发。
