## 免责声明

**本项目仅供个人学习、技术研究与逆向分析交流使用，请勿用于任何非法用途或未授权场景。**

为避免歧义，请在使用前明确知悉以下内容：

1. 你应当仅在**合法、授权、自担风险**的前提下查看、编译、研究或测试本项目。

2. 本项目不提供任何商业服务，也不对你基于本项目进行的二次使用、移植、传播或实际部署行为负责。

3. 若你下载、保存、编译或运行了本项目，请在 **24 小时内删除**相关源码、构建产物与衍生文件。

4. 本项目内容仅用于**学习交流**，请支持正版软件与原始版权方的合法权益。

5. 因使用本项目导致的任何直接或间接后果，包括但不限于账号、设备、数据、法律与合规风险，均由使用者自行承担，与项目维护者无关。

   如果你不能接受以上条款，请不要继续浏览、下载、编译或使用本项目。



# ChaoxingLaunchAdBlock

一个针对 `ChaoXingStudy`（学习通 iOS 客户端）启动广告链路的 Theos tweak。

当前实现的思路比较直接：一层拦截启动广告相关请求，另一层直接抑制广告页面展示和跳转，从而尽量避免启动页广告弹出。

## 仓库内容

- `Tweak.xm`：核心 Hook 逻辑
- `Makefile`：Theos 构建脚本，当前配置为 `roothide` 打包
- `control`：Debian 包元数据
- `ChaoxingLaunchAdBlock.plist`：注入配置
- `roothide/`：已构建的 `.deb` 产物

## 简单逆向过程

这个仓库对应的逆向流程，可以概括成下面几步：

### 1. 解包 IPA，拿到主程序

先从 IPA 中解出 `Payload/ChaoXingStudy.app`，确认主程序可执行文件是 `ChaoXingStudy`，再结合 `Info.plist` 确认版本号、包名和平台信息。

### 2. 做静态检索，先找“广告入口”而不是盲扫

对主程序做字符串和符号级检索，优先找：

- 启动广告接口
- 启动广告展示类
- AppDelegate 中与广告窗口、广告跳转相关的方法

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

也就是说，思路不是“猜测广告逻辑”，而是：

1. 先确认广告接口和展示方法真实存在
2. 再同时卡住“请求”与“展示”两个方向
3. 保持改动尽量小，避免把无关启动流程也一并打断

## 当前实现说明

`Tweak.xm` 目前做了这些事情：

### 1. 按 URL 关键字拦截广告请求

默认拦截的模式：

- `/admsg/v2/launch`
- `home-yd.chaoxing.com/apis/data/getAdsRecommend`
- `home-yd.chaoxing.com/apis/banner/getConfigInfoForClient?incode=client`

### 2. 抑制广告展示逻辑

直接 Hook 并短路以下逻辑：

- `-[UMPLaunchMessage displayLaunchAD]`
- `-[AppDelegate createadWindowWithImage:WithDurationTime:]`
- `-[AppDelegate gotoADViewController]`
- `-[AppDelegate IsGoToADViewController]`

## 构建说明

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

### 构建命令

```bash
cd ChaoxingLaunchAdBlock
make package
```

当前默认：

- 注入进程：`ChaoXingStudy`
- 打包方案：`roothide`
- 包名：`com.tune.chaoxinglaunchadblock`

## 适用范围与限制

- 已验证到的样本是 `6.2.9` 和 `6.7.4` 
- 如果学习通后续版本调整了广告接口、类名、方法名或启动链路，需要重新做字符串检索和 Hook 点确认
- 这个 tweak 只处理当前已识别的启动广告链路，不保证覆盖所有弹窗、活动页或后续新增广告模块

