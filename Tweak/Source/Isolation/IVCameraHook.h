#import <Foundation/Foundation.h>

@class IVContainer;

NS_ASSUME_NONNULL_BEGIN

/// Per-container virtual camera.
///
/// When a container has a verification video configured (IVContainer.cameraVideoPath),
/// this feeds that video's frames INTO Badoo's own native capture pipeline instead
/// of the real camera — for the passive photo / pose "Photo Verification" and
/// profile-photo capture. It works entirely in-process, substrate-free:
///
///   1. Swizzle `-[AVCaptureVideoDataOutput setSampleBufferDelegate:queue:]` so we
///      learn the concrete delegate class Badoo installs the moment it wires up the
///      camera (which only happens on a user verification action, always AFTER we
///      install at launch).
///   2. Swizzle that delegate class's
///      `-captureOutput:didOutputSampleBuffer:fromConnection:`. On every real camera
///      frame we replace the frame's image buffer with the next frame decoded from
///      the chosen video (scaled/cropped to the exact incoming geometry + pixel
///      format, original timing preserved) and forward THAT to Badoo. The video is
///      looped seamlessly.
///
/// DEFENSIVE BY DESIGN: any failure at any step (missing frameworks, decode error,
/// geometry mismatch, buffer alloc failure) falls through to Badoo's UNTOUCHED real
/// frame — the hook must never crash or freeze Badoo's camera.
///
/// HONEST LIMITS (in-process, no jailbreak):
///   * Feeds Badoo's OWN native AVFoundation camera only. It does NOT reach the
///     Veriff ID/age KYC selfie, which runs getUserMedia inside a WebView in a
///     separate process — unreachable by an in-process hook.
///   * The live on-screen preview (AVCaptureVideoPreviewLayer) is driven by the OS
///     compositor from the hardware feed, so it may still show the REAL camera even
///     while the frames DELIVERED to Badoo are the video.
///
/// Idempotent; gated to isolated containers only.
@interface IVCameraHook : NSObject

/// Install for the active isolated container. No-op unless `container.cameraVideoPath`
/// resolves to a readable file. Idempotent; call once from Bootstrap under the
/// `isolated` gate.
+ (void)installForContainer:(IVContainer *)container;

@end

NS_ASSUME_NONNULL_END
