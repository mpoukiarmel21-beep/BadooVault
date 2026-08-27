#import <UIKit/UIKit.h>
#import <objc/message.h>
#import "IVAutoSwipe.h"
#import "IVDiagnostics.h"

// Best-effort keyword sets (lowercased substring match over an element's
// accessibilityIdentifier + accessibilityLabel + button title). No Badoo private
// headers exist, so these are heuristics tuned to Badoo's visible/ax strings.
// Bare "yes"/"no"/"non" are intentionally excluded — they match unrelated words
// ("yesterday", "notification") and would mis-tap.
static NSArray<NSString *> *IVLikeKeywords(void)    { return @[@"like", @"heart", @"jaime", @"vote_yes", @"yes_vote", @"favorite", @"btn_yes", @"coeur"]; }
static NSArray<NSString *> *IVDislikeKeywords(void) { return @[@"dislike", @"pass", @"nope", @"vote_no", @"no_vote", @"reject", @"btn_no", @"croix", @"skip"]; }
// Controls we must never mistake for like/dislike (nav, boost, super-like, chat…).
static NSArray<NSString *> *IVSwipeAvoidKeywords(void){ return @[@"super", @"boost", @"rewind", @"undo", @"back", @"settings", @"profile", @"filter", @"menu", @"tab", @"spotlight", @"message", @"chat", @"crush", @"gift"]; }
static NSArray<NSString *> *IVMatchKeywords(void)   { return @[@"match", @"vous vous plaisez", @"you matched", @"c'est un match", @"it's a match", @"mutual"]; }
static NSArray<NSString *> *IVSendKeywords(void)    { return @[@"send", @"envoyer", @"envoi"]; }
static NSArray<NSString *> *IVContinueKeywords(void){ return @[@"continue", @"continuer", @"keep", @"garder", @"swip", @"later", @"plus tard", @"discuter", @"chat", @"fermer", @"close"]; }

@implementation IVAutoSwipe {
    BOOL _running;
    NSArray<NSString *> *_messages;
    NSInteger _count;      // 0 == unlimited
    double _min, _max;     // seconds
    NSInteger _method;     // 0 == boutons (tap), 1 == gestes (finger swipe)
    NSInteger _likePercent;// 0..100 — probability an action is a LIKE
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
    _method = (c.autoSwipeMethod == 1) ? 1 : 0;
    _likePercent = c.autoSwipeLikePercent < 0 ? 0 : (c.autoSwipeLikePercent > 100 ? 100 : c.autoSwipeLikePercent);
    _done = 0;
    _running = YES;
    _gen++;
    IVLog(@"auto-swipe: START cid=%@ count=%ld delay=[%.1f,%.1f] method=%@ like=%ld%% msgs=%lu",
          c.cid, (long)_count, _min, _max, _method == 1 ? @"gestes" : @"boutons",
          (long)_likePercent, (unsigned long)_messages.count);
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

    // Roll the like/dislike ratio for this profile. left→dislike, right→like.
    BOOL wantLike = ((NSInteger)arc4random_uniform(100) < _likePercent);
    BOOL acted = [self performAction:wantLike inView:root];
    if (acted) {
        _done++;
        IVLog(@"auto-swipe: %@ (%ld%@)", wantLike ? @"like" : @"dislike", (long)_done,
              _count > 0 ? [NSString stringWithFormat:@"/%ld", (long)_count] : @"");
        if (_count > 0 && _done >= _count) { IVLog(@"auto-swipe: count reached — stopping"); [self stop]; return; }
    } else {
        IVLog(@"auto-swipe: no actionable control/card found this tick");
    }
    [self scheduleNextTick];
}

#pragma mark - Action dispatch (method + like/dislike)

