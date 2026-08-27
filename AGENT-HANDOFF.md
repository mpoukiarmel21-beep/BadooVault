# AGENT-HANDOFF.md — BadooVault

> Point de liaison multi-agents. Lis-moi avant de travailler. Entrées de Journal
> datées, plus récentes en haut, jamais réécrites.

## État actuel

**BadooVault** = portage propre de ThreadsVault/InstaVault v2 sur **Badoo**
(`com.badoo.Badoo`, base 5.467.0). Moteur de tweak identique (substrate-free,
`LIBRARY_NAME`, fishhook + `method_setImplementation`), symboles internes `IV*`
inchangés car agnostiques de l'app hôte. Objectif : conteneurs isolés
(« téléphones distincts »), login persistant par conteneur, faux GPS + spoof
device/locale, bouton flottant + menu Liquid Glass sombre, reset/suppression
propres, anti-corrélation inter-conteneurs.

Forensics Badoo confirmé **classe lenient (Instagram/Threads)** : binaire décrypté
(`LC_ENCRYPTION_INFO` absent), **aucune gate d'intégrité au lancement** (App Attest /
DeviceCheck / ptrace / csops / CS_VALID absents), détection JB = télémétrie souple.
Sécurité forte = serveur/compte (ArkoseLabs, Veriff selfie, Prove KYC, DeviceAuth,
keypair FBSDK). Détail : `docs/audit/2026-08-27-badoo-forensics.md`.

Architecture = **4 redirections atomiques** (comme ThreadsVault, car Badoo a un
App Group `group.com.badoo.Badoo`) : #1 HOME, #2 Keychain (HIDE défaut), #3
CFPreferences, #4 App Group (`IVAppGroupHook`, swizzle *dynamique* — s'adapte au
group de Badoo sans code en dur). Parité complète reprise : P1/A/B/C/R2/P3.

## En cours

Personne. build-5 en cours de CI : **refonte** de la présentation du bouton
flottant (fenêtre unique persistante) pour tuer la série de bugs tap/menu.
Créneau libre après la CI verte.

## Prochaine étape

**Valider build-5 sur appareil** (Sideloadly, iOS 17+). Vérifie : (1) un tap sur
le bouton flottant OUVRE le menu de gestion des conteneurs à chaque fois ; (2) le
bouton revient bien à la fermeture (bouton Close) et au swipe-down ; (3) plus de
« le bouton disparaît puis revient tout seul et le 2e tap ne fait rien ». Puis
re-valider le Reset élargi de build-3. Depuis Windows la CI ne fait que produire
l'IPA ; l'install + le test restent manuels (côté humain).

## Blocages / risques

- Pas d'appareil de test côté agent (Windows) → validation device = humain.
- Base propre `decrypt.day` : pas de dylib mod embarquée → recette CI clean (pas de
  bloc de tri des mods, contrairement à ThreadsVault dont la base était repackée).
- `BPEPushNotificationService.appex` conservée telle quelle ; re-signée par Sideloadly.

## Journal

### 2026-08-27 — Claude Code — build-5 : refonte présentation bouton (fenêtre unique)

Rapport appareil : « quand j'ai cliqué dessus, le bouton a disparu, ensuite c'est
revenu quelques secondes [après] et quand je réplique dessus y a rien qui se
passe, y a pas le menu qui s'affiche ». Troisième symptôme de la série tap/menu
(après build-2 tap mort et build-4 fenêtre 0×0) → règle « échoué deux fois =
changer d'approche » : on abandonne le patch incrémental et on refond la
présentation.

