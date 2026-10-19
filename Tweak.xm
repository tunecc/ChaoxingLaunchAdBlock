#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>

#pragma mark - UM OpenUDID deadlock bypass

// UMCommon 7.3.5 的 +[UMOpenUDID valueWithError:] 在全新安装时会同步扫描并写 100 个
// 自定义 UIPasteboard(iOS 16 上写入会同步派发 pasteboard-change 观察者操作)。
// 当友盟后台线程先抢到 UMEnvelopeBuild 的 dispatch_once、主线程又在
// +[UMessage startWithAppkey:] 处等待同一个 once 时,写 pasteboard 触发的
// 通知等待会形成死锁,watchdog 杀进程 —— 表现为隐私弹窗点同意后冻结/卡开屏。
// 这里绕过 pasteboard,改用 NSUserDefaults 持久化一份格式兼容的 OpenUDID。
static NSString *CXStableOpenUDID(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;

    // 优先复用原有 OpenUDID,保持卸载插件后身份连续
    id existing = [defaults objectForKey:@"OpenUDID"];
    if ([existing isKindOfClass:[NSDictionary class]]) {
        NSString *value = [existing objectForKey:@"OpenUDID"];
        if ([value isKindOfClass:[NSString class]] && value.length > 0) {
            return value;
        }
    }

    static NSString *generated;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *openUDID = [defaults stringForKey:@"CXOpenUDID"];
        if (openUDID.length == 0) {
            // 与 UMOpenUDID _generateFreshOpenUDID 相同的格式:UUID → MD5 hex + 随机尾
            NSString *uuid = [NSUUID UUID].UUIDString.lowercaseString;
            unsigned char md[CC_MD5_DIGEST_LENGTH];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            CC_MD5(uuid.UTF8String, (CC_LONG)uuid.length, md);
#pragma clang diagnostic pop
            NSMutableString *hex = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
            for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
                [hex appendFormat:@"%02x", md[i]];
            }
            openUDID = [hex stringByAppendingFormat:@"%08lx", (unsigned long)arc4random()];
        }
        if (openUDID.length > 0) {
            [defaults setObject:openUDID forKey:@"CXOpenUDID"];
            [defaults setObject:@{ @"OpenUDID": openUDID,
                                   @"OpenUDID_appUID": [NSUUID UUID].UUIDString.lowercaseString }
                         forKey:@"OpenUDID"];
        }
        generated = openUDID;
    });
    return generated;
}

static BOOL CXShouldBlockLaunchAdRequest(NSURLRequest *request) {
    if (!request) {
        return NO;
    }

    NSURL *url = request.URL;
    if (!url) {
        return NO;
    }

    NSString *absoluteString = url.absoluteString;
    if (absoluteString.length == 0) {
        return NO;
    }

    static NSArray<NSString *> *blockedPatterns;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        blockedPatterns = @[
            @"/admsg/v2/launch",
            @"home-yd.chaoxing.com/apis/data/getAdsRecommend",
            @"home-yd.chaoxing.com/apis/banner/getConfigInfoForClient?incode=client",
        ];
    });

    for (NSString *pattern in blockedPatterns) {
        if ([absoluteString containsString:pattern]) {
            return YES;
        }
    }

    return NO;
}

static void CXLogBlockedRequest(NSString *prefix, NSURLRequest *request) {
    @try {
        NSString *urlString = request.URL.absoluteString ?: @"<nil>";
        NSLog(@"[ChaoxingLaunchAdBlock] %@ %@", prefix, urlString);
    } @catch (__unused NSException *exception) {
    }
}

static void CXClearResponseAndError(NSURLResponse * _Nullable __autoreleasing *response,
                                    NSError * _Nullable __autoreleasing *error) {
    if (response) {
        *response = nil;
    }
    if (error) {
        *error = nil;
    }
}

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    if (CXShouldBlockLaunchAdRequest(request)) {
        CXLogBlockedRequest(@"blocked NSURLSession request:", request);
        return nil;
    }

    return %orig;
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    if (CXShouldBlockLaunchAdRequest(request)) {
        CXLogBlockedRequest(@"blocked NSURLSession request:", request);
        if (completionHandler) {
            completionHandler(nil, nil, nil);
        }
        return nil;
    }

    return %orig;
}

%end

%hook NSURLConnection

+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request
                 returningResponse:(NSURLResponse * _Nullable __autoreleasing *)response
                             error:(NSError * _Nullable __autoreleasing *)error {
    if (CXShouldBlockLaunchAdRequest(request)) {
        CXLogBlockedRequest(@"blocked NSURLConnection request:", request);
        CXClearResponseAndError(response, error);
        return nil;
    }

    return %orig;
}

%end

%hook UMPLaunchMessage

- (void)displayLaunchAD {
    NSLog(@"[ChaoxingLaunchAdBlock] suppress UMP launch ad display");
    return;
}

%end

%hook AppDelegate

- (void)createadWindowWithImage:(UIImage *)image WithDurationTime:(id)duration {
    NSLog(@"[ChaoxingLaunchAdBlock] suppress AppDelegate launch ad window");
    return;
}

- (BOOL)IsGoToADViewController {
    return NO;
}

- (void)gotoADViewController {
    NSLog(@"[ChaoxingLaunchAdBlock] suppress launch ad controller jump");
    return;
}

%end

// 友盟 OpenUDID 首次生成走 100 个自定义 UIPasteboard 的同步扫描/写入,
// 在 iOS 16 与 UMEnvelopeBuild 的 dispatch_once 组合下会死锁(见文件头注释)。
// 直接用本地持久化值短路,不再触碰 pasteboard。
%hook UMOpenUDID

+ (NSString *)value {
    NSString *openUDID = CXStableOpenUDID();
    NSLog(@"[ChaoxingLaunchAdBlock] UMOpenUDID value -> %@", openUDID);
    return openUDID;
}

+ (NSString *)valueWithError:(NSError **)error {
    NSString *openUDID = CXStableOpenUDID();
    NSLog(@"[ChaoxingLaunchAdBlock] UMOpenUDID valueWithError -> %@", openUDID);
    return openUDID;
}

%end
