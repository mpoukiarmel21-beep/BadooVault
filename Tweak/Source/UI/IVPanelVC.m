#import "IVPanelVC.h"
#import "IVCreateVC.h"
#import "IVMapPickerVC.h"
#import "IVListPickerVC.h"
#import "IVTheme.h"
#import "IVActionSheet.h"
#import "../Core/IVContainer.h"
#import "../Core/IVContainerStore.h"
#import "../Spoof/IVDeviceSpoof.h"
#import "../Spoof/IVDeviceIdentity.h"
#import "../Spoof/IVLocaleSpoof.h"
#import "../Core/IVPaths.h"
#import "../Util/IVAppRelaunch.h"
#import "../Util/IVAutoSwipe.h"
#import "IVAutoSwipeVC.h"
#import <PhotosUI/PhotosUI.h>

@interface IVPanelVC () <UITableViewDataSource, UITableViewDelegate, PHPickerViewControllerDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, copy) NSArray<IVContainer *> *items;
@property (nonatomic, strong, nullable) UIBarButtonItem *cameraBarButton;
@end

@implementation IVPanelVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Badooscale";   // back button / accessibilité ; titleView dessine la marque

    // Dark violet-tinted surface everywhere; force Dark so system controls
    // (alerts, text fields, the pushed map/create screens) match.
    self.view.backgroundColor = IVTheme.panelBackground;
    self.navigationController.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    // Barre compacte (plus de grand titre) avec une marque discrète à côté du
    // wordmark, pour que la liste des conteneurs remonte et lise comme une seule
    // surface fluide.
    UINavigationBar *bar = self.navigationController.navigationBar;
    bar.prefersLargeTitles = NO;
    bar.tintColor = IVTheme.accent;
    self.navigationItem.titleView = [self makeBrandTitleView];

    UINavigationBarAppearance *ap = [UINavigationBarAppearance new];
    [ap configureWithOpaqueBackground];
    ap.backgroundColor = IVTheme.panelBackground;
    ap.shadowColor = UIColor.clearColor;
    ap.titleTextAttributes = @{ NSForegroundColorAttributeName: IVTheme.primaryText };
    bar.standardAppearance = ap;
    bar.scrollEdgeAppearance = ap;
    bar.compactAppearance = ap;

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                      target:self action:@selector(close)];
    UIBarButtonItem *add =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                      target:self action:@selector(createNew)];
    // Global virtual camera lives on the nav bar (shared by every container: the
    // user just swaps the one video to verify a different account). Glyph reflects
    // whether a global video is currently set.
    self.cameraBarButton =
        [[UIBarButtonItem alloc] initWithImage:[self globalCameraGlyph]
                                         style:UIBarButtonItemStylePlain
                                        target:self action:@selector(manageGlobalCamera)];
    self.navigationItem.rightBarButtonItems = @[ add, self.cameraBarButton ];

    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.backgroundColor = UIColor.clearColor;   // let panelBackground show through
    self.table.dataSource = self;
    self.table.delegate = self;
    [self.table registerClass:[UITableViewCell class] forCellReuseIdentifier:@"c"];
    if (@available(iOS 15.0, *)) {
        self.table.sectionHeaderTopPadding = 0.0;   // pas d'espace mort au-dessus de la 1re ligne
    }
    self.table.tableFooterView = [self makeResetFooter];
    // If the app launched degraded (isolation could not be applied and we fell
    // back to the REAL account), warn loudly at the top so the user does not log
    // in thinking they are inside a container.
    if ([IVContainerStore shared].isolationDegraded) {
        self.table.tableHeaderView = [self makeDegradedBanner];
    }
    [self.view addSubview:self.table];

    for (NSString *n in @[ kIVContainersChanged, kIVActiveChanged ]) {
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload)
                                                   name:n object:nil];
    }
    [self reload];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    // Fire onClose only on a real dismissal (Close / swipe-down), never when a
    // child (map picker) is pushed on top — so the floating button reappears at
    // the right moment.
    if ((self.isBeingDismissed || self.navigationController.isBeingDismissed) && self.onClose) {
        self.onClose();
        self.onClose = nil;
    }
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)reload {
    self.items = [IVContainerStore shared].containers;
    [self.table reloadData];
}

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.items.count; }

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    return @"Changer de conteneur actif nécessite un redémarrage de l'app.";
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c" forIndexPath:ip];
    IVContainer *c = self.items[ip.row];
    BOOL active = [c.cid isEqualToString:[IVContainerStore shared].activeCID];

    NSString *model = [IVDeviceSpoof effectiveModelForContainer:c];
    NSMutableString *sub = [NSMutableString stringWithString:c.isDefault ? @"Réel (non isolé)" : model];
    if (c.hasLocation && c.locationName.length) [sub appendFormat:@"  ·  📍 %@", c.locationName];

    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.text = c.name;
    content.textProperties.color = IVTheme.primaryText;
    content.textProperties.font = [UIFont systemFontOfSize:17
                                                    weight:active ? UIFontWeightSemibold : UIFontWeightRegular];
    content.secondaryText = sub;
    content.secondaryTextProperties.color = IVTheme.secondaryText;
    content.secondaryTextProperties.font = [UIFont systemFontOfSize:13];
    // Leading indicator doubles as the "active" marker (filled accent) vs idle.
    content.image = [UIImage systemImageNamed:active ? @"checkmark.circle.fill" : @"circle"];
    content.imageProperties.tintColor = active ? IVTheme.accent : IVTheme.secondaryText;
    content.imageProperties.preferredSymbolConfiguration =
        [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightRegular];
    content.imageToTextPadding = 10.0;
    cell.contentConfiguration = content;

    // Translucent-but-visible glass row over the dark surface.
    cell.backgroundColor = IVTheme.glassFill;
    UIView *sel = [UIView new];
    sel.backgroundColor = IVTheme.elevatedSurface;
    cell.selectedBackgroundView = sel;

    cell.tintColor = IVTheme.accent;
    // Affordances de fin de ligne : des icônes explicites POSÉES sur chaque
    // conteneur (appareil · localisation · caméra de vérif · auto-swipe), pour
    // que chaque réglage soit à un tap sans ouvrir de menu. Le conteneur par
    // défaut (compte réel) ne porte que l'épingle GPS. Le tap sur la ligne ouvre
    // la feuille d'actions (activer / langue & région / renommer / supprimer).
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = [self trailingControlsForRow:ip.row];
    return cell;
}

