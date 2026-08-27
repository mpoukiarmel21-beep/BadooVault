#import "IVFloatingButton.h"
#import "IVPanelVC.h"
#import "IVTheme.h"

#pragma mark - Passthrough overlay window

/// A tiny window that floats the button. Touches on padding (outside the button
/// container) pass through to the host app; only the button itself is live.
@interface IVOverlayWindow : UIWindow
@property (nonatomic, weak) UIView *liveView;
@end

@implementation IVOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (self.liveView && (hit == self.liveView || [hit isDescendantOfView:self.liveView])) return hit;
    return nil;   // pass through to the app
}
@end

#pragma mark - Dedicated presentation window (hosts the panel)

// Presenting the panel on the HOST app's "top" view controller proved fragile:
// when that controller was busy (already presenting, mid-transition, or owned by
// a lingering system alert) UIKit silently DROPPED the request and the tap did
// nothing — the "rien ne se passe" report. We present on our OWN full-screen
// window instead: always available, never owned by Badoo, so a tap ALWAYS opens
// the menu regardless of what the host is doing.
@interface IVPresentationWindow : UIWindow
@end
@implementation IVPresentationWindow
@end

// The foreground-active window scene, or nil if the app UI isn't up yet.
static UIWindowScene *IVActiveWindowScene(void) {
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]] &&
            s.activationState == UISceneActivationStateForegroundActive) {
            return (UIWindowScene *)s;
        }
    }
    return nil;
}

#pragma mark - Floating button

static NSString *const kIVBtnCenterKey = @"IVFloatingButtonCenter";
static const CGFloat kIVButtonSize = 60.0;
static const CGFloat kIVPad = 18.0;   // shadow padding around the button

@interface IVFloatingButton () <UIAdaptivePresentationControllerDelegate>
@property (nonatomic, strong) IVOverlayWindow *window;
@property (nonatomic, strong) UIView *container;      // button container (live area)
@property (nonatomic, strong) UIViewController *presentedNav;   // guard double-present
@property (nonatomic, strong) IVPresentationWindow *presWindow; // our own presentation window
@end

@implementation IVFloatingButton

+ (instancetype)shared {
    static IVFloatingButton *i;
    static dispatch_once_t o;
    dispatch_once(&o, ^{ i = [self new]; });
    return i;
}

