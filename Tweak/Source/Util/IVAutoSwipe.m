#import <UIKit/UIKit.h>
#import "IVAutoSwipe.h"
#import "IVDiagnostics.h"

// Best-effort keyword sets (lowercased substring match over an element's
// accessibilityIdentifier + accessibilityLabel + button title). No Badoo private
// headers exist, so these are heuristics tuned to Badoo's visible/ax strings.
static NSArray<NSString *> *IVLikeKeywords(void)    { return @[@"like", @"yes", @"heart", @"favorite", @"jaime", @"vote_yes"]; }
static NSArray<NSString *> *IVNegKeywords(void)     { return @[@"super", @"dislike", @"pass", @"nope", @"rewind", @"undo", @"back", @"close", @"settings", @"profile", @"filter", @"boost"]; }
static NSArray<NSString *> *IVMatchKeywords(void)   { return @[@"match", @"vous vous plaisez", @"you matched", @"c'est un match", @"it's a match", @"mutual"]; }
static NSArray<NSString *> *IVSendKeywords(void)    { return @[@"send", @"envoyer", @"envoi"]; }
static NSArray<NSString *> *IVContinueKeywords(void){ return @[@"continue", @"continuer", @"keep", @"garder", @"swip", @"later", @"plus tard", @"discuter", @"chat", @"fermer", @"close"]; }

@implementation IVAutoSwipe {
    BOOL _running;
    NSArray<NSString *> *_messages;
    NSInteger _count;      // 0 == unlimited
    double _min, _max;     // seconds
    NSInteger _done;
    NSInteger _gen;        // generation token — bumping it cancels pending ticks
}

+ (instancetype)shared {
    static IVAutoSwipe *i; static dispatch_once_t o;
    dispatch_once(&o, ^{ i = [self new]; });
    return i;
}

- (BOOL)isRunning { return _running; }

- (void)startWithContainer:(IVContainer *)c {
    if (_running || !c) return;
    _messages = c.autoSwipeMessages.count ? [c.autoSwipeMessages copy] : nil;
    _count = c.autoSwipeCount > 0 ? c.autoSwipeCount : 0;
    _min = c.autoSwipeMinDelay >= 1.0 ? c.autoSwipeMinDelay : 1.0;
    _max = c.autoSwipeMaxDelay >= _min ? c.autoSwipeMaxDelay : _min;
    _done = 0;
    _running = YES;
    _gen++;
    IVLog(@"auto-swipe: START cid=%@ count=%ld delay=[%.1f,%.1f] msgs=%lu",
          c.cid, (long)_count, _min, _max, (unsigned long)_messages.count);
    [self scheduleNextTick];   // first tick after a delay: lets the panel dismiss
}

- (void)stop {
    if (!_running) return;
    _running = NO;
    _gen++;
    IVLog(@"auto-swipe: STOP after %ld swipe(s)", (long)_done);
}

#pragma mark - Tick loop

- (double)randomDelay {
    double lo = _min, hi = _max;
    double span = hi - lo;
    double r = span > 0 ? ((double)arc4random_uniform(1000000) / 1000000.0) * span : 0;
    return lo + r;
}

- (void)scheduleNextTick {
    if (!_running) return;
    NSInteger gen = _gen;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([self randomDelay] * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (gen != self->_gen || !self->_running) return;   // stopped/restarted meanwhile
        [self tick];
    });
}

- (void)tick {
    if (!_running) return;
    UIApplication *app = UIApplication.sharedApplication;
    if (app.applicationState != UIApplicationStateActive) {
        [self scheduleNextTick];   // backgrounded — wait, act only when foreground-active
        return;
    }
    UIView *root = [self hostTopViewController].view;
    if (!root) { IVLog(@"auto-swipe: no host view this tick"); [self scheduleNextTick]; return; }

    // A match popup takes priority: handle it (send a phrase / dismiss) before swiping.
    if ([self handleMatchPopupInView:root]) { [self scheduleNextTick]; return; }

    UIControl *like = [self findLikeControlInView:root];
    if (like) {
        [self tapControl:like];
        _done++;
        IVLog(@"auto-swipe: liked (%ld%@)", (long)_done,
              _count > 0 ? [NSString stringWithFormat:@"/%ld", (long)_count] : @"");
        if (_count > 0 && _done >= _count) { IVLog(@"auto-swipe: count reached — stopping"); [self stop]; return; }
    } else {
        IVLog(@"auto-swipe: no like control found this tick");
    }
    [self scheduleNextTick];
}

#pragma mark - Host UI resolution

// The frontmost view controller of Badoo's OWN UI — the highest normal-level,
// visible window of the foreground-active scene, EXCLUDING our floating-button
// overlay (IVOverlayWindow, which sits above UIWindowLevelAlert). Then drill to
// the topmost presented controller so we search whatever is actually on screen.
- (UIViewController *)hostTopViewController {
    UIWindow *best = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        if (scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.hidden || w.alpha < 0.05) continue;
            if ([NSStringFromClass(w.class) containsString:@"IVOverlay"]) continue;  // ours
            if (w.windowLevel > UIWindowLevelNormal + 100) continue;                 // skip alert overlays
            if (!best || w.windowLevel >= best.windowLevel) best = w;
        }
    }
    UIViewController *vc = best.rootViewController;
    while (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed) {
        vc = vc.presentedViewController;
    }
    return vc;
}

#pragma mark - Match popup

