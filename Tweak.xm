//
//  Tweak.xm
//  SileoBrowserPicker
//
//  Intercept Sileo's ASWebAuthenticationSession payment auth flow
//  and redirect to a user-selected third-party browser.
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ===== Version =====
#define SBP_VERSION @"1.0.2"

// ===== Preferences =====
#define PREFS_PATH @"/var/mobile/Library/Preferences/com.mosheng.sileobrowserpicker.plist"
#define kEnabled   @"enabled"
#define kMode      @"browserMode"

// Browser modes
#define SBP_DISABLED           0
#define SBP_SAFARI_DEFAULT     1
#define SBP_SAFARI_EPHEMERAL   2
#define SBP_ALOOK              3
#define SBP_CHROME             4
#define SBP_QUARK              5
#define SBP_ASK                6

// ASWebAuthenticationSessionError.canceledLogin = 10
#define SBP_CANCEL_CODE 10
#define SBP_ERROR_DOMAIN @"ASWebAuthenticationSessionErrorDomain"

// ===== Class declaration for compiler =====
@interface ASWebAuthenticationSession : NSObject
- (instancetype)initWithURL:(NSURL *)URL
        callbackURLScheme:(NSString *)callbackURLScheme
       completionHandler:(void (^)(NSURL *, NSError *))completionHandler;
- (BOOL)start;
@property (nonatomic) BOOL prefersEphemeralWebBrowserSession;
@property (nonatomic, weak) id presentationContextProvider;
@end

// ===== Pending auth state =====
static NSURL   *s_pendingURL    = nil;
static NSString *s_pendingScheme = nil;
static void (^s_pendingHandler)(NSURL *, NSError *) = nil;
static BOOL    s_hasPending     = NO;

// ===== Auto-cancel observer =====
static id s_activeObserver = nil;

// ===== Delegate swizzle =====
static BOOL s_delegateSwizzled = NO;
static IMP  s_orig_openURL     = NULL;

// ===== Bypass flag (for creating new session internally) =====
static BOOL s_bypassHook = NO;

// ===== Helpers =====

static BOOL sbpEnabled(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
    NSNumber *en = d[kEnabled];
    return en ? en.boolValue : YES;
}

static NSInteger sbpMode(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];
    NSNumber *m = d[kMode];
    return m ? m.integerValue : SBP_ASK;
}

static void cleanupPending(void) {
    s_pendingURL    = nil;
    s_pendingScheme = nil;
    s_pendingHandler = nil;
    s_hasPending    = NO;
    if (s_activeObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:s_activeObserver];
        s_activeObserver = nil;
    }
}

static void cancelPendingAuth(void) {
    if (!s_hasPending) return;
    void (^handler)(NSURL *, NSError *) = s_pendingHandler;
    cleanupPending();
    NSError *err = [NSError errorWithDomain:SBP_ERROR_DOMAIN
                                        code:SBP_CANCEL_CODE
                                    userInfo:nil];
    handler(nil, err);
}

// Open auth URL in a third-party browser
static void openInBrowser(NSURL *authURL, NSInteger mode) {
    NSString *urlStr = authURL.absoluteString;
    NSURL *openURL = nil;

    switch (mode) {
        case SBP_ALOOK:
            // Alook: Alook://<fullurl>
            openURL = [NSURL URLWithString:[NSString stringWithFormat:@"Alook://%@", urlStr]];
            break;
        case SBP_CHROME: {
            // Chrome: replace https:// -> googlechromes://, http:// -> googlechrome://
            NSString *chrome = [urlStr stringByReplacingOccurrencesOfString:@"https://"
                                                                  withString:@"googlechromes://"];
            chrome = [chrome stringByReplacingOccurrencesOfString:@"http://"
                                                       withString:@"googlechrome://"];
            openURL = [NSURL URLWithString:chrome];
            break;
        }
        case SBP_QUARK: {
            // Quark: quark://web?target=<percent-encoded>
            NSString *encoded = [urlStr stringByAddingPercentEncodingWithAllowedCharacters:
                                 [NSCharacterSet URLQueryAllowedCharacterSet]];
            openURL = [NSURL URLWithString:[NSString stringWithFormat:@"quark://web?target=%@", encoded]];
            break;
        }
    }

    if (openURL) {
        // Use openURL:options:completionHandler: (bypasses canOpenURL restriction)
        [[UIApplication sharedApplication] openURL:openURL
                                           options:@{}
                                 completionHandler:nil];
    }
}

// Get the active window (iOS 13+ UIScene compatible)
static UIWindow *sbpActiveWindow(void) {
    for (UIScene *scene in [UIApplication.sharedApplication connectedScenes]) {
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                for (UIWindow *w in ws.windows) {
                    if (w.isKeyWindow) return w;
                }
                if (ws.windows.count > 0) return ws.windows.firstObject;
            }
        }
    }
    return nil;
}

// Present a view controller safely
static void sbpPresent(UIAlertController *alert) {
    UIWindow *win = sbpActiveWindow();
    if (!win) {
        // Fallback: create a temporary window
        win = [[UIWindow alloc] initWithFrame:[UIScreen.mainScreen bounds]];
        win.windowLevel = UIWindowLevelAlert;
        [win makeKeyAndVisible];
    }
    UIViewController *vc = win.rootViewController;
    if (!vc) {
        // No root VC — create a transparent host
        vc = [[UIViewController alloc] init];
        win.rootViewController = vc;
    }
    while (vc.presentedViewController) {
        vc = vc.presentedViewController;
    }
    [vc presentViewController:alert animated:YES completion:nil];
}