// The cell's accessoryView: explicit quick-action icons ON the row itself, so the
// per-container settings are one tap away without opening a menu (the user asked to
// bring the icons back — "remets les icônes ... c'est beaucoup plus simple"). The
// DEFAULT (real) container only carries the fake-GPS pin; a real container has no
// spoofed device / auto-swipe to configure. Each NON-default row shows the
// localisation pin FIRST and enlarged so it reads as the row's primary affordance
// ("la tourelle, tu le mets sur le conteneur pour que ça soit visible"), then the
// appareil glyph, then auto-swipe. The verification camera is GLOBAL now (one shared
// video for every container) so it lives on the nav bar, not per row. Each button
// carries the row index in its tag so the handler resolves the container at tap time
// (self.items stays in sync across reloads).
- (nullable UIView *)trailingControlsForRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.items.count) return nil;
    IVContainer *c = self.items[row];

    BOOL loc = c.hasLocation;
    UIButton *pin = [self glyphButton:(loc ? @"mappin.circle.fill" : @"mappin.and.ellipse")
                                  row:row action:@selector(editLocationFromControl:)
                                 tint:(loc ? IVTheme.accent : IVTheme.secondaryText)];

    // Default container (real account): fake GPS only, comfortably sized.
    if (c.isDefault) {
        const CGFloat size = 40.0;
        UIView *wrap = [[UIView alloc] initWithFrame:CGRectMake(0, 0, size, size)];
        pin.frame = CGRectMake(0, 0, size, size);
        [wrap addSubview:pin];
        return wrap;
    }

    // Non-default: appareil (leading & prominent) · localisation · auto-swipe.
    // Each container is a distinct virtual phone, so the phone glyph is the row's
    // headline icon (replaces the GPS pin in the prominent spot); the GPS pin and
    // auto-swipe trail it as regular controls (the pin stays visible and tappable).
    BOOL swipeOn = c.autoSwipeEnabled;
    UIButton *dev = [self glyphButton:@"iphone"
                                  row:row action:@selector(deviceInfoFromControl:)
                                 tint:IVTheme.secondaryText];
    UIButton *swipe = [self glyphButton:(swipeOn ? @"hand.draw.fill" : @"hand.draw")
                                    row:row action:@selector(autoSwipeFromControl:)
                                   tint:(swipeOn ? IVTheme.accent : IVTheme.secondaryText)];

    // Phone leads and is wider than the rest so it stands out as the row's headline
    // control; the smaller glyphs (GPS · auto-swipe) trail it.
    const CGFloat devW = 46.0, bw = 34.0, bh = 40.0;
    NSArray<UIButton *> *trailing = @[ pin, swipe ];
    UIView *wrap = [[UIView alloc] initWithFrame:CGRectMake(0, 0, devW + bw * trailing.count, bh)];
    dev.frame = CGRectMake(0, 0, devW, bh);
    [wrap addSubview:dev];
    [trailing enumerateObjectsUsingBlock:^(UIButton *b, NSUInteger i, BOOL *stop) {
        b.frame = CGRectMake(devW + bw * i, 0, bw, bh);
        [wrap addSubview:b];
    }];
    return wrap;
}

