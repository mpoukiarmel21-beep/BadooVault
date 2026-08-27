#import "IVAutoSwipeVC.h"
#import "IVTheme.h"
#import "../Core/IVContainerStore.h"
#import "../Util/IVAutoSwipe.h"
#import "../Util/IVDiagnostics.h"

@interface IVAutoSwipeVC () <UITextViewDelegate>
@property (nonatomic, strong) IVContainer *container;
@property (nonatomic, strong) UITextView *phrasesView;
@property (nonatomic, strong) UITextField *countField;
@property (nonatomic, strong) UITextField *minField;
@property (nonatomic, strong) UITextField *maxField;
@property (nonatomic, strong) UIButton *runButton;
@end

@implementation IVAutoSwipeVC

- (instancetype)initWithContainer:(IVContainer *)container {
    if ((self = [super init])) { _container = container; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Auto-swipe";
    self.view.backgroundColor = IVTheme.panelBackground;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    UINavigationBar *bar = self.navigationController.navigationBar;
    bar.tintColor = IVTheme.accent;
    UINavigationBarAppearance *ap = [UINavigationBarAppearance new];
    [ap configureWithOpaqueBackground];
    ap.backgroundColor = IVTheme.panelBackground;
    ap.shadowColor = UIColor.clearColor;
    ap.titleTextAttributes = @{ NSForegroundColorAttributeName: IVTheme.primaryText };
    bar.standardAppearance = ap;
    bar.scrollEdgeAppearance = ap;
    bar.compactAppearance = ap;

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Enregistrer" style:UIBarButtonItemStyleDone
                                        target:self action:@selector(saveAndPop)];
    [self buildForm];
}

#pragma mark - Form

- (void)buildForm {
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    scroll.alwaysBounceVertical = YES;
    [self.view addSubview:scroll];

    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.topAnchor constant:18],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor constant:18],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor constant:-18],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:-24],
        [stack.widthAnchor constraintEqualToAnchor:scroll.widthAnchor constant:-36],
    ]];

    [stack addArrangedSubview:[self sectionTitle:@"Phrases envoyées sur un match"]];
    [stack addArrangedSubview:[self hint:@"Une phrase par ligne. À chaque match, le bot en envoie une au hasard. Laisse vide pour liker sans écrire."]];
    self.phrasesView = [self makeTextView];
    [self.phrasesView.heightAnchor constraintGreaterThanOrEqualToConstant:120].active = YES;
    self.phrasesView.text = [self.container.autoSwipeMessages componentsJoinedByString:@"\n"] ?: @"";
    [stack addArrangedSubview:self.phrasesView];

    [stack addArrangedSubview:[self sectionTitle:@"Paramètres de swipe"]];
    self.countField = [self fieldRowInStack:stack label:@"Nombre de swipes (0 = illimité)"
                                       value:(self.container.autoSwipeCount > 0 ? [NSString stringWithFormat:@"%ld", (long)self.container.autoSwipeCount] : @"0")];
    self.minField = [self fieldRowInStack:stack label:@"Délai min entre actions (s)"
                                     value:(self.container.autoSwipeMinDelay >= 1 ? [self fmt:self.container.autoSwipeMinDelay] : @"3")];
    self.maxField = [self fieldRowInStack:stack label:@"Délai max entre actions (s)"
                                     value:(self.container.autoSwipeMaxDelay >= 1 ? [self fmt:self.container.autoSwipeMaxDelay] : @"7")];

    [stack addArrangedSubview:[self hint:@"Détection best-effort : le bot appuie sur le like de Badoo, repère le popup « match » et envoie une phrase. Selon la version de Badoo, un réglage sur l'appareil peut être nécessaire."]];

    self.runButton = [self makeRunButton];
    [self.runButton.heightAnchor constraintEqualToConstant:52].active = YES;
    [stack addArrangedSubview:self.runButton];
    [self refreshRunButton];
}

#pragma mark - Builders

- (UILabel *)sectionTitle:(NSString *)text {
    UILabel *l = [UILabel new];
    l.text = text.uppercaseString;
    l.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    l.textColor = IVTheme.secondaryText;
    l.numberOfLines = 0;
    return l;
}

- (UILabel *)hint:(NSString *)text {
    UILabel *l = [UILabel new];
    l.text = text;
    l.font = [UIFont systemFontOfSize:12];
    l.textColor = IVTheme.secondaryText;
    l.numberOfLines = 0;
    return l;
}

- (UITextView *)makeTextView {
    UITextView *tv = [UITextView new];
    tv.backgroundColor = IVTheme.glassFill;
    tv.textColor = IVTheme.primaryText;
    tv.font = [UIFont systemFontOfSize:15];
    tv.layer.cornerRadius = 10;
    tv.layer.borderWidth = 1;
    tv.layer.borderColor = IVTheme.glassStroke.CGColor;
    tv.textContainerInset = UIEdgeInsetsMake(10, 8, 10, 8);
    tv.keyboardAppearance = UIKeyboardAppearanceDark;
    tv.delegate = self;
    return tv;
}