// Perform one swipe action. In "gestes" mode, synthesize a finger swipe on the top
// card (right = like, left = dislike) and, if synthesis is unavailable, fall back
// to tapping the buttons. In "boutons" mode, tap Badoo's like/dislike control. If
// the desired control isn't found, try the opposite so the queue keeps advancing.
// Returns YES if some action was taken.
- (BOOL)performAction:(BOOL)wantLike inView:(UIView *)root {
    if (_method == 1) {
        if ([self synthesizeSwipeLike:wantLike inView:root]) return YES;
        IVLog(@"auto-swipe: gesture synthesis unavailable — falling back to buttons");
    }
    return [self tapVoteLike:wantLike inView:root];
}

// Tap Badoo's own like/dislike control; falls through to the opposite vote if the
// desired one can't be located (keeps the profile queue moving rather than stalling).
- (BOOL)tapVoteLike:(BOOL)wantLike inView:(UIView *)root {
    UIControl *primary = wantLike ? [self findLikeControlInView:root] : [self findDislikeControlInView:root];
    if (primary) { [self tapControl:primary]; return YES; }
    UIControl *fallback = wantLike ? [self findDislikeControlInView:root] : [self findLikeControlInView:root];
    if (fallback) {
        IVLog(@"auto-swipe: desired %@ control missing — used opposite to advance", wantLike ? @"like" : @"dislike");
        [self tapControl:fallback];
        return YES;
    }
    return NO;
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

// Concatenate keyword arrays into a single avoid-set.
static NSArray<NSString *> *IVConcat(NSArray<NSString *> *a, NSArray<NSString *> *b) {
    NSMutableArray<NSString *> *m = [NSMutableArray arrayWithArray:a];
    [m addObjectsFromArray:b];
    return m;
}

// The like control must not be confused with the dislike control or any nav/boost/
// super-like control, so avoid both keyword sets.
- (UIControl *)findLikeControlInView:(UIView *)root {
    return [self findControlInView:root
                          keywords:IVLikeKeywords()
                             avoid:IVConcat(IVDislikeKeywords(), IVSwipeAvoidKeywords())];
}

// Symmetric dislike finder — avoid the like set and the nav/boost/super-like set.
- (UIControl *)findDislikeControlInView:(UIView *)root {
    return [self findControlInView:root
                          keywords:IVDislikeKeywords()
                             avoid:IVConcat(IVLikeKeywords(), IVSwipeAvoidKeywords())];
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

#pragma mark - Gesture synthesis ("Gestes" mode — best-effort)

// Locate the swipeable profile card: the largest visible non-control view that
// carries a UIPanGestureRecognizer (Badoo's card stack drives like/dislike from a
// pan). Falls back to the largest big central view if no pan recognizer is exposed.
- (UIView *)findCardInView:(UIView *)root {
    UIView *bestPan = nil; CGFloat bestPanArea = 0;
    UIView *bestBig = nil; CGFloat bestBigArea = 0;
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if (!v.hidden && v.alpha >= 0.05) {
            CGSize sz = v.bounds.size;
            CGFloat area = sz.width * sz.height;
            if (sz.width > 180 && sz.height > 220 && ![v isKindOfClass:UIControl.class]) {
                BOOL hasPan = NO;
                for (UIGestureRecognizer *g in v.gestureRecognizers) {
                    if ([g isKindOfClass:UIPanGestureRecognizer.class]) { hasPan = YES; break; }
                }
                if (hasPan && area > bestPanArea) { bestPanArea = area; bestPan = v; }
                if (area > bestBigArea) { bestBigArea = area; bestBig = v; }
            }
            for (UIView *sub in v.subviews) [stack addObject:sub];
        }
    }
    return bestPan ?: bestBig;
}

// Drive a real horizontal finger swipe over the top card (right = like, left =
// dislike) by synthesizing UITouch/UIEvent through private UIKit selectors. Every
// selector is respondsToSelector-guarded and the whole path is @try-wrapped:
// on ANY unavailability we return NO so performAction: falls back to buttons.
- (BOOL)synthesizeSwipeLike:(BOOL)wantLike inView:(UIView *)root {
    UIView *card = [self findCardInView:root];
    UIWindow *win = card.window;
    if (!card || !win) return NO;

    UIApplication *app = UIApplication.sharedApplication;
    SEL touchesEventSel = NSSelectorFromString(@"_touchesEvent");
    SEL setLocSel = NSSelectorFromString(@"_setLocationInWindow:resetPrevious:");
    SEL setPhaseSel = NSSelectorFromString(@"setPhase:");
    SEL setWindowSel = NSSelectorFromString(@"setWindow:");
    SEL setViewSel = NSSelectorFromString(@"setView:");
    SEL setTapSel = NSSelectorFromString(@"setTapCount:");
    SEL setTSSel = NSSelectorFromString(@"setTimestamp:");
    SEL addTouchSel = NSSelectorFromString(@"_addTouch:forDelayedDelivery:");

    UITouch *touch = [[UITouch alloc] init];
    if (![app respondsToSelector:touchesEventSel] ||
        ![touch respondsToSelector:setLocSel] ||
        ![touch respondsToSelector:setPhaseSel] ||
        ![touch respondsToSelector:setWindowSel] ||
        ![touch respondsToSelector:setViewSel] ||
        ![touch respondsToSelector:setTapSel] ||
        ![touch respondsToSelector:setTSSel]) {
        return NO;
    }

    @try {
        CGRect b = [card convertRect:card.bounds toView:win];
        CGFloat y = CGRectGetMidY(b);
        CGFloat x0 = CGRectGetMidX(b);
        CGFloat dx = CGRectGetWidth(b) * 0.42;
        CGPoint start = CGPointMake(x0, y);
        CGPoint finish = CGPointMake(wantLike ? x0 + dx : x0 - dx, y);

        typedef void (*VoidObjIMP)(id, SEL, id);
        typedef void (*VoidUIntIMP)(id, SEL, NSUInteger);
        typedef void (*VoidDblIMP)(id, SEL, double);
        typedef void (*VoidPtBoolIMP)(id, SEL, CGPoint, BOOL);

        VoidObjIMP setWindow = (VoidObjIMP)objc_msgSend;
        VoidObjIMP setView = (VoidObjIMP)objc_msgSend;
        VoidUIntIMP setTap = (VoidUIntIMP)objc_msgSend;
        VoidUIntIMP setPhase = (VoidUIntIMP)objc_msgSend;
        VoidDblIMP setTS = (VoidDblIMP)objc_msgSend;
        VoidPtBoolIMP setLoc = (VoidPtBoolIMP)objc_msgSend;

        setWindow(touch, setWindowSel, win);
        setView(touch, setViewSel, card);
        setTap(touch, setTapSel, 1);
        setTS(touch, setTSSel, [[NSProcessInfo processInfo] systemUptime]);
        setLoc(touch, setLocSel, start, YES);

        UIEvent *event = ((id (*)(id, SEL))objc_msgSend)(app, touchesEventSel);
        if (!event) return NO;
        BOOL canAdd = [event respondsToSelector:addTouchSel];

        // UITouchPhaseBegan = 0, Moved = 1, Ended = 3.
        setPhase(touch, setPhaseSel, 0);
        if (canAdd) ((void (*)(id, SEL, id, BOOL))objc_msgSend)(event, addTouchSel, touch, NO);
        [app sendEvent:event];

        NSInteger steps = 12;
        for (NSInteger i = 1; i <= steps; i++) {
            CGFloat t = (CGFloat)i / (CGFloat)steps;
            CGPoint p = CGPointMake(start.x + (finish.x - start.x) * t, y);
            setLoc(touch, setLocSel, p, NO);
            setPhase(touch, setPhaseSel, 1);
            setTS(touch, setTSSel, [[NSProcessInfo processInfo] systemUptime]);
            [app sendEvent:event];
        }

        setLoc(touch, setLocSel, finish, NO);
        setPhase(touch, setPhaseSel, 3);
        setTS(touch, setTSSel, [[NSProcessInfo processInfo] systemUptime]);
        [app sendEvent:event];
        return YES;
    } @catch (__unused NSException *e) {
        return NO;
    }
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