- (UIButton *)glyphButton:(NSString *)symbol row:(NSInteger)row action:(SEL)action tint:(UIColor *)tint {
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightRegular];
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setImage:[UIImage systemImageNamed:symbol withConfiguration:cfg] forState:UIControlStateNormal];
    b.tintColor = tint;
    b.tag = row;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (nullable IVContainer *)containerForControl:(UIControl *)sender {
    NSInteger row = sender.tag;
    return (row >= 0 && row < (NSInteger)self.items.count) ? self.items[row] : nil;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    [self presentActionsFor:self.items[ip.row]];
}

- (void)tableView:(UITableView *)tv accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)ip {
    [self presentActionsFor:self.items[ip.row]];
}

#pragma mark - Per-container actions

- (void)presentActionsFor:(IVContainer *)c {
    IVContainerStore *store = [IVContainerStore shared];
    BOOL active = [c.cid isEqualToString:store.activeCID];
    __weak typeof(self) ws = self;

    IVActionSheet *sheet = [[IVActionSheet alloc] initWithTitle:c.name
                                                        message:active ? @"Conteneur actif" : nil];

    if (!active) {
        [sheet addAction:[IVAction actionWithTitle:@"Activer ce conteneur"
                                            symbol:@"power.circle.fill"
                                             style:IVActionStyleAccentSoft
                                           handler:^{ [ws activate:c]; }]];
    }
    if (!c.isDefault) {
        // Appareil, caméra et auto-swipe ont leurs icônes directes sur la ligne ;
        // ne restent ici que les réglages sans icône dédiée + renommer / supprimer.
        [sheet addAction:[IVAction actionWithTitle:@"Langue & région"
                                            symbol:@"gearshape"
                                             style:IVActionStyleDefault
                                           handler:^{ [ws showSettingsFor:c]; }]];
        [sheet addAction:[IVAction actionWithTitle:@"Renommer"
                                            symbol:@"pencil"
                                             style:IVActionStyleDefault
                                           handler:^{ [ws rename:c]; }]];
        [sheet addAction:[IVAction actionWithTitle:@"Supprimer"
                                            symbol:@"trash"
                                             style:IVActionStyleDestructive
                                           handler:^{ [ws delete:c]; }]];
    }
    [sheet presentFrom:self];
}

- (void)activate:(IVContainer *)c {
    if (![[IVContainerStore shared] setActiveCID:c.cid]) {
        [self warn:@"Échec" msg:@"Impossible d'enregistrer le conteneur actif (écriture disque échouée). Réessaie."];
        return;
    }
    // Le choix est persisté : il reste à redémarrer pour l'appliquer. On ferme
    // l'app automatiquement après une brève confirmation (aucun bouton — la
    // fermeture est le geste). Le conteneur par défaut reste intact comme
    // repli : activer un autre conteneur ne le supprime jamais.
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Conteneur activé"
        message:[NSString stringWithFormat:@"« %@ » est prêt.\nL'app va se fermer — rouvre-la pour l'utiliser.", c.name]
                                                       preferredStyle:UIAlertControllerStyleAlert];
    a.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [self presentViewController:a animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.4 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ IVCloseAppForRelaunch(); });
    }];
}

