#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Resolves every path BadooVault needs, distinguishing:
///   - realHome     : the app's true sandbox home, captured BEFORE any HOME
///                    redirect (== NSHomeDirectory() at the first line of the
///                    constructor). All shared control files live here.
///   - container root: <realHome>/Documents/Instances/<cid>/  (the redirected
///                    HOME for a non-default container).
///
/// IMPORTANT: after the HOME redirect, NSHomeDirectory() points inside the
/// active container. Never use NSHomeDirectory() to reach the shared control
/// files — always go through +realHome. This is the BUG-01 class of failure.
@interface IVPaths : NSObject

/// Capture the real home. MUST be the first thing the constructor calls,
/// before any setenv. Idempotent.
+ (void)captureRealHome;

/// The true app sandbox home (un-redirected). Falls back to NSHomeDirectory()
/// if capture somehow didn't run.
+ (NSString *)realHome;

/// <realHome>/Documents/BadooVault  (shared control dir; created on demand).
+ (NSString *)controlDir;

/// <realHome>/Documents/BadooVault/containers.plist
+ (NSString *)containersFile;

/// <realHome>/Documents/BadooVault/active.plist
+ (NSString *)activeFile;

/// <realHome>/Documents/Instances/<cid>  (a non-default container's HOME root).
+ (NSString *)containerRootForCID:(NSString *)cid;

/// Create the skeleton dirs (Documents, Library, Library/Caches,
/// Library/Preferences, tmp) under a container root. Returns NO + logs on failure.
+ (BOOL)ensureSkeletonAtRoot:(NSString *)root;

/// Recursively re-stamp every file/dir under `root` to the lock-readable
/// protection class (CompleteUntilFirstUserAuthentication). Badoo writes new
/// session files under an isolated container inheriting NSFileProtectionComplete
/// (unreadable while locked) → a background relaunch during a lock reads them as
/// empty and the container looks logged out. Call this after isolation and on
/// every background transition, on the isolated-container root ONLY — never the
/// real sandbox. Best-effort, never aborts.
+ (void)reapplyProtectionRecursivelyAtRoot:(NSString *)root;

/// Wipe the DEFAULT/real account's on-disk session surfaces —
/// realHome/Library/{Cookies,HTTPStorages,WebKit}. Used by a global reset so the
/// principal account is logged out too, not just the containers. Leaves Caches
/// and the control plane (Documents/BadooVault) untouched. Returns NO if a
/// surface existed but could not be removed.
+ (BOOL)wipeRealSessionFiles;

@end

NS_ASSUME_NONNULL_END
