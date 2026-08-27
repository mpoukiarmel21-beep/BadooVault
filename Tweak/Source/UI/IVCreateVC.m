#import "IVCreateVC.h"
#import "IVListPickerVC.h"
#import "IVTheme.h"
#import "../Core/IVContainer.h"
#import "../Core/IVContainerStore.h"
#import "../Spoof/IVDeviceIdentity.h"
#import "../Util/IVAppRelaunch.h"

#pragma mark - Create / edit

@interface IVCreateVC () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, strong, nullable) IVContainer *editing;   // nil == create
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, copy) NSString *chosenModel;        // identifier, e.g. "iPhone17,1"
@property (nonatomic, copy) NSString *chosenIOS;          // marketing, e.g. "26.6.1"
@property (nonatomic, copy, nullable) NSString *seedCID;  // create only: cid minted up-front to seed a unique fingerprint
@end

@implementation IVCreateVC

- (instancetype)initWithContainer:(IVContainer *)container {
    if ((self = [super init])) {
        _editing = container;
        if (container) {
            // Edit: keep the container's saved identity; if a legacy container has
            // none, fall back to a UNIQUE per-cid identity (never the shared newest).
            _chosenModel = container.deviceModel.length ? container.deviceModel
                            : [IVDeviceIdentity seededModelForCID:container.cid].identifier;
            _chosenIOS = container.iosVersion.length ? container.iosVersion
                            : [IVDeviceIdentity seededIOSVersionForCID:container.cid];
        } else {
            // Create: mint the cid NOW and derive a UNIQUE fingerprint from it, so
            // every new container defaults to a DISTINCT device + iOS instead of all
            // sharing the newest one (the multi-account fingerprint collision that
            // trips Badoo). The user can still override both in the pickers; the
            // same cid is handed to the store at save so the whole identity (model,
            // iOS, serial, UDID, IDFV) derives from one seed.
            _seedCID = [[NSUUID UUID] UUIDString];
            _chosenModel = [IVDeviceIdentity seededModelForCID:_seedCID].identifier;
            _chosenIOS = [IVDeviceIdentity seededIOSVersionForCID:_seedCID];
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.editing ? @"Modifier" : @"Nouveau conteneur";
    self.view.backgroundColor = IVTheme.panelBackground;
    // Pin Dark so the grouped table, its separators and system controls read as
    // one dark surface with the pickers pushed from here.
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    // Opaque dark nav bar (same recipe as the main panel) so this screen AND the
    // model / iOS pickers pushed from it read as one dark surface — never the bare
    // white bar the default appearance would give.
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

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                      target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                      target:self action:@selector(save)];

    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.backgroundColor = UIColor.clearColor;
    self.table.dataSource = self;
    self.table.delegate = self;
    [self.view addSubview:self.table];
}

- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)save {
    NSString *name = [self.nameField.text stringByTrimmingCharactersInSet:
                      NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (name.length == 0) name = @"Conteneur";
    NSString *marketing = [IVDeviceIdentity marketingNameForIdentifier:self.chosenModel];
    IVContainerStore *store = [IVContainerStore shared];

    IVContainer *target = self.editing;
    BOOL creating = (target == nil);
    if (target) {
        if (![store renameContainer:target to:name]) { [self warnSaveFailed]; return; }
    } else {
        // Pass the up-front cid so the container adopts the exact identity previewed
        // above (model + iOS derived from this same seed).
        target = [store createWithName:name cid:self.seedCID];
        if (!target) { [self warnSaveFailed]; return; }
    }
    if (![store setDeviceModel:self.chosenModel
                    iosVersion:self.chosenIOS
                 marketingName:marketing
                  forContainer:target]) {
        [self warnSaveFailed];
        return;
    }

    // Édition d'un conteneur existant : rien à activer, on revient au panneau.
    if (!creating) {
        [self dismissViewControllerAnimated:YES completion:nil];
        return;
    }

    // Création : c'est ICI que se règle le bug « je crée un conteneur mais je
    // retombe sur le même compte ». Créer un conteneur ne fait que l'ajouter à la
    // liste ; l'isolation (redirections HOME/keychain/prefs/app-group + spoof
    // device) n'est appliquée qu'au PROCHAIN lancement, sur le conteneur ACTIF.
    // Tant qu'on n'active pas + relance, l'app continue de tourner sur l'ancien
    // conteneur (souvent le compte réel banni), d'où « je tombe toujours sur le
    // même compte ». On propose donc d'activer le tout nouveau conteneur — un
    // compte vierge, non lié à ce téléphone — et de fermer l'app pour qu'elle
    // rouvre dessus, déconnectée.
    [self promptActivateNewContainer:target];
}

// Demande à l'utilisateur d'activer le conteneur fraîchement créé. « Activer et
// fermer » enregistre le nouveau conteneur comme actif puis ferme l'app pour une
// relance à froid (seule façon d'appliquer son isolation). « Plus tard » n'active
// rien — le conteneur actif reste inchangé, donc aucune garde « conteneur périmé »
// ne se déclenche au prochain retour d'avant-plan.
- (void)promptActivateNewContainer:(IVContainer *)target {
    NSString *msg = [NSString stringWithFormat:
        @"« %@ » est un tout nouveau compte : vierge, déconnecté et non lié à ce "
        @"téléphone (appareil, identifiants et session distincts).\n\n"
        @"Pour l'ouvrir, l'app va se fermer — rouvre-la et elle démarrera "
        @"directement sur ce conteneur.", target.name];
    UIAlertController *a =
        [UIAlertController alertControllerWithTitle:@"Conteneur créé"
                                            message:msg
                                     preferredStyle:UIAlertControllerStyleAlert];
    a.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    a.view.tintColor = IVTheme.accent;

    IVContainerStore *store = [IVContainerStore shared];
    [a addAction:[UIAlertAction actionWithTitle:@"Activer et fermer"
                                          style:UIAlertActionStyleDefault
                                        handler:^(UIAlertAction *x) {
        if (![store setActiveCID:target.cid]) { [self warnSaveFailed]; return; }
        IVCloseAppForRelaunch();
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Plus tard"
                                          style:UIAlertActionStyleCancel
                                        handler:^(UIAlertAction *x) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)warnSaveFailed {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Échec de l'enregistrement"
        message:@"Le conteneur n'a pas pu être enregistré (écriture disque échouée). Réessaie."
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Table (row 0: name, row 1: model, row 2: iOS version)

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 1; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return 3; }

- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    return [NSString stringWithFormat:@"Modèles limités à la puce réelle (%@). Chaque conteneur répond ces informations à Badoo.",
            [IVDeviceIdentity realChipFamily]];
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.row == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"n"];
        cell.backgroundColor = IVTheme.glassFill;
        if (!self.nameField) {
            self.nameField = [[UITextField alloc] initWithFrame:CGRectInset(cell.contentView.bounds, 16, 0)];
            self.nameField.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            self.nameField.placeholder = @"Nom du conteneur";
            self.nameField.text = self.editing.name;
            self.nameField.textColor = IVTheme.primaryText;
            self.nameField.clearButtonMode = UITextFieldViewModeWhileEditing;
            self.nameField.delegate = self;
        }
        [cell.contentView addSubview:self.nameField];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"v"];
    cell.backgroundColor = IVTheme.glassFill;
    cell.textLabel.textColor = IVTheme.primaryText;
    cell.detailTextLabel.textColor = IVTheme.secondaryText;
    if (ip.row == 1) {
        cell.textLabel.text = @"Modèle d'appareil";
        cell.detailTextLabel.text = [IVDeviceIdentity marketingNameForIdentifier:self.chosenModel];
    } else {
        NSString *build = [IVDeviceIdentity buildForIOSVersion:self.chosenIOS];
        cell.textLabel.text = @"Version iOS";
        cell.detailTextLabel.text = build.length
            ? [NSString stringWithFormat:@"%@ (%@)", self.chosenIOS, build]
            : self.chosenIOS;
    }
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    UIView *sel = [UIView new];
    sel.backgroundColor = IVTheme.elevatedSurface;
    cell.selectedBackgroundView = sel;
    return cell;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    if (ip.row == 1) {
        [self pickModel];
    } else if (ip.row == 2) {
        [self pickIOS];
    }
}

- (void)pickModel {
    NSMutableArray<IVListOption *> *opts = [NSMutableArray new];
    for (IVDeviceModel *m in [IVDeviceIdentity modelsForRealChip]) {
        [opts addObject:[IVListOption value:m.identifier title:m.marketingName subtitle:m.identifier]];
    }
    __weak typeof(self) ws = self;
    IVListPickerVC *p = [[IVListPickerVC alloc] initWithTitle:@"Modèle d'appareil"
                                                      options:opts
                                                selectedValue:self.chosenModel
                                                       onPick:^(IVListOption *o) {
        ws.chosenModel = o.value;
        [ws.table reloadData];
    }];
    [self.navigationController pushViewController:p animated:YES];
}

- (void)pickIOS {
    NSMutableArray<IVListOption *> *opts = [NSMutableArray new];
    for (NSString *v in [IVDeviceIdentity iosVersions]) {
        NSString *build = [IVDeviceIdentity buildForIOSVersion:v];
        [opts addObject:[IVListOption value:v title:v subtitle:build.length ? [@"build " stringByAppendingString:build] : nil]];
    }
    __weak typeof(self) ws = self;
    IVListPickerVC *p = [[IVListPickerVC alloc] initWithTitle:@"Version iOS"
                                                      options:opts
                                                selectedValue:self.chosenIOS
                                                       onPick:^(IVListOption *o) {
        ws.chosenIOS = o.value;
        [ws.table reloadData];
    }];
    [self.navigationController pushViewController:p animated:YES];
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; return YES; }

@end