- (void)editLocationFromControl:(UIButton *)sender {
    IVContainer *c = [self containerForControl:sender];
    if (c) [self editLocation:c];
}

- (void)editLocation:(IVContainer *)c {
    IVMapPickerVC *map = [[IVMapPickerVC alloc] initWithContainer:c];
    __weak typeof(self) ws = self;
    map.onCommit = ^(CLLocationCoordinate2D coord, NSString *name) { [ws reload]; };
    [self.navigationController pushViewController:map animated:YES];
}

#pragma mark - Row icon handlers (device · auto-swipe)

// "Téléphone" : ouvre la fiche appareil (modèle, iOS, série — lecture seule).
- (void)deviceInfoFromControl:(UIButton *)sender {
    IVContainer *c = [self containerForControl:sender];
    if (c) [self showDeviceInfoFor:c];
}

// "Auto-swipe" : ouvre le panneau de configuration du bot pour ce conteneur.
- (void)autoSwipeFromControl:(UIButton *)sender {
    IVContainer *c = [self containerForControl:sender];
    if (c) [self showAutoSwipeFor:c];
}

// Panneau de configuration de l'auto-swipe, poussé sur la pile de navigation (comme
// le sélecteur de langue / la carte). Le panneau gère lui-même « Enregistrer » /
// « Démarrer » : démarrer ferme tout le panneau pour laisser l'UI de Badoo au premier
// plan, seule surface que le bot pilote.
- (void)showAutoSwipeFor:(IVContainer *)c {
    if (!c) return;
    IVAutoSwipeVC *vc = [[IVAutoSwipeVC alloc] initWithContainer:c];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)rename:(IVContainer *)c {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Renommer" message:nil
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = c.name; }];
    [a addAction:[UIAlertAction actionWithTitle:@"Annuler" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Enregistrer" style:UIAlertActionStyleDefault
                                        handler:^(UIAlertAction *x) {
        if ([[IVContainerStore shared] renameContainer:c to:a.textFields.firstObject.text]) {
            [self reload];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self warn:@"Renommage impossible" msg:@"Nom vide ou écriture disque échouée."];
            });
        }
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)delete:(IVContainer *)c {
    if ([c.cid isEqualToString:[IVContainerStore shared].activeCID]) {
        [self warn:@"Conteneur actif" msg:@"Bascule sur un autre conteneur avant de le supprimer."];
        return;
    }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Supprimer ce conteneur ?"
        message:@"Toutes ses données (comptes, réglages) seront effacées définitivement."
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Annuler" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Supprimer" style:UIAlertActionStyleDestructive
                                        handler:^(UIAlertAction *x) {
        if ([[IVContainerStore shared] removeContainer:c]) {
            [self reload];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self warn:@"Suppression impossible" msg:@"Le conteneur est actif ou l'écriture disque a échoué."];
            });
        }
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Device info (read-only) + settings (language / region)

