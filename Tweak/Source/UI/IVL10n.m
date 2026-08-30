//
//  IVL10n.m
//  BadooVault
//
//  Implémentation du système de localisation FR/EN. Définit la langue cible une
//  fois (à la 1re résolution), puis rend les chaînes depuis une table. Repli sûr :
//  langue cible absente -> français (source) -> clé brute jamais.
//

#import "IVL10n.h"
#import <UIKit/UIKit.h>

// Table de traduction : clé -> { langue : chaîne }.
// "fr" est la source (obligatoire). "en" couvre toutes les clés listées afin
// d'éviter les trous d'UI.
static NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *IVL10nTable(void) {
    static NSDictionary *t;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString * (^FR)(NSString *) = ^NSString *(NSString *s) { return s; };
        t = @{
            // ---- FloatingButton ----
            @"fb.accessibilityLabel" : @{ @"fr" : FR(@"Badooscale"), @"en" : @"Badooscale" },
            @"fb.accessibilityHint"  : @{ @"fr" : FR(@"Ouvre la gestion des conteneurs"), @"en" : @"Opens container management" },

            // ---- Panneau principal ----
            @"panel.title"          : @{ @"fr" : FR(@"Badooscale"), @"en" : @"Badooscale" },
            @"panel.footer"         : @{ @"fr" : FR(@"Changer de conteneur actif nécessite un redémarrage de l'app."), @"en" : @"Switching the active container requires restarting the app." },
            @"panel.row.real"       : @{ @"fr" : FR(@"Réel (non isolé)"), @"en" : @"Real (not isolated)" },
            @"panel.active"         : @{ @"fr" : FR(@"Conteneur actif"), @"en" : @"Active container" },
            @"panel.activate"       : @{ @"fr" : FR(@"Activer ce conteneur"), @"en" : @"Activate this container" },
            @"panel.device"         : @{ @"fr" : FR(@"Appareil (infos)"), @"en" : @"Device (info)" },
            @"panel.rename"         : @{ @"fr" : FR(@"Renommer"), @"en" : @"Rename" },
            @"panel.delete"         : @{ @"fr" : FR(@"Supprimer"), @"en" : @"Delete" },
            @"panel.rename.title"   : @{ @"fr" : FR(@"Renommer"), @"en" : @"Rename" },
            @"panel.rename.fail.t"  : @{ @"fr" : FR(@"Renommage impossible"), @"en" : @"Rename failed" },
            @"panel.rename.fail.m"  : @{ @"fr" : FR(@"Nom vide ou écriture disque échouée."), @"en" : @"Empty name or disk write failed." },
            @"panel.active.warn.t"  : @{ @"fr" : FR(@"Conteneur actif"), @"en" : @"Active container" },
            @"panel.active.warn.m"  : @{ @"fr" : FR(@"Bascule sur un autre conteneur avant de le supprimer."), @"en" : @"Switch to another container before deleting it." },
            @"panel.delete.conf"    : @{ @"fr" : FR(@"Supprimer ce conteneur ?"), @"en" : @"Delete this container?" },
            @"panel.delete.msg"     : @{ @"fr" : FR(@"Toutes ses données (comptes, réglages) seront effacées définitivement."), @"en" : @"All its data (accounts, settings) will be permanently erased." },
            @"panel.delete.fail.t"  : @{ @"fr" : FR(@"Suppression impossible"), @"en" : @"Delete failed" },
            @"panel.delete.fail.m"  : @{ @"fr" : FR(@"Le conteneur est actif ou l'écriture disque a échoué."), @"en" : @"The container is active or the disk write failed." },
            @"panel.activated"      : @{ @"fr" : FR(@"Conteneur activé"), @"en" : @"Container activated" },
            @"panel.activated.m"    : @{ @"fr" : FR(@"« %@ » est prêt.\nL'app va se fermer — rouvre-la pour l'utiliser."), @"en" : @"\u00ab %@ \u00bb is ready.\nThe app will close — reopen it to use it." },
            @"panel.fail.t"         : @{ @"fr" : FR(@"Échec"), @"en" : @"Failed" },
            @"panel.fail.lang.m"    : @{ @"fr" : FR(@"Impossible d'enregistrer la langue (écriture disque échouée)."), @"en" : @"Could not save the language (disk write failed)." },
            @"panel.fail.region.m"  : @{ @"fr" : FR(@"Impossible d'enregistrer la région (écriture disque échouée)."), @"en" : @"Could not save the region (disk write failed)." },
            @"panel.fail.active.m"  : @{ @"fr" : FR(@"Impossible d'enregistrer le conteneur actif (écriture disque échouée). Réessaie."), @"en" : @"Could not save the active container (disk write failed). Try again." },

            // ---- Réglages (langue / région) ----
            @"settings.title"       : @{ @"fr" : FR(@"Réglages — %@"), @"en" : @"Settings — %@" },
            @"settings.msg"         : @{ @"fr" : FR(@"Prend effet au prochain démarrage de l'app."), @"en" : @"Takes effect at the next app launch." },
            @"settings.lang"        : @{ @"fr" : FR(@"Langue : %@"), @"en" : @"Language: %@" },
            @"settings.region"      : @{ @"fr" : FR(@"Région : %@"), @"en" : @"Region: %@" },
            @"settings.auto"        : @{ @"fr" : FR(@"Automatique"), @"en" : @"Automatic" },
            @"settings.lang.title"  : @{ @"fr" : FR(@"Langue de l'application"), @"en" : @"App language" },
            @"settings.region.title": @{ @"fr" : FR(@"Pays / région"), @"en" : @"Country / region" },
            @"settings.autoSystem"  : @{ @"fr" : FR(@"Automatique (système)"), @"en" : @"Automatic (system)" },

            // ---- Caméra virtuelle ----
            @"cam.title"            : @{ @"fr" : FR(@"Caméra virtuelle"), @"en" : @"Virtual camera" },
            @"cam.set"              : @{ @"fr" : FR(@"Vidéo de vérification définie ✓ (partagée par tous les conteneurs)"), @"en" : @"Verification video set ✓ (shared by all containers)" },
            @"cam.change"           : @{ @"fr" : FR(@"Changer la vidéo"), @"en" : @"Change video" },
            @"cam.remove"           : @{ @"fr" : FR(@"Retirer la vidéo"), @"en" : @"Remove video" },
            @"cam.unsupported.t"    : @{ @"fr" : FR(@"Indisponible"), @"en" : @"Unavailable" },
            @"cam.unsupported.m"    : @{ @"fr" : FR(@"La sélection de vidéo nécessite iOS 14 ou plus récent."), @"en" : @"Video selection requires iOS 14 or later." },
            @"cam.removed.t"        : @{ @"fr" : FR(@"Vidéo retirée"), @"en" : @"Video removed" },
            @"cam.removed.m"        : @{ @"fr" : FR(@"La caméra virtuelle est désactivée : Badoo utilisera de nouveau la vraie caméra."), @"en" : @"The virtual camera is disabled: Badoo will use the real camera again." },
            @"cam.format.t"         : @{ @"fr" : FR(@"Format non pris en charge"), @"en" : @"Unsupported format" },
            @"cam.format.m"         : @{ @"fr" : FR(@"Choisis une vidéo (.mov ou .mp4)."), @"en" : @"Choose a video (.mov or .mp4)." },
            @"cam.import.t"         : @{ @"fr" : FR(@"Import échoué"), @"en" : @"Import failed" },
            @"cam.import.m"         : @{ @"fr" : FR(@"La vidéo n'a pas pu être copiée. Réessaie."), @"en" : @"The video could not be copied. Try again." },
            @"cam.saved.t"          : @{ @"fr" : FR(@"Vidéo enregistrée"), @"en" : @"Video saved" },
            @"cam.saved.m"          : @{ @"fr" : FR(@"Elle alimentera la caméra native de Badoo lors de la vérification, sur tous les conteneurs. Redémarre l'app pour l'activer."), @"en" : @"It will feed Badoo's native camera during verification, on all containers. Restart the app to activate it." },

            // ---- Appareil (infos) ----
            @"device.iosReal"       : @{ @"fr" : FR(@"iOS : version réelle (non forcée)"), @"en" : @"iOS: real version (not forced)" },
            @"device.iosFmt"        : @{ @"fr" : FR(@"iOS %@%@"), @"en" : @"iOS %@%@" },
            @"device.buildFmt"      : @{ @"fr" : FR(@" (build %@)"), @"en" : @" (build %@)" },
            @"device.identFmt"      : @{ @"fr" : FR(@"Identifiant : %@"), @"en" : @"Identifier: %@" },
            @"device.modelFmt"      : @{ @"fr" : FR(@"N° de modèle : %@"), @"en" : @"Model number: %@" },
            @"device.serialFmt"     : @{ @"fr" : FR(@"N° de série : %@"), @"en" : @"Serial number: %@" },
            @"device.foot"          : @{ @"fr" : FR(@"Ces informations sont celles répondues à Badoo (série et n° de modèle sont indicatifs, affichage seul)."), @"en" : @"This is the information answered to Badoo (serial and model number are indicative, display only)." },
            @"device.close"         : @{ @"fr" : FR(@"Fermer"), @"en" : @"Close" },

            // ---- Réinitialisation ----
            @"reset.confirm"        : @{ @"fr" : FR(@"Tout réinitialiser ?"), @"en" : @"Reset everything?" },
            @"reset.msg"            : @{ @"fr" : FR(@"Déconnecte AUSSI le compte principal : efface tous les cookies et sessions Badoo du téléphone et supprime tous les conteneurs. L'app se fermera. Irréversible."), @"en" : @"ALSO signs out the main account: clears all Badoo cookies and sessions on the phone and removes all containers. The app will close. Irreversible." },
            @"reset.reset"          : @{ @"fr" : FR(@"Réinitialiser"), @"en" : @"Reset" },
            @"reset.done"           : @{ @"fr" : FR(@"Réinitialisé"), @"en" : @"Reset" },
            @"reset.done.m"         : @{ @"fr" : FR(@"Compte déconnecté et données effacées. L'app va se fermer — rouvre-la."), @"en" : @"Account signed out and data cleared. The app will close — reopen it." },
            @"reset.incomplete.t"   : @{ @"fr" : FR(@"Réinitialisation incomplète"), @"en" : @"Incomplete reset" },
            @"reset.incomplete.m"   : @{ @"fr" : FR(@"L'écriture disque a échoué. Réessaie."), @"en" : @"The disk write failed. Try again." },
            @"reset.button"         : @{ @"fr" : FR(@"Tout réinitialiser"), @"en" : @"Reset everything" },

            // ---- Création / édition d'un conteneur ----
            @"create.titleEdit"     : @{ @"fr" : FR(@"Modifier"), @"en" : @"Edit" },
            @"create.titleNew"      : @{ @"fr" : FR(@"Nouveau conteneur"), @"en" : @"New container" },
            @"create.save"          : @{ @"fr" : FR(@"Enregistrer"), @"en" : @"Save" },
            @"create.defaultName"   : @{ @"fr" : FR(@"Conteneur"), @"en" : @"Container" },
            @"create.namePlaceholder": @{ @"fr" : FR(@"Nom du conteneur"), @"en" : @"Container name" },
            @"create.savefail.t"    : @{ @"fr" : FR(@"Échec de l'enregistrement"), @"en" : @"Save failed" },
            @"create.savefail.m"    : @{ @"fr" : FR(@"Le conteneur n'a pas pu être enregistré (écriture disque échouée). Réessaie."), @"en" : @"The container could not be saved (disk write failed). Try again." },
            @"create.modelLabel"    : @{ @"fr" : FR(@"Modèle d'appareil"), @"en" : @"Device model" },
            @"create.iosLabel"      : @{ @"fr" : FR(@"Version iOS"), @"en" : @"iOS version" },
            @"create.iosCellFmt"    : @{ @"fr" : FR(@"%@ (%@)"), @"en" : @"%@ (%@)" },
            @"create.buildFmt"      : @{ @"fr" : FR(@"build %@"), @"en" : @"build %@" },
            @"create.pickModel"     : @{ @"fr" : FR(@"Modèle d'appareil"), @"en" : @"Device model" },
            @"create.pickIOS"       : @{ @"fr" : FR(@"Version iOS"), @"en" : @"iOS version" },
            @"create.footFmt"       : @{ @"fr" : FR(@"Modèles limités à la puce réelle (%@). Chaque conteneur répond ces informations à Badoo."), @"en" : @"Models limited to the real chip (%@). Each container answers this information to Badoo." },

            // ---- Bandeau dégradé ----
            @"degraded.banner"      : @{ @"fr" : FR(@"⚠️ Isolation inactive — vous êtes sur le compte réel. Ne vous connectez pas ici ; fermez complètement l'app puis rouvrez-la."), @"en" : @"⚠️ Isolation inactive — you are on the real account. Do not sign in here; fully close the app then reopen it." },

            // ---- Auto-swipe ----
            @"autoswipe.title"      : @{ @"fr" : FR(@"Auto-swipe"), @"en" : @"Auto-swipe" },
            @"autoswipe.save"       : @{ @"fr" : FR(@"Enregistrer"), @"en" : @"Save" },
            @"autoswipe.phrases"    : @{ @"fr" : FR(@"Phrases envoyées sur un match"), @"en" : @"Messages sent on a match" },
            @"autoswipe.phrasesHint": @{ @"fr" : FR(@"Une phrase par ligne. À chaque match, le bot en envoie une au hasard. Laisse vide pour liker sans écrire."), @"en" : @"One message per line. On each match, the bot sends one at random. Leave empty to like without writing." },
            @"autoswipe.method"     : @{ @"fr" : FR(@"Méthode"), @"en" : @"Method" },
            @"autoswipe.buttons"    : @{ @"fr" : FR(@"Boutons"), @"en" : @"Buttons" },
            @"autoswipe.gestures"   : @{ @"fr" : FR(@"Gestes"), @"en" : @"Gestures" },
            @"autoswipe.methodHint" : @{ @"fr" : FR(@"Boutons : appuie sur le ✕ / ♥ de Badoo (robuste). Gestes : simule un glissement du doigt gauche/droite (repli automatique sur Boutons si indisponible)."), @"en" : @"Buttons: taps Badoo's ✕ / ♥ (robust). Gestures: simulates a left/right finger swipe (falls back to Buttons if unavailable)." },
            @"autoswipe.params"     : @{ @"fr" : FR(@"Paramètres de swipe"), @"en" : @"Swipe settings" },
            @"autoswipe.count"      : @{ @"fr" : FR(@"Nombre de swipes (0 = illimité)"), @"en" : @"Number of swipes (0 = unlimited)" },
            @"autoswipe.like"       : @{ @"fr" : FR(@"% de like (droite)"), @"en" : @"% like (right)" },
            @"autoswipe.dislike"    : @{ @"fr" : FR(@"% de dislike (gauche)"), @"en" : @"% dislike (left)" },
            @"autoswipe.min"        : @{ @"fr" : FR(@"Délai min entre actions (s)"), @"en" : @"Min delay between actions (s)" },
            @"autoswipe.max"        : @{ @"fr" : FR(@"Délai max entre actions (s)"), @"en" : @"Max delay between actions (s)" },
            @"autoswipe.bestEffort" : @{ @"fr" : FR(@"Détection best-effort : le bot agit sur l'UI de Badoo (like/dislike + popup « match »). Selon la version de Badoo, un réglage sur l'appareil peut être nécessaire."), @"en" : @"Best-effort detection: the bot acts on Badoo's UI (like/dislike + \u00ab match \u00bb popup). Depending on the Badoo version, a device setting may be needed." },
            @"autoswipe.stop"       : @{ @"fr" : FR(@"Arrêter l'auto-swipe"), @"en" : @"Stop auto-swipe" },
            @"autoswipe.start"      : @{ @"fr" : FR(@"Démarrer l'auto-swipe"), @"en" : @"Start auto-swipe" },
            @"autoswipe.fail.t"     : @{ @"fr" : FR(@"Échec"), @"en" : @"Failed" },
            @"autoswipe.fail.m"     : @{ @"fr" : FR(@"La configuration n'a pas pu être enregistrée (écriture disque). Réessaie."), @"en" : @"The configuration could not be saved (disk write). Try again." },

            // ---- Carte (GPS) ----
            @"gps.title"            : @{ @"fr" : FR(@"Localisation GPS"), @"en" : @"GPS Location" },
            @"gps.search"           : @{ @"fr" : FR(@"Rechercher une ville…"), @"en" : @"Search a city…" },
            @"gps.activate"         : @{ @"fr" : FR(@"Activer cette position"), @"en" : @"Activate this location" },
            @"gps.clear"            : @{ @"fr" : FR(@"Effacer"), @"en" : @"Clear" },
            @"gps.pin"              : @{ @"fr" : FR(@"Position choisie"), @"en" : @"Chosen position" },
            @"gps.savefail.t"       : @{ @"fr" : FR(@"Échec de l'enregistrement"), @"en" : @"Save failed" },
            @"gps.savefail.m"       : @{ @"fr" : FR(@"La localisation n'a pas pu être enregistrée (écriture disque échouée). Réessaie."), @"en" : @"The location could not be saved (disk write failed). Try again." },

            // ---- Commun ----
            @"common.ok"            : @{ @"fr" : FR(@"OK"), @"en" : @"OK" },
            @"common.cancel"        : @{ @"fr" : FR(@"Annuler"), @"en" : @"Cancel" },
        };
    });
    return t;
}