- (void)show {
    if (self.window) { self.window.hidden = NO; return; }

    // Require a foreground window scene BEFORE creating anything. If we built the
    // window without one (e.g. the 2.5s fallback fired before the UI came up),
    // it would never attach to a scene AND self.window would be set — so every
    // later DidBecomeActive would hit the early-return above and the button would
    // never appear. Bail instead and let the next activation retry.
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]] &&
            s.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)s; break;
        }
    }
    if (!scene) return;

    CGFloat dim = kIVButtonSize + kIVPad * 2;
    IVOverlayWindow *w = [[IVOverlayWindow alloc] initWithFrame:CGRectMake(0, 0, dim, dim)];
    w.windowLevel = UIWindowLevelAlert + 1;
    w.backgroundColor = UIColor.clearColor;
    w.windowScene = scene;
    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = UIColor.clearColor;
    w.rootViewController = root;

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(kIVPad, kIVPad, kIVButtonSize, kIVButtonSize)];
    // Soft violet glow instead of a flat black drop shadow — reads as a premium
    // floating control rather than a plain circle.
    container.layer.shadowColor = IVTheme.accentDeep.CGColor;
    container.layer.shadowOpacity = 0.45;
    container.layer.shadowRadius = 12.0;
    container.layer.shadowOffset = CGSizeMake(0, 6);
    // Explicit circular shadow path: without it the layer derives a rectangular
    // shadow from the (square) bounds, so a round button casts a square shadow.
    container.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:container.bounds
                                                           cornerRadius:kIVButtonSize / 2.0].CGPath;

    // Solid violet gradient disc. The old UIGlassEffect background rendered
    // near-clear / white on some builds (the "tout blanc" report) and its size
    // was ambiguous (IVGlass returns an autolayout view, but here we position by
    // frame). A CAGradientLayer disc is deterministic — it always paints the
    // brand violet, so the button reads as a designed control on any background.
    UIView *disc = [[UIView alloc] initWithFrame:container.bounds];
    disc.userInteractionEnabled = NO;                 // the button on top gets the tap
    disc.backgroundColor = IVTheme.accent;            // fallback if the layers fail
    disc.layer.cornerRadius = kIVButtonSize / 2.0;
    disc.layer.cornerCurve = kCACornerCurveContinuous;
    disc.clipsToBounds = YES;
    disc.layer.borderWidth = 1.0;                     // crisp hairline edge over busy content
    disc.layer.borderColor = IVTheme.hairline.CGColor;
    disc.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    // Diagonal accent → accentDeep fill gives the disc depth.
    CAGradientLayer *fill = [CAGradientLayer layer];
    fill.frame = disc.bounds;
    fill.colors = @[(id)IVTheme.accent.CGColor, (id)IVTheme.accentDeep.CGColor];
    fill.startPoint = CGPointMake(0.15, 0.0);
    fill.endPoint = CGPointMake(0.85, 1.0);
    fill.cornerRadius = kIVButtonSize / 2.0;
    [disc.layer addSublayer:fill];

    // Top specular gloss so the disc reads as a raised, glassy control.
    CAGradientLayer *gloss = [CAGradientLayer layer];
    gloss.frame = CGRectMake(0, 0, container.bounds.size.width, container.bounds.size.height * 0.55);
    gloss.colors = @[(id)[UIColor colorWithWhite:1.0 alpha:0.38].CGColor,
                     (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor];
    gloss.startPoint = CGPointMake(0.5, 0.0);
    gloss.endPoint = CGPointMake(0.5, 1.0);
    [disc.layer addSublayer:gloss];

    [container addSubview:disc];

    // The real interactive layer: a UIButton reliably turns a stationary touch
    // into an action while coexisting with the drag pan on the container.
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = container.bounds;
    btn.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightSemibold];
    UIImage *icon = [[UIImage systemImageNamed:@"square.stack.3d.up.fill" withConfiguration:cfg]
                        imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [btn setImage:icon forState:UIControlStateNormal];
    btn.tintColor = UIColor.whiteColor;
    btn.adjustsImageWhenHighlighted = NO;
    [btn addTarget:self action:@selector(onTap) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:btn];

    // VoiceOver: expose the button as a single, labelled control.
    btn.isAccessibilityElement = YES;
    btn.accessibilityLabel = @"Badooscale";
    btn.accessibilityHint = @"Ouvre la gestion des conteneurs";

    [container addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)]];

    [root.view addSubview:container];
    w.liveView = container;
    self.window = w;
    self.container = container;

    w.hidden = NO;
    [self restorePosition];
}

- (void)hide { self.window.hidden = YES; }

#pragma mark - Drag / snap / persist

- (CGRect)screenBounds {
    return self.window.screen.bounds.size.width > 0 ? self.window.screen.bounds : UIScreen.mainScreen.bounds;
}

// The overlay window is only ~90pt wide, so its OWN safeAreaInsets are ~0 — it
// doesn't span the notch or the home indicator. Read the host app's key window
// insets instead so we clamp consistently below the notch and above the home
// indicator. Falls back to typical modern-iPhone insets if none is found.
- (UIEdgeInsets)screenSafeInsets {
    UIWindowScene *scene = (UIWindowScene *)self.window.windowScene;
    if ([scene isKindOfClass:[UIWindowScene class]]) {
        for (UIWindow *w in scene.windows) {
            if (w != self.window &&
                !UIEdgeInsetsEqualToEdgeInsets(w.safeAreaInsets, UIEdgeInsetsZero)) {
                return w.safeAreaInsets;
            }
        }
    }
    return UIEdgeInsetsMake(44.0, 0.0, 34.0, 0.0);
}

// Snap horizontally to the nearer edge and clamp vertically inside the safe
// area. Shared by drag-end and restore so both agree on the same bounds.
- (CGPoint)clampedCenter:(CGPoint)c inBounds:(CGRect)b {
    CGFloat half = self.window.bounds.size.width / 2.0;
    UIEdgeInsets safe = [self screenSafeInsets];
    c.x = (c.x < b.size.width / 2.0) ? (half + 4.0) : (b.size.width - half - 4.0);
    CGFloat minY = safe.top + half + 4.0;
    CGFloat maxY = b.size.height - safe.bottom - half - 4.0;
    c.y = MAX(minY, MIN(maxY, c.y));
    return c;
}

- (void)onPan:(UIPanGestureRecognizer *)g {
    CGPoint tr = [g translationInView:g.view];
    CGPoint c = self.window.center;
    c.x += tr.x; c.y += tr.y;
    self.window.center = c;
    [g setTranslation:CGPointZero inView:g.view];
    if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        [self snapToEdgeAndSave];
    }
}

