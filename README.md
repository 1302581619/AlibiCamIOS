# AlibiCam iOS（巨魔版）

复刻 [pokedo0/Alibi-Cam](https://github.com/pokedo0/Alibi-Cam) 核心功能的 iOS 版本，用 SwiftUI + AVFoundation 重写，部署目标 iOS 15.0，产物为巨魔（TrollStore）可直接安装的 ipa。

## 已实现功能（对齐原版核心）

- **循环分段录像**：连续采集视频，按 `分段间隔` 切段（AVAssetWriter 无损写盘）
- **滚动窗口**：只保留最近 `保留时长` 的片段，超期自动删除（对应原版 `IntervalRecorderService`）
- **保存导出**：一键把当前循环窗口内所有片段无损拼接成完整录像（不重新编码）
- **画质设置**：720p / 1080p / 4K，帧率 15/24/30/60，码率 1/2/4/6 Mbps
- **摄像头切换**：前置 / 后置
- **防抖（EIS）**：视频稳定开关
- **姿态感知自动停止**：检测到剧烈震动/倾倒自动停止并保留片段（对应原版 `AutoStopSensorTile`）
- **永久删除**：关闭时旧片段移入应用内回收站目录
- **后台保活**：静音音频维持后台运行
- **文件管理**：已保存录像列表、播放、分享导出
- 全部设置用 UserDefaults 持久化（对应原版 `AppSettings`）

## 未移植（iOS 平台无对等能力）

- 双摄同步录像（iOS 的 `AVCaptureMultiCamSession` 仅部分机型支持且无法后台并发，稳定性差）
- 桌面快捷方式 / 通知栏磁贴（iOS 用快捷指令 App 替代，本工程不做）
- GitHub 在线更新（巨魔安装的更新走重新装包）

## 生成 ipa（GitHub 云编译，无需 Mac / 开发者账号）

工程配置好了 GitHub Actions，**你只需要把目录推到自己的 GitHub 仓库，在 Actions 里点一下运行即可**。

### 步骤

1. 在 GitHub 新建一个**公开**仓库（例如 `AlibiCamIOS`）。公开仓库用 macOS runner 不消耗额度；私有仓库会消耗付费分钟。

2. 在本机（`D:/记录仪ipa/AlibiCamIOS` 目录）执行：

   ```bash
   git init
   git add .
   git commit -m "init"
   git remote add origin https://github.com/<你的用户名>/AlibiCamIOS.git
   git push -u origin main
   ```

3. 打开仓库网页 → **Actions** 标签 → 左侧选 **Build AlibiCam TrollStore IPA** → 点 **Run workflow** → 再点绿色按钮 **Run workflow**。

4. 等几分钟（首次约 5-8 分钟）。跑完后有两种拿包方式：
   - **直接下载**：点进这次运行记录，页面底部 **Artifacts** 里的 `AlibiCam-ipa`，下载后解压得到 `AlibiCam-trollstore.ipa`
   - **挂到 Release**（可选）：在第 3 步运行时填入 `release_tag`（如 `v1.0`），会自动把 ipa 传到该 Release

### 编译原理

workflow 用 [`Zeu1s/trollstore-ipa`](https://github.com/Zeu1s/trollstore-ipa) 这个 Action：
- 在 macOS runner 上用 XcodeGen 生成 `.xcodeproj`
- 以 `CODE_SIGNING_ALLOWED=NO` 归档（不需要开发者证书 / 描述文件）
- 用 `ldid` 做 ad-hoc 伪签名并打包成 ipa
- 刻意不加任何平台保留权限，保证巨魔能装

### 常见失败排查

| 现象 | 原因 | 处理 |
|------|------|------|
| `xcodegen: command not found` | brew 未装成功 | 看日志确认 Install XcodeGen 步骤，重跑 |
| Archive 报签名错误 | 版本参数问题 | 确认 `version: 1.0.0`、`build-number: 1` 是纯数字/点分 |
| ipa 装上打不开 | 概率极低 | 确认 iOS 在 14.0–16.6.1 / 17.0 巨魔支持范围内 |

## 安装

1. 把 `AlibiCam-trollstore.ipa` 传到手机（AirDrop / 网盘 / 文件 App）。
2. 在「文件」里长按 ipa → 共享 → 选 **TrollStore** → 安装。
3. 桌面出现 AlibiCam 图标，首次打开允许相机、麦克风权限。

> 你的 iOS 15.6 在巨魔支持范围内（14.0–16.6.1），可直接装。

## 使用

1. 打开进「录制」页，可在设置里先调好画质/时长。
2. 点红色按钮开始循环录像，界面显示录像时长与当前分段数。
3. 录制中随时点「保存」，会把当前窗口内所有片段拼成完整录像，到「录像」页查看/播放/分享。
4. 系统检测剧烈震动会自动停止（需在设置里开启姿态感知）。

## 源码结构

```
AlibiCamIOS/
├── project.yml                       # XcodeGen 工程定义
├── .github/workflows/build.yml       # 云编译工作流
└── AlibiCam/
    ├── AlibiCamApp.swift             # App 入口
    ├── Info.plist                    # 权限声明
    ├── silence.wav                   # 后台保活用静音音频
    ├── Models/
    │   ├── AppState.swift            # 全局状态容器
    │   ├── Settings.swift            # 设置项 + 持久化
    │   └── Segment.swift             # 分段文件管理 / 滚动删除 / 拼接导出
    ├── Camera/
    │   └── RecorderEngine.swift      # 核心录像引擎（采集+分段+保活+姿态）
    └── Views/
        ├── ContentView.swift         # 根 TabView
        ├── RecorderView.swift        # 录制主界面
        ├── CameraPreview.swift       # 相机预览桥接
        ├── SettingsView.swift        # 设置页
        └── SavedFilesView.swift      # 已保存录像 / 播放器
```

## 许可证

基于 GPL v3 开源项目的功能复刻，原作者 Myzel394 / pokedo0。