- (void)showDeviceInfoFor:(IVContainer *)c {
    if (!c) return;
    NSString *ident = [IVDeviceSpoof effectiveModelForContainer:c];
    NSString *marketing = [IVDeviceIdentity marketingNameForIdentifier:ident];

    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    if (c.iosVersion.length) {
        NSString *build = [IVDeviceIdentity buildForIOSVersion:c.iosVersion];
        [lines addObject:[NSString stringWithFormat:@"iOS %@%@", c.iosVersion,
                          build.length ? [NSString stringWithFormat:@" (build %@)", build] : @""]];
    } else {
        [lines addObject:@"iOS : version réelle (non forcée)"];
    }
    [lines addObject:[NSString stringWithFormat:@"Identifiant : %@", ident]];
    [lines addObject:[NSString stringWithFormat:@"N° de modèle : %@",
                      [IVDeviceIdentity modelNumberForCID:c.cid region:c.regionCountry]]];
    [lines addObject:[NSString stringWithFormat:@"N° de série : %@", [IVDeviceIdentity serialForCID:c.cid]]];
    [lines addObject:@""];
    [lines addObject:@"Ces informations sont celles répondues à Badoo (série et n° de modèle sont indicatifs, affichage seul)."];

    UIAlertController *a = [UIAlertController alertControllerWithTitle:marketing
                                                              message:[lines componentsJoinedByString:@"\n"]
                                                       preferredStyle:UIAlertControllerStyleAlert];
    a.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [a addAction:[UIAlertAction actionWithTitle:@"Fermer" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)showSettingsFor:(IVContainer *)c {
    if (!c) return;
    __weak typeof(self) ws = self;

    NSString *langNow = c.appLanguage.length
        ? [IVLocaleSpoof displayNameForLanguage:c.appLanguage] : @"Automatique";
    NSString *regionNow = c.regionCountry.length
        ? [IVLocaleSpoof displayNameForRegion:c.regionCountry] : @"Automatique";

    IVActionSheet *sheet = [[IVActionSheet alloc] initWithTitle:[NSString stringWithFormat:@"Réglages — %@", c.name]
                                                        message:@"Prend effet au prochain démarrage de l'app."];
    [sheet addAction:[IVAction actionWithTitle:[NSString stringWithFormat:@"Langue : %@", langNow]
                                        symbol:@"globe"
                                         style:IVActionStyleDefault
                                       handler:^{ [ws pickLanguageFor:c]; }]];
    [sheet addAction:[IVAction actionWithTitle:[NSString stringWithFormat:@"Région : %@", regionNow]
                                        symbol:@"map"
                                         style:IVActionStyleDefault
                                       handler:^{ [ws pickRegionFor:c]; }]];
    [sheet presentFrom:self];
}

- (void)pickLanguageFor:(IVContainer *)c {
    NSMutableArray<IVListOption *> *opts = [NSMutableArray new];
    [opts addObject:[IVListOption value:@"" title:@"Automatique (système)" subtitle:nil]];
    for (NSString *code in [IVLocaleSpoof supportedLanguageCodes]) {
        [opts addObject:[IVListOption value:code title:[IVLocaleSpoof displayNameForLanguage:code] subtitle:code]];
    }
    __weak typeof(self) ws = self;
    IVListPickerVC *p = [[IVListPickerVC alloc] initWithTitle:@"Langue de l'application"
                                                      options:opts
                                                selectedValue:c.appLanguage
                                                       onPick:^(IVListOption *o) {
        NSString *lang = o.value.length ? o.value : nil;
        if (![[IVContainerStore shared] setAppLanguage:lang region:c.regionCountry forContainer:c]) {
            [ws warn:@"Échec" msg:@"Impossible d'enregistrer la langue (écriture disque échouée)."];
        }
        [ws reload];
    }];
    [self.navigationController pushViewController:p animated:YES];
}

- (void)pickRegionFor:(IVContainer *)c {
    NSMutableArray<IVListOption *> *opts = [NSMutableArray new];
    [opts addObject:[IVListOption value:@"" title:@"Automatique (système)" subtitle:nil]];
    for (NSString *code in [IVLocaleSpoof supportedRegionCodes]) {
        [opts addObject:[IVListOption value:code title:[IVLocaleSpoof displayNameForRegion:code] subtitle:code]];
    }
    __weak typeof(self) ws = self;
    IVListPickerVC *p = [[IVListPickerVC alloc] initWithTitle:@"Pays / région"
                                                      options:opts
                                                selectedValue:c.regionCountry
                                                       onPick:^(IVListOption *o) {
        NSString *region = o.value.length ? o.value : nil;
        if (![[IVContainerStore shared] setAppLanguage:c.appLanguage region:region forContainer:c]) {
            [ws warn:@"Échec" msg:@"Impossible d'enregistrer la région (écriture disque échouée)."];
        }
        [ws reload];
    }];
    [self.navigationController pushViewController:p animated:YES];
}

#pragma mark - Caméra virtuelle globale (vidéo de vérification partagée)

// The virtual camera is GLOBAL: ONE video feeds Badoo's OWN native capture pipeline
// for every container. The user swaps the single file to verify a different account
// ("Tu peux mettre le même système de caméra pour tous les containers et moi j'aurais
// qu'à changer la vidéo"). State = the mere existence of the global video on disk.

// Nav-bar glyph reflecting whether a global video is currently set (filled = set).
- (UIImage *)globalCameraGlyph {
    BOOL has = [IVPaths hasGlobalCameraVideo];
    return [UIImage systemImageNamed:(has ? @"video.fill" : @"video")];
}

- (void)refreshCameraBarButton {
    self.cameraBarButton.image = [self globalCameraGlyph];
    self.cameraBarButton.tintColor = [IVPaths hasGlobalCameraVideo] ? IVTheme.accent : nil;
}

// Tap the nav-bar camera: pick a video if none is set, otherwise offer to change or
// remove the one shared by every container.
- (void)manageGlobalCamera {
    if (![IVPaths hasGlobalCameraVideo]) { [self pickGlobalCameraVideo]; return; }
    __weak typeof(self) ws = self;
    IVActionSheet *sheet = [[IVActionSheet alloc] initWithTitle:@"Caméra virtuelle"
                                                        message:@"Vidéo de vérification définie ✓ (partagée par tous les conteneurs)"];
    [sheet addAction:[IVAction actionWithTitle:@"Changer la vidéo"
                                        symbol:@"video.badge.plus"
                                         style:IVActionStyleDefault
                                       handler:^{ [ws pickGlobalCameraVideo]; }]];
    [sheet addAction:[IVAction actionWithTitle:@"Retirer la vidéo"
                                        symbol:@"video.slash"
                                         style:IVActionStyleDestructive
                                       handler:^{ [ws removeGlobalCameraVideo]; }]];
    [sheet presentFrom:self];
}

// PHPickerViewController runs out-of-process (no photo-library permission prompt).
- (void)pickGlobalCameraVideo {
    if (@available(iOS 14.0, *)) {
        PHPickerConfiguration *cfg = [[PHPickerConfiguration alloc] init];
        cfg.filter = [PHPickerFilter videosFilter];
        cfg.selectionLimit = 1;
        PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:cfg];
        picker.delegate = self;
        picker.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        [self presentViewController:picker animated:YES completion:nil];
    } else {
        [self warn:@"Indisponible" msg:@"La sélection de vidéo nécessite iOS 14 ou plus récent."];
    }
}

- (void)removeGlobalCameraVideo {
    [IVPaths removeGlobalCameraVideo];
    [self refreshCameraBarButton];
    [self warn:@"Vidéo retirée"
           msg:@"La caméra virtuelle est désactivée : Badoo utilisera de nouveau la vraie caméra."];
}

- (void)picker:(PHPickerViewController *)picker
    didFinishPicking:(NSArray<PHPickerResult *> *)results API_AVAILABLE(ios(14.0)) {
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (results.count == 0) return;

    NSItemProvider *provider = results.firstObject.itemProvider;
    if (![provider hasItemConformingToTypeIdentifier:@"public.movie"]) {
        [self warn:@"Format non pris en charge" msg:@"Choisis une vidéo (.mov ou .mp4)."];
        return;
    }
    // The vended file URL is valid ONLY for the duration of this completion block,
    // so we import (copy into the control dir) synchronously here, then hop to the
    // main queue for the UI refresh.
    [provider loadFileRepresentationForTypeIdentifier:@"public.movie"
                                    completionHandler:^(NSURL *url, NSError *error) {
        BOOL imported = (url != nil) && [IVPaths importGlobalCameraVideoFromURL:url];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!imported) {
                [self warn:@"Import échoué" msg:@"La vidéo n'a pas pu être copiée. Réessaie."];
                return;
            }
            [self refreshCameraBarButton];
            [self warn:@"Vidéo enregistrée"
                   msg:@"Elle alimentera la caméra native de Badoo lors de la vérification, sur "
                       @"tous les conteneurs. Redémarre l'app pour l'activer."];
        });
    }];
}

