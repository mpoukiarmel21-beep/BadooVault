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

Claude Code — port initial + build-1 CI. Prise de main 2026-08-27.

## Prochaine étape

Valider le build-1 sur appareil (Sideloadly, appareil iOS 17+). Depuis Windows,
la CI ne peut que produire l'IPA ; l'install + le test multi-comptes sont manuels.

## Blocages / risques

- Pas d'appareil de test côté agent (Windows) → validation device = humain.
- Base propre `decrypt.day` : pas de dylib mod embarquée → recette CI clean (pas de
  bloc de tri des mods, contrairement à ThreadsVault dont la base était repackée).
- `BPEPushNotificationService.appex` conservée telle quelle ; re-signée par Sideloadly.

## Journal

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
