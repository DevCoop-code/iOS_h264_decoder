//
//  MediaFileParser.m
//  HWCodecSample
//
//  Created by HanGyo Jeong on 06/10/2019.
//  Copyright © 2019 HanGyoJeong. All rights reserved.
//

#import "MediaFileParser.h"

//8bit(1byte) unsigned size integer
//For parsing the video when video type is Annex B
const uint8_t KStartCode[4] = {0, 0, 0, 1};

@implementation VideoPacket

- (instancetype)initWithsize:(NSInteger)size
{
    self = [super init];
    self.buffer = malloc(size);
    self.size = size;
    
    return self;
}

- (void)dealloc
{
    free(self.buffer);
}

@end

@interface MediaFileParser(){
    uint8_t *_buffer;
    NSInteger _bufferSize;
    NSInteger _bufferCap;
}
@property NSString *filePath;
@property NSInputStream *fileInputStream;

@end

@implementation MediaFileParser

- (BOOL)open:(NSString *)filePath
{
    _bufferSize = 0;
    _bufferCap = 512 * 1024;        //Buffer Capability
    _buffer = malloc(_bufferCap);
    self.filePath = filePath;
    self.fileInputStream = [NSInputStream inputStreamWithFileAtPath:filePath];
    [self.fileInputStream open];
    
    return YES;
}

- (VideoPacket*)nextPacket
{
    /*
     NSInputStream [hasBytesAvailable]
     Return YES if there is more data to read in the stream, NO if there is not
     */
    if(_bufferSize < _bufferCap && self.fileInputStream.hasBytesAvailable){
        NSLog(@"Read Buffer in bytes");
        NSInteger readBytes = [self.fileInputStream read:_buffer + _bufferSize maxLength:_bufferCap - _bufferSize];
        _bufferSize += readBytes;
    }else{
        NSLog(@"Fail to read buffer");
    }
    
    if(memcmp(_buffer, KStartCode, 4) != 0){
        NSLog(@"This is not Annex B Type format");
        return nil;
    }
    
    if(_bufferSize >= 5){
        uint8_t *bufferBegin = _buffer + 4;
        uint8_t *bufferEnd = _buffer + _bufferSize;
        while(bufferBegin != bufferEnd){
            if(*bufferBegin == 0x1){
                if(memcmp(bufferBegin - 3, KStartCode, 4) == 0){
                    //Pointer Subtraction means how far about pointer to pointer
                    //So bufferBegin - _buffer means how far between buffer begin to buffer size
                    NSInteger packetSize = bufferBegin - _buffer - 3;
                    VideoPacket *vp = [[VideoPacket alloc] initWithsize:packetSize];
                    
                    memcpy(vp.buffer, _buffer, packetSize);
                    
                    memmove(_buffer, _buffer + packetSize, _bufferSize - packetSize);
                    _bufferSize -= packetSize;
                    
                    return vp;
                }
            }
            ++bufferBegin;
        }
    }
    return nil;
}

- (void)close
{
    free(_buffer);
    [self.fileInputStream close];
}
@end