- (void)createNew {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:
                                   [[IVCreateVC alloc] initWithContainer:nil]];
    nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;   // match the dark menu
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - Global reset

- (void)confirmReset {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Tout réinitialiser ?"
        message:@"Déconnecte AUSSI le compte principal : efface tous les cookies et sessions "
                @"Badoo du téléphone et supprime tous les conteneurs. L'app se fermera. "
                @"Irréversible."
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Annuler" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Réinitialiser" style:UIAlertActionStyleDestructive
                                        handler:^(UIAlertAction *x) {
        if ([[IVContainerStore shared] resetAll]) {
            // The wipe cleared the on-disk + keychain + in-memory session, but the
            // running Badoo process still holds live session state (NSURLSession,
            // WebKit) that it would re-persist over the freshly cleared files on the
            // next flush. Cold-close so the next open relaunches truly logged out.
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertController *done = [UIAlertController
                    alertControllerWithTitle:@"Réinitialisé"
                                     message:@"Compte déconnecté et données effacées. "
                                             @"L'app va se fermer — rouvre-la."
                              preferredStyle:UIAlertControllerStyleAlert];
                [done addAction:[UIAlertAction actionWithTitle:@"Fermer"
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *y) {
                    IVCloseAppForRelaunch();
                }]];
                [self presentViewController:done animated:YES completion:nil];
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self warn:@"Réinitialisation incomplète" msg:@"L'écriture disque a échoué. Réessaie."];
            });
        }
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)warn:(NSString *)title msg:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

