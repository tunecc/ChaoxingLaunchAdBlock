## 免责声明

**本项目仅供个人学习、技术研究与逆向分析交流使用，请勿用于任何非法用途或未授权场景。**

为避免歧义，请在使用前明确知悉以下内容：

1. 你应当仅在**合法、授权、自担风险**的前提下查看、编译、研究或测试本项目。
2. 本项目不提供任何商业服务，也不对你基于本项目进行的二次使用、移植、传播或实际部署行为负责。
3. 若你下载、保存、编译或运行了本项目，请在 **24 小时内删除**相关源码、构建产物与衍生文件。
4. 本项目内容仅用于**学习交流**，请支持正版软件与原始版权方的合法权益。
5. 因使用本项目导致的任何直接或间接后果，包括但不限于账号、设备、数据、法律与合规风险，均由使用者自行承担，与项目维护者无关。

如果你不能接受以上条款，请不要继续浏览、下载、编译或使用本项目。

## ChaoxingLaunchAdBlock

在学习通的开屏广告链路里，广告不是单一路径。

第一轮分析只锁定了友盟 `UMP` 开屏链路，拦截 `https://msg.umengcloud.com/admsg/v2/launch` 后，首次安装和前几次启动可能没有广告，但重复打开后广告又会回来。这说明 App 内部还有另一条自研开屏链路。

当前 `0.0.2` 版本已经把两条链路都纳入处理：

- 友盟 `UMP` 开屏拉取：`/admsg/v2/launch`
- 学习通自研开屏配置：
  - `home-yd.chaoxing.com/apis/data/getAdsRecommend`
  - `home-yd.chaoxing.com/apis/banner/getConfigInfoForClient?incode=client`

  同时还在展示层做了兜底，减少缓存或漏网请求导致广告继续显示的概率。

## 当前实现

核心实现文件是 `Tweak.xm`。

当前逻辑分两层：

### 1. 网络层拦截

Hook：

- `NSURLSession`
- `NSURLConnection`

拦截规则：

- `/admsg/v2/launch`
- `home-yd.chaoxing.com/apis/data/getAdsRecommend`
- `home-yd.chaoxing.com/apis/banner/getConfigInfoForClient?incode=client`

### 2. 展示层兜底

Hook：

- `-[UMPLaunchMessage displayLaunchAD]`
- `-[AppDelegate createadWindowWithImage:WithDurationTime:]`
- `-[AppDelegate gotoADViewController]`
- `-[AppDelegate IsGoToADViewController]`

## 仓库内容

主要文件如下：

- `Tweak.xm`：核心 Hook 逻辑
- `Makefile`：Theos 构建脚本，当前默认打包方案是 `roothide`
- `control`：Debian 包元数据，当前版本号是 `0.0.2`
- `ChaoxingLaunchAdBlock.plist`：注入配置，只注入 `com.ssreader.ChaoXingStudy`
- `roothide/`：当前默认打包产物目录
- `rootless/`：已有 rootless 产物目录，但不是当前默认打包方案
- `first.md`：这次逆向和实现思路的补充说明

## 简单逆向过程

这个仓库对应的逆向流程，可以概括成下面几步：

### 1. 解包 IPA，先拿到主程序

先从 IPA 中解出 `Payload/ChaoXingStudy.app`，确认主程序可执行文件是 `ChaoXingStudy`，再结合 `Info.plist` 确认版本号、包名和平台信息。

### 2. 做静态检索，先找广告入口而不是盲扫

对主程序做字符串和符号级检索，优先找：

- 启动广告接口
- 启动广告展示类
- `AppDelegate` 中与广告窗口、广告跳转相关的方法

当前样本里可以直接命中的关键字符串包括：

- `https://home-yd.chaoxing.com/apis/data/getAdsRecommend`
- `https://home-yd.chaoxing.com/apis/banner/getConfigInfoForClient?incode=client`
- `%@/admsg/v2/launch`
- `UMPLaunchMessage`
- `displayLaunchAD`
- `createadWindowWithImage:WithDurationTime:`
- `gotoADViewController`
- `IsGoToADViewController`

这说明启动广告至少分成两层：

- 网络层请求广告配置或广告素材
- UI 层展示广告视图或跳转广告控制器

### 3. 定位最小闭环 Hook 点

当前实现没有做大范围重构，而是选了几个闭环最强的点：

- `NSURLSession`：拦截启动广告相关请求
- `NSURLConnection`：补一层老式同步请求拦截
- `UMPLaunchMessage -displayLaunchAD`：直接压掉广告展示
- `AppDelegate` 里的广告窗口创建与广告跳转方法：阻断广告页出现和跳转

也就是说，思路不是猜测广告逻辑，而是：

1. 先确认广告接口和展示方法真实存在
2. 再同时卡住请求与展示两个方向
3. 保持改动尽量小，避免把无关启动流程也一并打断

## 构建与安装

### 环境要求

- iOS 越狱环境
- Theos
- Logos / MobileSubstrate
- `arm64` / `arm64e`
- 当前 `Makefile` 目标最低系统版本：`iOS 15.0`

### 注意事项

`Makefile` 里写死了本机 Theos 路径：

```make
export THEOS = /Users/tune/Develop/theos-roothide
```

如果你本地路径不同，需要先自行修改。

工程里还额外指定了本地 clang 模块缓存目录，避免构建时写系统缓存失败：

```make
ADDITIONAL_CFLAGS += -fmodules-cache-path=$(THEOS_PROJECT_DIR)/.clang-cache/ModuleCache
```

### 构建命令

在项目根目录运行：

```bash
make clean package
```

当前默认：

- 注入进程：`ChaoXingStudy`
- 打包方案：`roothide`
- 包名：`com.tune.chaoxinglaunchadblock`

当前稳定包输出在：

```bash
roothide/com.tune.chaoxinglaunchadblock_0.0.2_iphoneos-arm64e.deb
```

## 如何验证是否生效

建议这样验证：

1. 安装 `0.0.2`
2. 重启目标 App
3. 冷启动 5 到 10 次
4. 观察是否还出现迟发型开屏广告

如果需要看命中情况，可以观察系统日志中是否出现：

```text
[ChaoxingLaunchAdBlock] blocked NSURLSession request:
[ChaoxingLaunchAdBlock] blocked NSURLConnection request:
[ChaoxingLaunchAdBlock] suppress UMP launch ad display
[ChaoxingLaunchAdBlock] suppress AppDelegate launch ad window
[ChaoxingLaunchAdBlock] suppress launch ad controller jump
```

## 适用范围与限制

- 这个项目当前只针对开屏广告做处理，不等于全 App 去广告。
- 当前仓库文档里记录过的样本版本包括 `6.2.9` 和 `6.7.4`。
- 如果后续版本改了网络层、类名、方法名或广告配置接口，需要重新确认。
- 当前没有把整域全封，目的是尽量避免误伤其他功能。

## 版本说明

### 0.0.1

只覆盖了 `UMP /admsg/v2/launch`，不能稳定去除广告。

### 0.0.2

补齐了：

- `home-yd` 自研配置链路
- `NSURLSession`
- `NSURLConnection`
- 展示层兜底方法

这是当前推荐使用的版本。

## 维护建议

如果后续继续迭代，优先复查这几个点：

- `setupCXLaunchAd`
- `createadWindowWithImage:WithDurationTime:`
- `getLaunchMessageWithPmode:Response:`
- `/admsg/v2/launch`
- `home-yd.chaoxing.com` 相关广告配置接口
