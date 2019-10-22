//
//  MediaFileParser.h
//  HWCodecSample
//
//  Created by HanGyo Jeong on 06/10/2019.
//  Copyright © 2019 HanGyoJeong. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface VideoPacket : NSObject

@property uint8_t *buffer;
@property NSInteger size;

@end

@interface MediaFileParser : NSObject

- (BOOL)open:(NSString*)filePath;
- (VideoPacket*)nextPacket;
- (void)close;

@end

NS_ASSUME_NONNULL_END