Diagnostic (cause racine, vérifiée dans le code) : l'ancienne archi à **deux
fenêtres** (petite fenêtre-bouton `IVOverlayWindow` Alert+1 + fenêtre jetable
`IVPresentationWindow` Normal+3 recréée à chaque tap) avait plusieurs coutures
fragiles. Celle du rapport : `-[IVFloatingButton show]` est appelée à **chaque**
`UIApplicationDidBecomeActive` (voir `Bootstrap.m:26`) et fait
`if (self.window) { self.window.hidden = NO; return; }`. Présenter la feuille
faisait re-déclencher un DidBecomeActive → `show` **ré-affichait le bouton tout
seul** SANS passer par `teardownPresentation`, donc `presWindow`/`presentedNav`
restaient non-nil → le garde d'entrée de `onTap` (`if (self.presWindow || …)
return;`) bloquait tout tap suivant. D'où exactement « revient quelques secondes
après, puis 2e tap mort ».

Correctif (refonte de `Tweak/Source/UI/IVFloatingButton.m`, API publique
`+shared/-show/-hide` inchangée ; 126 insertions / 145 suppressions) : **une seule
fenêtre plein écran persistante**. `IVOverlayWindow` couvre toute la scène
(`w.frame = scene.coordinateSpace.bounds`), transparente, `hitTest` en
passthrough SAUF (a) le bouton et (b) quand le panneau est présenté (alors toute
la fenêtre devient vivante pour que la feuille reçoive les touches). Le bouton
n'est plus une fenêtre mais un **sous-vue** (`container`) du rootVC stable ; le
panneau `IVPanelVC` est présenté sur CE rootVC (plus de 2e fenêtre à
dimensionner/retenir/rendre key/fuiter). Le garde d'entrée lit désormais l'état
UIKit **vivant** (`host.presentedViewController`) → il ne peut plus rester
« collé ». Le bouton est masqué (`container.hidden = YES`) uniquement dans le
completion du present (jamais avant → pas de bouton fantôme si le present
échouait) et restauré dans `teardownPresentation` (idempotent). `show` ne touche
plus JAMAIS la visibilité du bouton (seulement celle de la fenêtre) → une
ré-activation ne peut plus le ré-afficher par-dessus un menu vivant. La fenêtre
devient key pendant la présentation (clavier des champs rename/create) et rend la
main à la fenêtre de l'app au dismiss (`previousKeyWindow`). Supprimé :
`IVPresentationWindow`, `IVActiveWindowScene`, les propriétés `presWindow` /
`presentedNav`. Drag/persistance adaptés (déplacent `container.center` dans le
rootVC plein écran, insets lus sur notre propre fenêtre).

Reste : build CI + publication IPA build-5, puis validation appareil (humain).



Rapport appareil : « quand j'appuie dessus le bouton disparaît » — le tap faisait
disparaître le bouton flottant mais le menu de gestion des conteneurs
n'apparaissait pas (tap mort).

Diagnostic : dans `IVFloatingButton.m -onTap`, la fenêtre de présentation
`IVPresentationWindow` était créée par `initWithWindowScene:` **sans jamais fixer
son `frame`**. Contrairement à ce que disait le commentaire, `initWithWindowScene:`
ne dimensionne PAS la fenêtre : elle naît à `CGRectZero`. `makeKeyAndVisible`
affichait donc une fenêtre 0×0, et la page-sheet présentée depuis son rootVC
n'avait aucune place pour se dessiner. Le bloc de complétion du present se
déclenchait quand même (le present « réussit »), donc le bouton se cachait
(`ws.window.hidden = YES`) alors qu'aucun menu n'était visible → exactement le
symptôme rapporté.

Correctif (1 fichier, `Tweak/Source/UI/IVFloatingButton.m`, `-onTap` uniquement,
API publique `+shared/-show/-hide` inchangée) : après l'init, on fixe
explicitement `pw.frame = scene.coordinateSpace.bounds` (repli sur
`UIScreen.mainScreen.bounds` si vide) avant `windowLevel`/`makeKeyAndVisible`. La
fenêtre couvre alors toute la scène, la page-sheet s'affiche, et le bouton ne se
cache que derrière un menu réellement présent. Commentaire trompeur corrigé.

Reste : build CI + publication IPA build-4, puis validation appareil (humain).


### 2026-08-27 — Claude Code — build-3 : Reset déconnecte vraiment + purge conteneur renforcée

Rapport appareil : (1) après réinstall on retombe sur le conteneur par défaut
déjà connecté (persistance keychain iOS au réinstall = comportement iOS attendu,
non corrigeable côté tweak) ; (2) « quand je clique sur réinitialiser, le compte
ne disparaît pas *toujours* » ; (3) supprimer un conteneur doit effacer la
totalité du cache + cookies + stockage du bloc, en isolation.

Diagnostic : le Reset ne nettoyait que `Library/{Cookies,HTTPStorages,WebKit}` du
compte réel + keychain non-synchronizable + jar cookies live. Il **manquait** les
surfaces où Badoo garde réellement l'état « encore connecté » : NSUserDefaults
(`Library/Preferences/com.badoo.Badoo.plist`, avec cache cfprefsd vivant qui
re-persiste par-dessus un simple `rm` → d'où l'intermittence), la DB de compte
locale (`Library/Application Support`), le cache (`Library/Caches`), et les items
keychain **synchronizable** (iCloud Keychain).

Corrections (3 fichiers) :
- `Tweak/Source/Core/IVPaths.m` — `wipeRealSessionFiles` élargi : ajoute `Caches`
  et `Application Support` aux dossiers supprimés, et efface toutes les *.plist de
  Preferences appartenant à Badoo (tout sauf `com.apple.*` / `.GlobalPreferences`).
  Ne touche jamais `Documents/BadooVault` (control plane) ni `Documents/Instances`
  (conteneurs), disjoints de Library.
- `Tweak/Source/Core/IVContainerStore.m` — `resetAll` ajoute une étape (4) : flush
  live de NSUserDefaults via `removePersistentDomainForName:` (domaine bundle) +
  `synchronize`, pour que cfprefsd ne re-persiste pas la session par-dessus les
  plists tout juste effacées (tue l'intermittence). Ordre conservé, puis cold-close
  existant (`IVCloseAppForSwitch`).
- `Tweak/Source/Isolation/IVKeychainHook.m` — `purgeItemsWithPrefix:`,
  `countItemsWithPrefix:` et `purgeRealPasswordItems` : ajout de
  `kSecAttrSynchronizable = kSecAttrSynchronizableAny` aux requêtes d'énumération,
  pour attraper aussi les items iCloud-Keychain (sinon un token de login
  synchronizable survivait au reset). Renforce aussi la purge par-conteneur.

Delete conteneur : déjà complet et isolé — `removeItemAtPath:Instances/<cid>`
efface tout l'arbre du bloc (HOME + Prefs + AppGroup redirigés dessous : Caches,
Cookies, WebKit, HTTPStorages, Preferences, Application Support, AppGroups, tmp)
+ purge keychain `IV:<cid>:` (désormais SynchronizableAny). Aucun autre conteneur
touché. Pas de nouveau code nécessaire, seulement renforcé par le SynchronizableAny.

Reste : build CI + publication IPA build-3, puis validation appareil (humain).


### 2026-08-27 — Claude Code — build-2 : bouton flottant redesigné + tap réparé

- Rapport appareil : « le bouton apparaît mais tout blanc et pas bien designé ;
  au tap rien ne se passe ». Deux bugs corrigés dans
  `Tweak/Source/UI/IVFloatingButton.m` (API publique `+shared/-show/-hide`
  inchangée, changements internes uniquement).
- **Blanc / mal designé** : le fond `UIGlassEffect` (via `IVGlass`) rendait
  quasi-transparent/blanc sur certains builds et avait une taille ambiguë
  (vue autolayout positionnée au frame). Remplacé par un disque violet
  déterministe — `CAGradientLayer` accent→accentDeep en diagonale + gloss
  spéculaire blanc en haut (α0.38→0) + liseré hairline 1pt, glow violet et
  icône SF blanche conservés. Import `IVGlass.h` retiré (plus utilisé ici).
- **Rien au tap** : présentation faite sur le top VC de Badoo → UIKit droppait
  silencieusement quand ce VC était occupé. Désormais on présente sur notre
  PROPRE fenêtre plein écran `IVPresentationWindow` (niveau `UIWindowLevelNormal+3`,
  `initWithWindowScene:`, rootVC transparent, `makeKeyAndVisible`) : jamais
  occupée → le tap ouvre toujours le menu. `teardownPresentation` (idempotent)
  restaure le bouton et libère la fenêtre au close/swipe-dismiss.
- Commit `5d71485` poussé sur `master`. Run CI `33076645591` (run #2) **success**
  (1m50s). Release `build-2` + asset `BadooVault.ipa` (81 843 402 o) publié :
  `https://github.com/mpoukiarmel21-beep/BadooVault/releases/download/build-2/BadooVault.ipa`
