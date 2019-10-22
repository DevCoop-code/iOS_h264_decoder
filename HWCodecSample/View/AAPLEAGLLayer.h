//
//  AAPLEAGLLayer.h
//  HWCodecSample
//
//  Created by HanGyo Jeong on 06/10/2019.
//  Copyright © 2019 HanGyoJeong. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import <CoreVideo/CoreVideo.h>

#import <AVFoundation/AVUtilities.h>
#import <AVFoundation/AVFoundation.h>
#import <mach/mach_time.h>
#import <UIKit/UIScreen.h>

#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>

NS_ASSUME_NONNULL_BEGIN

@interface AAPLEAGLLayer : CAEAGLLayer

@property CVPixelBufferRef pixelBuffer;
- (id)initWithFrame:(CGRect)frame;
- (void)resetRenderBuffer;

@end

NS_ASSUME_NONNULL_END
