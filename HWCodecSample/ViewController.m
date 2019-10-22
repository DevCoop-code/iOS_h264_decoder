//
//  ViewController.m
//  HWCodecSample
//
//  Created by HanGyo Jeong on 06/10/2019.
//  Copyright © 2019 HanGyoJeong. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()
{
    uint8_t *_sps;
    NSInteger _spsSize;
    
    uint8_t *_pps;
    NSInteger _ppsSize;
    
    VTDecompressionSessionRef _decoderSession;
    CMVideoFormatDescriptionRef _decoderFormatDescription;
    
    AAPLEAGLLayer *_glLayer;
}

@end

static void didDecompress(void *decompressionOutputRefCon,
                          void *sourceFrameRefCon,
                          OSStatus status,
                          VTDecodeInfoFlags infoFlags,
                          CVImageBufferRef pixelBuffer,
                          CMTime presentationTimeStamp,
                          CMTime presentationDuration)
{
    CVPixelBufferRef *outputPixelBuffer = (CVPixelBufferRef *)sourceFrameRefCon;
    *outputPixelBuffer = CVPixelBufferRetain(pixelBuffer);
}

@implementation ViewController

- (BOOL)initH264Decoder{
    if(_decoderSession){
        return YES;
    }
    
    const uint8_t* const parameterSetPointers[2] = {_sps, _pps};
    const size_t parameterSetSizes[2] = {_spsSize, _ppsSize};
    OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,
                                                                          2,    //param count
                                                                          parameterSetPointers,
                                                                          parameterSetSizes,
                                                                          4,    //NAL start code size
                                                                          &_decoderFormatDescription);
    if(status == noErr){
        CFDictionaryRef attrs = NULL;
        const void *keys[] = { kCVPixelBufferPixelFormatTypeKey };
        /*
         kCVPixelFormatType_420YpCbCr8Planer = YUV420
         kCVPixelFormatType_420YpCbCr8BiPlanarFullRange = NV12
         */
        uint32_t v = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
        const void *values[] = { CFNumberCreate(NULL, kCFNumberSInt32Type, &v) };
        attrs = CFDictionaryCreate(NULL,
                                   keys,
                                   values,
                                   1,
                                   NULL,
                                   NULL);
        
        VTDecompressionOutputCallbackRecord callBackRecord;
        callBackRecord.decompressionOutputCallback = didDecompress;
        callBackRecord.decompressionOutputRefCon = NULL;
        
        status = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                              _decoderFormatDescription,
                                              NULL,
                                              attrs,
                                              &callBackRecord,
                                              &_decoderSession);
        CFRelease(attrs);
    }else{
        NSLog(@"IOS8VT: Reset decoder session failed status = %d", status);
    }
    return YES;
}

- (void)clearH264Decoder{
    if(_decoderSession){
        VTDecompressionSessionInvalidate(_decoderSession);
        CFRelease(_decoderSession);
        _decoderSession = NULL;
    }
    
    if(_decoderFormatDescription){
        CFRelease(_decoderFormatDescription);
        _decoderFormatDescription = NULL;
    }
    free(_sps);
    free(_pps);
    _spsSize = _ppsSize = 0;
}

