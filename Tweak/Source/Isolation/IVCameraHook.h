#import <Foundation/Foundation.h>

@class IVContainer;

NS_ASSUME_NONNULL_BEGIN

/// Global virtual camera (shared by ALL containers).
///
/// When a global verification video is configured ([IVPaths globalCameraVideoPath]),
/// this feeds that video INTO Badoo's own native capture pipeline instead of the real
/// camera — for the passive photo / pose "Photo Verification" and profile-photo
/// capture. It works entirely in-process, substrate-free, and covers BOTH what Badoo
/// analyzes AND what the user sees on screen:
///
///   1. DATA PATH — swizzle `-[AVCaptureVideoDataOutput setSampleBufferDelegate:queue:]`
///      to learn the concrete delegate class Badoo installs the moment it wires up the
///      camera, then swizzle that delegate's
///      `-captureOutput:didOutputSampleBuffer:fromConnection:`. On every real camera
///      frame we replace the image buffer with the next frame decoded from the video
///      (scaled/cropped to the exact incoming geometry + pixel format, original timing
///      preserved) and forward THAT to Badoo. The video loops seamlessly.
///   2. PREVIEW PATH — swizzle `-[AVCaptureVideoPreviewLayer setSession:]` so the
///      instant Badoo shows a live preview we lay an AVPlayerLayer (looping the same
///      video, aspect-fill) OVER it. This is what makes the user SEE the video instead
///      of the real camera; the overlay is kept sized to the preview via a
///      `layoutSublayers` swizzle.
///
/// A single global video is shared by every container by design (the user swaps the
/// file to verify a different account) — state = the mere existence of the file, no
/// per-container flag.
///
/// DEFENSIVE BY DESIGN: any failure at any step (missing frameworks, decode error,
/// geometry mismatch, buffer alloc failure) falls through to Badoo's UNTOUCHED real
/// frame / real preview — the hook must never crash or freeze Badoo's camera.
///
/// HONEST LIMITS (in-process, no jailbreak):
///   * Feeds Badoo's OWN native AVFoundation camera only. It does NOT reach the
///     Veriff ID/age KYC selfie, which runs getUserMedia inside a WebView in a
///     separate process — unreachable by an in-process hook.
///   * The still-photo path via AVCapturePhotoOutput yields an immutable AVCapturePhoto
///     whose pixels can't be swapped in place; verification flows that rely on the
///     continuous video-data stream (the common passive/pose check) ARE covered.
@interface IVCameraHook : NSObject

/// Install the global virtual camera. No-op unless a global verification video exists
/// ([IVPaths hasGlobalCameraVideo]). Idempotent; call once from Bootstrap
/// UNCONDITIONALLY at launch (NOT under the isolation gate — the camera is global).
+ (void)installGlobal;

@end

NS_ASSUME_NONNULL_END