- (void)snapToEdgeAndSave {
    CGRect b = [self screenBounds];
    CGPoint c = [self clampedCenter:self.window.center inBounds:b];
    void (^persist)(void) = ^{
        [NSUserDefaults.standardUserDefaults setObject:NSStringFromCGPoint(c) forKey:kIVBtnCenterKey];
    };
    if (UIAccessibilityIsReduceMotionEnabled()) {
        self.window.center = c;
        persist();
        return;
    }
    [UIView animateWithDuration:0.28 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{ self.window.center = c; }
                     completion:^(BOOL done) { persist(); }];
}

- (void)restorePosition {
    CGRect b = [self screenBounds];
    CGFloat half = self.window.bounds.size.width / 2.0;
    NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:kIVBtnCenterKey];
    CGPoint c = saved ? CGPointFromString(saved)
                      : CGPointMake(b.size.width - half - 4.0, b.size.height * 0.72);
    self.window.center = [self clampedCenter:c inBounds:b];
}

#pragma mark - Tap → panel

- (void)onTap {
    // Already showing the panel? Ignore (avoids double-present).
    if (self.presWindow || (self.presentedNav && self.presentedNav.presentingViewController)) return;

    // We host the panel on our OWN full-screen window, so all we need is a
    // foreground-active scene to attach it to. Presenting on Badoo's "top" view
    // controller proved fragile: when that controller was busy (mid-transition,
    // owning a lingering alert, already presenting) UIKit SILENTLY dropped the
    // request and the tap did nothing — the "rien ne se passe" report. A window
    // we own is never busy, so a tap ALWAYS opens the menu. If the UI isn't up
    // yet, bail with the button still visible; the next tap retries.
    UIWindowScene *scene = IVActiveWindowScene();
    if (!scene) return;

    // Press feedback (skipped under Reduce Motion).
    if (!UIAccessibilityIsReduceMotionEnabled()) {
        [UIView animateWithDuration:0.08 animations:^{
            self.container.transform = CGAffineTransformMakeScale(0.9, 0.9);
        } completion:^(BOOL d) {
            [UIView animateWithDuration:0.12 animations:^{ self.container.transform = CGAffineTransformIdentity; }];
        }];
    }

    // Full-screen transparent window that we own. It sits just above the app's
    // normal content and below our button window, and hosts the page-sheet
    // presentation.
    IVPresentationWindow *pw = [[IVPresentationWindow alloc] initWithWindowScene:scene];
    // initWithWindowScene: does NOT size the window — it comes up at CGRectZero,
    // so makeKeyAndVisible shows a 0x0 window and the page sheet presented from
    // its rootVC has no room to draw. The present completion still fires, so the
    // button hid itself while no menu was ever visible: the exact "le bouton
    // disparaît" (dead tap) bug. Give it the scene's full bounds explicitly.
    CGRect pwFrame = scene.coordinateSpace.bounds;
    if (CGRectIsEmpty(pwFrame)) pwFrame = UIScreen.mainScreen.bounds;
    pw.frame = pwFrame;
    pw.windowLevel = UIWindowLevelNormal + 3;
    pw.backgroundColor = UIColor.clearColor;
    UIViewController *host = [UIViewController new];
    host.view.backgroundColor = UIColor.clearColor;
    pw.rootViewController = host;
    [pw makeKeyAndVisible];
    self.presWindow = pw;

    IVPanelVC *panel = [IVPanelVC new];
    __weak typeof(self) ws = self;
    panel.onClose = ^{ [ws teardownPresentation]; };   // restore the button when the menu closes

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:panel];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    nav.presentationController.delegate = self;   // backup re-show on swipe-dismiss
    self.presentedNav = nav;

    // Hide the button only once the sheet is actually on screen (in the present
    // completion). If the present were ever a no-op, the button window is never
    // stranded hidden behind a menu that isn't there.
    [host presentViewController:nav animated:YES completion:^{
        ws.window.hidden = YES;
    }];
}

// Idempotent: bring the button back, clear the presentation guard, and tear
// down our presentation window. Called from the panel's onClose (Close button)
// and the presentation delegate (swipe), so the button always returns and the
// window is never left holding key/visible state behind a dismissed menu.
- (void)teardownPresentation {
    self.window.hidden = NO;
    self.presentedNav = nil;
    self.presWindow.hidden = YES;
    self.presWindow.rootViewController = nil;
    self.presWindow = nil;
}

#pragma mark - UIAdaptivePresentationControllerDelegate

- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
    [self teardownPresentation];
}

@end