// Langue cible courante, recalculée à CHAQUE lecture (pas de cache statique),
// pour qu'une bascule FR/EN à l'exécution prenne effet immédiatement sans relance.
// Ordre de résolution :
//   1. Override explicitement choisi par l'utilisateur (bascule FR/EN du menu) —
//      persistant, « IVLOverrideLanguage ».
//   2. Sinon la langue du téléphone (préférences système).
//      « si le téléphone est en français, tout reste en français ».
NSString *IVLCurrentLanguage(void) {
    NSString *lang = nil;
    NSString *ov = [[NSUserDefaults standardUserDefaults] stringForKey:@"IVLOverrideLanguage"];
    if (ov.length) {
        lang = [[ov componentsSeparatedByString:@"-"] firstObject];
    } else {
        // Langue du téléphone (n'utilise PAS la langue spoofée d'un conteneur :
        // la bascule du menu suit la langue réelle de l'appareil).
        NSString *sys = [NSLocale preferredLanguages].firstObject;
        if (sys.length) lang = [[sys componentsSeparatedByString:@"-"] firstObject];
    }
    lang = [lang lowercaseString];
    // Valide contre les langues réellement traduites dans la table.
    static NSSet *known;
    static dispatch_once_t ok;
    dispatch_once(&ok, ^{
        known = [NSSet setWithArray:@[@"fr", @"en"]];
    });
    if (!(lang.length && [known containsObject:lang])) lang = nil; // → repli FR
    return lang;
}

void IVLSetOverrideLanguage(NSString *_Nullable lang) {
    // Persiste l'override ; il est relu à chaque nouvelle exécution.
    [[NSUserDefaults standardUserDefaults] setObject:lang ?: @"" forKey:@"IVLOverrideLanguage"];
}

NSString *IVLL(NSString *key, NSString *fallbackFR) {
    if (!key.length) return fallbackFR ?: @"";
    NSDictionary<NSString *, NSString *> *row = IVL10nTable()[key];
    if (!row) return fallbackFR ?: key;
    NSString *lang = IVLCurrentLanguage();
    // Langue cible d'abord, sinon français (source), sinon clé.
    NSString *hit = row[lang];
    if (!hit.length) hit = row[@"fr"];
    if (!hit.length) hit = fallbackFR ?: key;
    return hit;
}
