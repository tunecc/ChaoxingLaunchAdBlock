# 更新日志

本项目所有值得注意的变更都将记录在此文件中。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/),版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

- (暂无)

## [0.0.3] - 2026-10-19

### 修复

- **首次运行 / 隐私同意时的启动死锁(iOS 16,UMCommon 7.3.5)。** 在隐私政策弹窗点击*同意*后——以及清数据前的每一次冷启动——应用都会冻结在开屏界面,随后被 watchdog 杀死(`0x8BADF00D`,scene-create / scene-update)。根本原因:本地没有 OpenUDID 缓存时,`+[UMOpenUDID valueWithError:]` 会同步扫描并写入 100 个自定义 `UIPasteboard`;与此同时主线程正在等待友盟后台队列持有的 `+[UMEnvelopeBuild sharedInstance]` 的同一个 `dispatch_once`。写入 pasteboard 触发的变更通知又需要在一个已被占死的队列上完成,once 永远无法结束。本插件现 hook `+[UMOpenUDID value]` / `+valueWithError:`,改由 `NSUserDefaults` 提供稳定的 OpenUDID(优先复用已有值;没有则生成格式兼容的 UUID+MD5 标识,持久化在 `CXOpenUDID` 键下),使友盟初始化路径不再产生任何 pasteboard I/O。

### 变更

- 构建环境指向 `/opt/theos`(原先写死的 Theos 路径已不存在)。
- `control` 的 Debian `Architecture` 回归上游默认值 `iphoneos-arm`;rootless / roothide 的 scheme 模块会在构建时按产物线自动覆写。

### 新增

- 统一打包入口 `scripts/build_packages.sh`,对齐 rootful / rootless / roothide 打包规范:
  - 原生 scheme 构建(rootful 构建时显式清空 `THEOS_PACKAGE_SCHEME`,rootless / roothide 各自使用原生 scheme)
  - 构建锁;每个 scheme 的 package 输出目录先清空再构建
  - 产物统一收敛到 `out/`,命名为 `<名称>_<版本>_<scheme>_<短架构>.deb`
  - `dpkg-deb` 包头核对、安装根语义检查(仅 rootless 允许 `var/jb`)
  - 宿主元数据清理(`.DS_Store`、`._*`、`__MACOSX`)
  - 包内权限规范化(644/755)——修复过滤器 plist 以 `600` 权限进包、可能导致插件不注入的问题

### 已验证

- 真机安装(roothide):dylib 正常注入 `ChaoXingStudy`,隐私同意后可正常进入,不再出现开屏卡死或 watchdog 杀进程。

### 备注

- 可与 `Chaoxing630MultiOpenBypass` 同时安装;两者 hook 目标零交集(多开插件覆盖 `UTDIDOpenUDID` / `GainUUID` / 设备标识伪装,本修复只接管友盟自带的 `UMOpenUDID`)。

## [0.0.2] - 2026-04-11

### 新增

- 拦截自研开屏广告配置接口:`home-yd.chaoxing.com/apis/data/getAdsRecommend` 与 `home-yd.chaoxing.com/apis/banner/getConfigInfoForClient?incode=client`(hook `NSURLSession` 与老的 `NSURLConnection`)。
- 展示层兜底:压制 `-[UMPLaunchMessage displayLaunchAD]`、`-[AppDelegate createadWindowWithImage:WithDurationTime:]`、`-[AppDelegate gotoADViewController]`、`-[AppDelegate IsGoToADViewController]`。

### 修复

- 0.0.1 中多次启动后开屏广告仍会复现的问题;现在两条广告链路均已覆盖。

## [0.0.1] - 2026-04-08

### 新增

- 首个版本:通过 `NSURLSession` 拦截友盟 UMP 开屏广告请求(`/admsg/v2/launch`),并压制 `-[UMPLaunchMessage displayLaunchAD]`。

### 已知问题

- 多次重启后广告仍可能复现(自研广告链路尚未覆盖)。

[未发布]: https://github.com/tunecc/ChaoxingLaunchAdBlock/compare/0.0.3...HEAD
[0.0.3]: https://github.com/tunecc/ChaoxingLaunchAdBlock/compare/0.0.2...0.0.3
[0.0.2]: https://github.com/tunecc/ChaoxingLaunchAdBlock/compare/0.0.1...0.0.2
[0.0.1]: https://github.com/tunecc/ChaoxingLaunchAdBlock/releases/tag/0.0.1
