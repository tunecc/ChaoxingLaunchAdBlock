#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

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