// A small, restrained brand mark shown in the nav bar beside the "Badooscale"
// wordmark: a soft accent-tinted rounded badge holding a stacked-layers glyph
// (the "isolated containers" idea). Deliberately understated — present, not loud.
- (UIView *)makeBrandTitleView {
    UILabel *word = [UILabel new];
    word.text = @"Badooscale";
    word.textColor = IVTheme.primaryText;
    word.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [word sizeToFit];

    const CGFloat badgeSize = 24.0, gap = 8.0, h = 30.0;
    UIView *badge = [[UIView alloc] initWithFrame:CGRectMake(0, 0, badgeSize, badgeSize)];
    badge.backgroundColor = [IVTheme.accent colorWithAlphaComponent:0.20];
    badge.layer.cornerRadius = 6.0;
    badge.layer.cornerCurve = kCACornerCurveContinuous;
    badge.layer.borderWidth = 1.0;
    badge.layer.borderColor = [IVTheme.accent colorWithAlphaComponent:0.55].CGColor;

    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightBold];
    UIImageView *glyph = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:@"square.stack.3d.up.fill" withConfiguration:cfg]];
    glyph.tintColor = IVTheme.accent;
    glyph.contentMode = UIViewContentModeCenter;
    glyph.frame = badge.bounds;
    [badge addSubview:glyph];

    CGFloat w = badgeSize + gap + word.bounds.size.width;
    UIView *wrap = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
    badge.center = CGPointMake(badgeSize / 2.0, h / 2.0);
    [wrap addSubview:badge];
    word.frame = CGRectMake(badgeSize + gap, 0, word.bounds.size.width, h);
    [wrap addSubview:word];
    return wrap;
}

- (UIView *)makeDegradedBanner {
    CGFloat w = self.view.bounds.size.width;
    UIView *wrap = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 96)];
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(20, 12, w - 40, 72)];
    card.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    card.backgroundColor = [UIColor.systemRedColor colorWithAlphaComponent:0.18];
    card.layer.cornerRadius = 14.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [UIColor.systemRedColor colorWithAlphaComponent:0.55].CGColor;

    UILabel *l = [[UILabel alloc] initWithFrame:CGRectInset(card.bounds, 14, 10)];
    l.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    l.numberOfLines = 0;
    l.textColor = IVTheme.primaryText;
    l.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    l.text = @"⚠️ Isolation inactive — vous êtes sur le compte réel. Ne vous connectez pas ici ; fermez complètement l'app puis rouvrez-la.";
    [card addSubview:l];
    [wrap addSubview:card];
    return wrap;
}

- (UIView *)makeResetFooter {
    UIView *wrap = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 88)];
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(20, 24, wrap.bounds.size.width - 40, 52);
    b.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [b setTitle:@"Tout réinitialiser" forState:UIControlStateNormal];
    [b setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    // Translucent glass pill so it reads as a deliberate, framed destructive action.
    b.backgroundColor = IVTheme.glassFill;
    b.layer.cornerRadius = 16.0;
    b.layer.cornerCurve = kCACornerCurveContinuous;
    b.layer.borderWidth = 1.0;
    b.layer.borderColor = IVTheme.glassStroke.CGColor;
    [b addTarget:self action:@selector(confirmReset) forControlEvents:UIControlEventTouchUpInside];
    [wrap addSubview:b];
    return wrap;
}

@end