// Show browser picker action sheet
static void showBrowserPicker(NSURL *authURL) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"选择浏览器"
                             message:@"选择用于登录付款服务的浏览器"
                      preferredStyle:UIAlertControllerStyleActionSheet];

        [alert addAction:[UIAlertAction actionWithTitle:@"Alook"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *a) {
            openInBrowser(authURL, SBP_ALOOK);
        }]];

        [alert addAction:[UIAlertAction actionWithTitle:@"Chrome"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *a) {
            openInBrowser(authURL, SBP_CHROME);
        }]];

        [alert addAction:[UIAlertAction actionWithTitle:@"夸克"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *a) {
            openInBrowser(authURL, SBP_QUARK);
        }]];

        [alert addAction:[UIAlertAction actionWithTitle:@"Safari (独立会话)"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *a) {
            // Re-create session with ephemeral flag and start natively
            if (s_hasPending && s_pendingURL && s_pendingHandler) {
                s_bypassHook = YES;
                ASWebAuthenticationSession *newSession =
                    [[ASWebAuthenticationSession alloc] initWithURL:s_pendingURL
                                               callbackURLScheme:s_pendingScheme
                                              completionHandler:s_pendingHandler];
                newSession.prefersEphemeralWebBrowserSession = YES;
                [newSession start];
                s_bypassHook = NO;
                // Clear our pending state — the native session handles the callback
                cleanupPending();
            }
        }]];

        [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                                   style:UIAlertActionStyleCancel
                                                 handler:^(UIAlertAction *a) {
            cancelPendingAuth();
        }]];

        sbpPresent(alert);
    });
}

// Setup auto-cancel: if user returns to Sileo without completing auth
static void setupAutoCancel(void) {
    __block id observer = nil;
    observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        // Delay 1.2s to allow callback URL processing
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (s_hasPending) {
                cancelPendingAuth();
            }
        });
    }];
    s_activeObserver = observer;
}

// ===== Swizzled application:openURL:options: =====
static BOOL swizzled_openURL_impl(id self, SEL _cmd,
                                  UIApplication *application,
                                  NSURL *url,
                                  NSDictionary *options) {
    if (s_hasPending && [url.scheme isEqualToString:@"sileo"]) {
        NSString *host = url.host;
        if ([host isEqualToString:@"authentication_success"] ||
            [host isEqualToString:@"payment_completed"]) {
            // Capture the handler before cleanup
            void (^handler)(NSURL *, NSError *) = s_pendingHandler;
            cleanupPending();

            // Call the stored completion handler with the callback URL
            handler(url, nil);
            return YES;
        }
    }

    // Call original implementation
    if (s_orig_openURL) {
        return ((BOOL(*)(id, SEL, UIApplication *, NSURL *, NSDictionary *))
                s_orig_openURL)(self, _cmd, application, url, options);
    }
    return NO;
}

// ===== Hooks =====

%group ASWebAuthHooks

%hook ASWebAuthenticationSession

- (instancetype)initWithURL:(NSURL *)url
        callbackURLScheme:(NSString *)scheme
       completionHandler:(void (^)(NSURL *, NSError *))handler {
    ASWebAuthenticationSession *ret = %orig;

    if (!s_bypassHook && url && scheme && [scheme isEqualToString:@"sileo"]) {
        // Store pending auth info
        s_pendingURL     = [url copy];
        s_pendingScheme  = [scheme copy];
        s_pendingHandler = [handler copy];
        s_hasPending     = YES;
    }

    return ret;
}

- (BOOL)start {
    // Bypass: internal session creation (e.g. Safari ephemeral from picker)
    if (s_bypassHook) {
        return %orig;
    }

    // Not intercepting or plugin disabled
    if (!s_hasPending || !sbpEnabled()) {
        return %orig;
    }

    NSInteger mode = sbpMode();

    switch (mode) {
        case SBP_DISABLED:
        case SBP_SAFARI_DEFAULT:
            // Native behavior
            return %orig;

        case SBP_SAFARI_EPHEMERAL:
            // Set ephemeral flag then start natively
            self.prefersEphemeralWebBrowserSession = YES;
            return %orig;

        case SBP_ALOOK:
        case SBP_CHROME:
        case SBP_QUARK:
            // Redirect to external browser
            openInBrowser(s_pendingURL, mode);
            setupAutoCancel();
            return YES;  // Pretend session started

        case SBP_ASK:
            // Show picker
            showBrowserPicker(s_pendingURL);
            setupAutoCancel();
            return YES;

        default:
            return %orig;
    }
}

%end // %hook ASWebAuthenticationSession

%end // %group ASWebAuthHooks

%group AppDelegateHooks

%hook UIApplication

- (void)setDelegate:(id<UIApplicationDelegate>)delegate {
    %orig;

    if (delegate && !s_delegateSwizzled) {
        Class dc = object_getClass(delegate);
        SEL sel = @selector(application:openURL:options:);
        Method m = class_getInstanceMethod(dc, sel);

        if (m) {
            const char *types = method_getTypeEncoding(m);

            // Store original IMP
            s_orig_openURL = method_getImplementation(m);

            // Try to add method (for classes that inherit the method)
            // If add fails, the class already implements it — replace IMP
            if (!class_addMethod(dc, sel, (IMP)swizzled_openURL_impl, types)) {
                method_setImplementation(m, (IMP)swizzled_openURL_impl);
            }
        }

        s_delegateSwizzled = YES;
    }
}

%end // %hook UIApplication

%end // %group AppDelegateHooks

// ===== Constructor =====
%ctor {
    %init(ASWebAuthHooks);
    %init(AppDelegateHooks);

    NSLog(@"[SileoBrowserPicker] v%@ loaded", SBP_VERSION);
}