// Trim trailing zeros: 3.0 -> "3", 3.5 -> "3.5".
- (NSString *)fmt:(double)v {
    if (v == floor(v)) return [NSString stringWithFormat:@"%ld", (long)v];
    return [NSString stringWithFormat:@"%.1f", v];
}

- (UITextField *)fieldRowInStack:(UIStackView *)stack label:(NSString *)label value:(NSString *)value {
    UIStackView *row = [UIStackView new];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 8;

    UILabel *l = [UILabel new];
    l.text = label;
    l.font = [UIFont systemFontOfSize:15];
    l.textColor = IVTheme.primaryText;
    l.numberOfLines = 0;
    [l setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    UITextField *tf = [UITextField new];
    tf.text = value;
    tf.textAlignment = NSTextAlignmentRight;
    tf.textColor = IVTheme.primaryText;
    tf.font = [UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightSemibold];
    tf.keyboardType = UIKeyboardTypeDecimalPad;
    tf.keyboardAppearance = UIKeyboardAppearanceDark;
    tf.backgroundColor = IVTheme.glassFill;
    tf.layer.cornerRadius = 8;
    tf.layer.borderWidth = 1;
    tf.layer.borderColor = IVTheme.glassStroke.CGColor;
    tf.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, 0)];
    tf.leftViewMode = UITextFieldViewModeAlways;
    [tf.widthAnchor constraintEqualToConstant:90].active = YES;
    [tf.heightAnchor constraintEqualToConstant:38].active = YES;
    [tf setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [tf setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    [row addArrangedSubview:l];
    [row addArrangedSubview:tf];
    [stack addArrangedSubview:row];
    return tf;
}

- (UIButton *)makeRunButton {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    b.layer.cornerRadius = 14;
    [b addTarget:self action:@selector(toggleRun) forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)refreshRunButton {
    BOOL running = [IVAutoSwipe shared].isRunning;
    [self.runButton setTitle:(running ? @"Arrêter l'auto-swipe" : @"Démarrer l'auto-swipe") forState:UIControlStateNormal];
    self.runButton.backgroundColor = running ? IVTheme.elevatedSurface : IVTheme.accent;
    [self.runButton setTitleColor:(running ? IVTheme.primaryText : IVTheme.onAccent) forState:UIControlStateNormal];
    self.runButton.layer.borderWidth = running ? 1 : 0;
    self.runButton.layer.borderColor = IVTheme.glassStroke.CGColor;
}

#pragma mark - Persist + actions

- (NSArray<NSString *> *)parsedPhrases {
    NSMutableArray<NSString *> *out = [NSMutableArray new];
    for (NSString *raw in [self.phrasesView.text componentsSeparatedByString:@"\n"]) {
        NSString *t = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (t.length) [out addObject:t];
    }
    return out;
}

// Read + clamp the form, reflect the clamped values back into the fields, persist.
- (BOOL)persistConfigEnabled:(BOOL)enabled {
    NSArray<NSString *> *msgs = [self parsedPhrases];
    NSInteger count = [self.countField.text integerValue];
    if (count < 0) count = 0;
    double mn = [self.minField.text doubleValue];
    double mx = [self.maxField.text doubleValue];
    if (mn < 1) mn = 1;
    if (mx < mn) mx = mn;
    self.countField.text = [NSString stringWithFormat:@"%ld", (long)count];
    self.minField.text = [self fmt:mn];
    self.maxField.text = [self fmt:mx];
    return [[IVContainerStore shared] setAutoSwipeEnabled:enabled messages:msgs
                                                    count:count minDelay:mn maxDelay:mx
                                             forContainer:self.container];
}

- (void)warn {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Échec"
        message:@"La configuration n'a pas pu être enregistrée (écriture disque). Réessaie."
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

// "Enregistrer": persist the config (lights the row icon), stay in the panel.
- (void)saveAndPop {
    [self.view endEditing:YES];
    if (![self persistConfigEnabled:YES]) { [self warn]; return; }
    [self.navigationController popViewControllerAnimated:YES];
}

// "Démarrer": persist, start the engine, and dismiss the WHOLE panel so Badoo's
// own UI is frontmost for the bot to drive. "Arrêter": stop the engine, stay.
- (void)toggleRun {
    [self.view endEditing:YES];
    if ([IVAutoSwipe shared].isRunning) {
        [[IVAutoSwipe shared] stop];
        [self refreshRunButton];
        return;
    }
    if (![self persistConfigEnabled:YES]) { [self warn]; return; }
    [[IVAutoSwipe shared] startWithContainer:self.container];
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