// Returns YES if a "match" popup was detected and handled (message sent, or the
// popup dismissed so swiping can resume). NO means no match popup this tick.
- (BOOL)handleMatchPopupInView:(UIView *)root {
    NSMutableArray<UILabel *> *labels = [NSMutableArray new];
    [self collectLabelsIn:root into:labels];
    BOOL isMatch = NO;
    for (UILabel *l in labels) {
        if (l.hidden || l.alpha < 0.05 || !l.text.length) continue;
        if ([self text:l.text.lowercaseString matchesAny:IVMatchKeywords()]) { isMatch = YES; break; }
    }
    if (!isMatch) return NO;
    IVLog(@"auto-swipe: MATCH popup detected");

    if (_messages.count) {
        UIView *field = [self findTextInputIn:root];
        if (field) {
            NSString *phrase = _messages[arc4random_uniform((uint32_t)_messages.count)];
            [field becomeFirstResponder];
            if ([field conformsToProtocol:@protocol(UIKeyInput)]) [(id<UIKeyInput>)field insertText:phrase];
            IVLog(@"auto-swipe: typed match message: %@", phrase);
            UIControl *send = [self findControlInView:root keywords:IVSendKeywords() avoid:nil];
            if (send) { [self tapControl:send]; IVLog(@"auto-swipe: tapped send"); return YES; }
            IVLog(@"auto-swipe: send control not found — message left typed");
            return YES;
        }
        IVLog(@"auto-swipe: no editable text field in match popup");
    }
    // No message configured / no field: dismiss the match so the loop can continue.
    UIControl *cont = [self findControlInView:root keywords:IVContinueKeywords() avoid:nil];
    if (cont) { [self tapControl:cont]; IVLog(@"auto-swipe: dismissed match popup"); }
    return YES;
}

#pragma mark - Control / label search

- (UIControl *)findLikeControlInView:(UIView *)root {
    return [self findControlInView:root keywords:IVLikeKeywords() avoid:IVNegKeywords()];
}

// First visible, enabled, reasonably-sized UIControl whose identity string matches
// any `keywords` and none of `avoid`.
- (UIControl *)findControlInView:(UIView *)root keywords:(NSArray<NSString *> *)keywords avoid:(NSArray<NSString *> *)avoid {
    NSMutableArray<UIControl *> *controls = [NSMutableArray new];
    [self collectControlsIn:root into:controls];
    for (UIControl *ctl in controls) {
        if (ctl.hidden || ctl.alpha < 0.05 || !ctl.isUserInteractionEnabled || !ctl.enabled) continue;
        if (ctl.bounds.size.width < 20 || ctl.bounds.size.height < 20) continue;
        NSString *id = [self identityFor:ctl];
        if (!id.length) continue;
        if (avoid && [self text:id matchesAny:avoid]) continue;
        if ([self text:id matchesAny:keywords]) return ctl;
    }
    return nil;
}

// First visible editable text input (UITextField / editable UITextView).
- (UIView *)findTextInputIn:(UIView *)root {
    if (root.hidden || root.alpha < 0.05) return nil;
    if ([root isKindOfClass:UITextField.class] && ((UITextField *)root).isEnabled) return root;
    if ([root isKindOfClass:UITextView.class] && ((UITextView *)root).isEditable) return root;
    for (UIView *sub in root.subviews) {
        UIView *hit = [self findTextInputIn:sub];
        if (hit) return hit;
    }
    return nil;
}

- (void)tapControl:(UIControl *)ctl {
    [ctl sendActionsForControlEvents:UIControlEventTouchUpInside];
}

#pragma mark - Recursion + string helpers

- (void)collectControlsIn:(UIView *)view into:(NSMutableArray<UIControl *> *)out {
    if (view.hidden || view.alpha < 0.05) return;
    if ([view isKindOfClass:UIControl.class]) [out addObject:(UIControl *)view];
    for (UIView *sub in view.subviews) [self collectControlsIn:sub into:out];
}

- (void)collectLabelsIn:(UIView *)view into:(NSMutableArray<UILabel *> *)out {
    if (view.hidden || view.alpha < 0.05) return;
    if ([view isKindOfClass:UILabel.class]) [out addObject:(UILabel *)view];
    for (UIView *sub in view.subviews) [self collectLabelsIn:sub into:out];
}

// Lowercased haystack for an element: accessibilityIdentifier + accessibilityLabel
// + (button current title). All three because Badoo labels controls inconsistently.
- (NSString *)identityFor:(id)el {
    NSMutableString *s = [NSMutableString new];
    if ([el respondsToSelector:@selector(accessibilityIdentifier)]) {
        NSString *aid = [el accessibilityIdentifier];
        if (aid.length) [s appendFormat:@" %@", aid];
    }
    if ([el respondsToSelector:@selector(accessibilityLabel)]) {
        NSString *al = [el accessibilityLabel];
        if (al.length) [s appendFormat:@" %@", al];
    }
    if ([el isKindOfClass:UIButton.class]) {
        NSString *t = [(UIButton *)el currentTitle];
        if (t.length) [s appendFormat:@" %@", t];
    }
    return s.lowercaseString;
}

- (BOOL)text:(NSString *)hay matchesAny:(NSArray<NSString *> *)needles {
    if (!hay.length) return NO;
    for (NSString *n in needles) { if ([hay containsString:n]) return YES; }
    return NO;
}

@end