- Reste : validation appareil (humain, Sideloadly).

### 2026-08-27 — Claude Code — build-1 CI VERTE, IPA publiée

- Run `33073720990` **success** (2m14s). Release `build-1` créée, asset
  `BadooVault.ipa` (81 842 479 o, sha256 5d3e0a1e…c4f2) uploadé.
- URL : `https://github.com/mpoukiarmel21-beep/BadooVault/releases/download/build-1/BadooVault.ipa`
- Recette CI clean confirmée fonctionnelle sur base propre `decrypt.day` : dylib
  substrate-free buildée, injectée (`insert_dylib --strip-codesig`), re-signée ad-hoc,
  re-zippée. Aucun bloc de tri de mods nécessaire (aucune dylib mod embarquée).
- Reste : validation appareil (humain, Sideloadly).

### 2026-08-27 — Claude Code — Port initial BadooVault (build-1)

- Recherche sécurité Badoo + forensics binaire (voir docs/audit). Verdict : lenient,
  4-redirections applicables, shield anti-tamper TinderVault volontairement **exclu**
  du build-1 (aucune gate au lancement → risque sans bénéfice).
- Copie de l'arbre ThreadsVault → BadooVault, rebrand mécanique ordonné
  (`ThreadsVault`→`BadooVault`, `Threads`→`Badoo`, `Whamscale`→`Badooscale`,
  `com.burbn.barcelona`→`com.badoo.Badoo`, `444.0.0`→`5.467.0`). Symboles `IV*` gardés.
- `Makefile` : `LIBRARY_NAME=BadooVault` → dylib `BadooVault.dylib`.
- `.github/workflows/build.yml` réécrit sur la recette *clean* InstaVault (device-validée)
  + logique de download robuste de ThreadsVault (normalise vers `Input.ipa`).
- Docs ThreadsVault-spécifiques périmées supprimées ; forensics Badoo fraîche ajoutée ;
  `docs/decisions/001-substrate-free.md` conservée (rebrandée).
- Reste : `git init`, repo public `mpoukiarmel21-beep/BadooVault`, upload IPA base en
  release `v1.0-ipa`, push, `gh workflow run build.yml -f ipa_url=v1.0-ipa`, poll vert.