- (CVPixelBufferRef)decode:(VideoPacket*)vp{
    CVPixelBufferRef outputPixelBuffer = NULL;
    
    CMBlockBufferRef blockBuffer = NULL;
    
    //Creates a new CMBlockBuffer backed by a memory block
    OSStatus status = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,
                                                         (void*)vp.buffer,
                                                         vp.size,
                                                         kCFAllocatorNull,
                                                         NULL,
                                                         0,
                                                         vp.size,
                                                         0,
                                                         &blockBuffer);
    if(status == kCMBlockBufferNoErr){
        /*
         CMSampleBuffer is a Core Foundation object containing zero or more compressed(or uncompressed) samples of a particular media type(audio, video, muxed, and so on)
         */
        CMSampleBufferRef sampleBuffer = NULL;
        const size_t sampleSizeArray[] = {vp.size};
        //Create CMSampleBuffer
        status = CMSampleBufferCreateReady(kCFAllocatorDefault,
                                           blockBuffer,
                                           _decoderFormatDescription,
                                           1,
                                           0,
                                           NULL,
                                           1,
                                           sampleSizeArray,
                                           &sampleBuffer);
        if(status == kCMBlockBufferNoErr && sampleBuffer){
            VTDecodeFrameFlags flags = 0;
            VTDecodeInfoFlags flagOut = 0;
            //Decompresses a video frame
            OSStatus decodeStatus = VTDecompressionSessionDecodeFrame(_decoderSession,
                                                                      sampleBuffer,
                                                                      flags,
                                                                      &outputPixelBuffer,
                                                                      &flagOut);
            if(decodeStatus == kVTInvalidSessionErr){
                NSLog(@"IOS8VT: Invalid session. reset decoder session");
            }else if(decodeStatus == kVTVideoDecoderBadDataErr){
                NSLog(@"IOS8VT: decode failed status = %d(Bad data)", decodeStatus);
            }else if(decodeStatus != noErr){
                NSLog(@"IOS8VT: decode failed status = %d", decodeStatus);
            }
            CFRelease(sampleBuffer);
        }
        CFRelease(blockBuffer);
    }
    return outputPixelBuffer;
}

- (void)decodeFile:(NSString*)fileName fileExt:(NSString*)fileExt{
    NSString *path = [[NSBundle mainBundle] pathForResource:fileName ofType:fileExt];
    NSLog(@"video file path : %@", path);
    MediaFileParser *parser = [MediaFileParser alloc];
    [parser open:path];
    
    VideoPacket *vp = nil;
    while(true){
        vp = [parser nextPacket];
        if(vp == nil){
            NSLog(@"Video packet is nil");
            break;
        }
        
        uint32_t nalSize = (uint32_t)(vp.size - 4);
        uint8_t *pNalSize = (uint8_t*)(&nalSize);
        vp.buffer[0] = *(pNalSize + 3);
        vp.buffer[1] = *(pNalSize + 2);
        vp.buffer[2] = *(pNalSize + 1);
        vp.buffer[3] = *(pNalSize + 0);
        
        CVPixelBufferRef pixelBuffer = NULL;
        int nalType = vp.buffer[4] & 0x1F;
        switch (nalType) {
            case 0x05:
                NSLog(@"Nal type is IDR frame");
                if([self initH264Decoder]){
                    pixelBuffer = [self decode:vp];
                }
                break;
            case 0x07:
                NSLog(@"Nal type is SPS");
                _spsSize = vp.size - 4;
                _sps = malloc(_spsSize);
                memcpy(_sps, vp.buffer + 4, _spsSize);
                break;
            case 0x08:
                NSLog(@"Nal type is PPS");
                _ppsSize = vp.size - 4;
                _pps = malloc(_ppsSize);
                memcpy(_pps, vp.buffer + 4, _ppsSize);
                break;
                
            default:
                NSLog(@"Nal type is B/P frame");
                pixelBuffer = [self decode:vp];
                break;
        }
        
        if(pixelBuffer){
            dispatch_sync(dispatch_get_main_queue(), ^{
                _glLayer.pixelBuffer = pixelBuffer;
            });
            
            CVPixelBufferRelease(pixelBuffer);
        }
        NSLog(@"Read Nalu size %ld", vp.size);
    }
    [parser close];
}

# pragma mark - Button Actin

- (IBAction)on_playButton_clicked:(id)sender {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [self decodeFile:@"bunny" fileExt:@"h264"];
    });
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _glLayer = [[AAPLEAGLLayer alloc] initWithFrame:self.view.bounds];
    [self.view.layer addSublayer:_glLayer];
}

- (void)didReceiveMemoryWarning{
    [super didReceiveMemoryWarning];
}

@end
