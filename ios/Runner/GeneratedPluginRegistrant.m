//
//  Generated file. Do not edit.
//

// clang-format off

#import "GeneratedPluginRegistrant.h"

#if __has_include(<camera_avfoundation/CameraPlugin.h>)
#import <camera_avfoundation/CameraPlugin.h>
#else
@import camera_avfoundation;
#endif

#if __has_include(<gal/GalPlugin.h>)
#import <gal/GalPlugin.h>
#else
@import gal;
#endif

#if __has_include(<google_mlkit_commons/GoogleMlKitCommonsPlugin.h>)
#import <google_mlkit_commons/GoogleMlKitCommonsPlugin.h>
#else
@import google_mlkit_commons;
#endif

#if __has_include(<google_mlkit_pose_detection/GoogleMlKitPoseDetectionPlugin.h>)
#import <google_mlkit_pose_detection/GoogleMlKitPoseDetectionPlugin.h>
#else
@import google_mlkit_pose_detection;
#endif

@implementation GeneratedPluginRegistrant

+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {
  [CameraPlugin registerWithRegistrar:[registry registrarForPlugin:@"CameraPlugin"]];
  [GalPlugin registerWithRegistrar:[registry registrarForPlugin:@"GalPlugin"]];
  [GoogleMlKitCommonsPlugin registerWithRegistrar:[registry registrarForPlugin:@"GoogleMlKitCommonsPlugin"]];
  [GoogleMlKitPoseDetectionPlugin registerWithRegistrar:[registry registrarForPlugin:@"GoogleMlKitPoseDetectionPlugin"]];
}

@end
