//
//  AAPLEAGLLayer.m
//  HWCodecSample
//
//  Created by HanGyo Jeong on 06/10/2019.
//  Copyright © 2019 HanGyoJeong. All rights reserved.
//

#import "AAPLEAGLLayer.h"

//Uniform index.
enum
{
    UNIFORM_Y,
    UNIFORM_UV,
    UNIFORM_ROTATION_ANGLE,
    UNIFORM_COLOR_CONVERSION_MATRIX,
    NUM_UNIFORMS
};
GLint uniforms[NUM_UNIFORMS];

//Attribute index
enum
{
    ATTRIB_VERTEX,
    ATTRIB_TEXCOORD,
    NUM_ATTRIBUTES
};

/*
 Color Conversion Constants(YUV to RGB) including adjustment from 16-235/16-240 (video range)
 */
//BT.601, which is the standard for SDTV
static const GLfloat kColorConversion601[] = {
    1.164, 1.164, 1.164,
    0.0, -0.392, 2.017,
    1.596, -0.813, 0.0
};

//BT.701, which is the standard for HDTV
static const GLfloat kColorConversion709[] = {
    1.164, 1.164, 1.164,
    0.0, -0.213, 2.112,
    1.793, -0.533, 0.0
};

@interface AAPLEAGLLayer()
{
    //The pixel dimensions of the CAEAGLLayer
    GLint _backingWidth;
    GLint _backingHeight;
    
    EAGLContext *_context;
    CVOpenGLESTextureRef _lumaTexture;
    CVOpenGLESTextureRef _chromaTexture;
    
    GLuint _frameBufferHandle;
    GLuint _colorBufferHandle;
    
    const GLfloat *_preferredConversion;
}
@property GLuint program;

@end

@implementation AAPLEAGLLayer

@synthesize pixelBuffer = _pixelBuffer;

- (CVPixelBufferRef)pixelBuffer
{
    return _pixelBuffer;
}

- (void)setPixelBuffer:(CVPixelBufferRef)pixelBuffer
{
    if(_pixelBuffer){
        CVPixelBufferRelease(_pixelBuffer);
    }
    //Retain the pixel buffer
    _pixelBuffer = CVPixelBufferRetain(pixelBuffer);
    
    int frameWidth = (int)CVPixelBufferGetWidth(_pixelBuffer);
    int frameHeight = (int)CVPixelBufferGetHeight(_pixelBuffer);
    [self displayPixelBuffer:_pixelBuffer width:frameWidth height:frameHeight];
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super init];
    if(self){
        CGFloat scale = [[UIScreen mainScreen]scale];
        self.contentsScale = scale;
        
        self.opaque = TRUE;
        self.drawableProperties = @{ kEAGLDrawablePropertyRetainedBacking :[NSNumber numberWithBool:YES] };
        
        [self setFrame:frame];
        
        //Set the context into which the frames will be drawn
        _context = [[EAGLContext alloc]initWithAPI:kEAGLRenderingAPIOpenGLES2];
        
        if(!_context){
            return nil;
        }
        
        //Set the default conversion to BT.709, which is the standard for HDTV
        _preferredConversion = kColorConversion709;
        
        [self setupGL];
    }
    return self;
}

- (void)displayPixelBuffer:(CVPixelBufferRef)pixelBuffer width:(uint32_t)frameWidth height:(uint32_t)frameHeight
{
    if(!_context || ![EAGLContext setCurrentContext:_context]){
        return;
    }
    
    if(pixelBuffer == NULL){
        NSLog(@"Pixel buffer is null");
        return;
    }
    
    CVReturn err;
    
    //Returns number of planes of the pixel buffer
    size_t planeCount = CVPixelBufferGetPlaneCount(pixelBuffer);
    
    /*
     Use the color attachment of the pixel buffer to determine the appropriate color conversion matrix
     */
    CFTypeRef colorAttachments = CVBufferGetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, NULL);
    if(CFStringCompare(colorAttachments, kCVImageBufferYCbCrMatrix_ITU_R_601_4, 0) == kCFCompareEqualTo){
        _preferredConversion = kColorConversion601;
    }else{
        _preferredConversion = kColorConversion709;
    }
    
    /*
     CVOpenGLESTextureCacheCreateTextureFromImage will create GLES texture optimally from CVPixelBufferRef
     */
    
    /*
     Create Y and UV textures from the pixel buffer. These textures will be drawn on the frame buffer Y-plane.
     */
    CVOpenGLESTextureCacheRef _videoTextureCache;
    
    //Create CVOpenGLESTextureCacheRef for optimal CVPixelBufferRef to GLES texture conversion
    err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault,
                                       NULL,
                                       _context,
                                       NULL,
                                       &_videoTextureCache);
    if(err != noErr){
        NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
        return;
    }
    
    glActiveTexture(GL_TEXTURE0);
    err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                       _videoTextureCache,
                                                       pixelBuffer,
                                                       NULL,
                                                       GL_TEXTURE_2D,
                                                       GL_RED_EXT,
                                                       frameWidth,
                                                       frameHeight,
                                                       GL_RED_EXT,
                                                       GL_UNSIGNED_BYTE,
                                                       0,
                                                       &_lumaTexture);
    if(err){
        NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
    }
    glBindTexture(CVOpenGLESTextureGetTarget(_lumaTexture), CVOpenGLESTextureGetName(_lumaTexture));
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    if(planeCount == 2){
        //UV-plane
        glActiveTexture(GL_TEXTURE1);
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                           _videoTextureCache,
                                                           pixelBuffer,
                                                           NULL,
                                                           GL_TEXTURE_2D, GL_RG_EXT,
                                                           frameWidth / 2,
                                                           frameHeight / 2,
                                                           GL_RG_EXT,
                                                           GL_UNSIGNED_BYTE,
                                                           1,
                                                           &_chromaTexture);
        if (err) {
            NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
        }
        
        glBindTexture(CVOpenGLESTextureGetTarget(_chromaTexture), CVOpenGLESTextureGetName(_chromaTexture));
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    }
    
    glBindFramebuffer(GL_FRAMEBUFFER, _frameBufferHandle);
    
    //Set the view port to the entire view
    //Specify where to print the image in the window
    //(x,y) -> Left-Bottom coordinate
    glViewport(0, 0, _backingWidth, _backingHeight);
    
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    
    glUseProgram(self.program);
    
    //Specify the value of a uniform variable
    glUniform1f(uniforms[UNIFORM_ROTATION_ANGLE], 0);
    glUniformMatrix3fv(uniforms[UNIFORM_COLOR_CONVERSION_MATRIX], 1, GL_FALSE, _preferredConversion);
    
    //Set up the quad vertices with respect to the orientation and aspect ratio of the video
    CGRect viewBounds = self.bounds;
    //Returns a size with the specified dimension values
    CGSize contentSize = CGSizeMake(frameWidth, frameHeight);
    //Returns a scaled rectangle that maintains the specified aspect ratio within a bounding rectangle
    CGRect vertexSamplingRect = AVMakeRectWithAspectRatioInsideRect(contentSize, viewBounds);
    
    //Compute normalized quad coordinates to draw the frame into
    CGSize normalizedSamplingSize = CGSizeMake(0.0, 0.0);
    CGSize cropScaleAmount = CGSizeMake(vertexSamplingRect.size.width/viewBounds.size.width,
                                        vertexSamplingRect.size.height/viewBounds.size.height);
    
    //Normalize the quad vertices
    if(cropScaleAmount.width > cropScaleAmount.height){
        normalizedSamplingSize.width = 1.0;
        normalizedSamplingSize.height = cropScaleAmount.height/cropScaleAmount.width;
    }
    else{
        normalizedSamplingSize.width = cropScaleAmount.width/cropScaleAmount.height;
        normalizedSamplingSize.height = 1.0;
    }
    
    /*
     The quad vertex data defines the region of 2D plane onto which we draw our pixel buffers.
     Vertex data formed using (-1,-1) and (1,1) as the bottom left and top right coordinates respectively, covers the entire screen.
     */
    GLfloat quadVertexData[] = {
        -1 * normalizedSamplingSize.width, -1 * normalizedSamplingSize.height,
         1 * normalizedSamplingSize.width, -1 * normalizedSamplingSize.height,
        -1 * normalizedSamplingSize.width,  1 * normalizedSamplingSize.height,
         1 * normalizedSamplingSize.width,  1 * normalizedSamplingSize.height
    };
    
    /*
     Update attribute values.
     */
    //Define an array of generic vertex attribute data
    glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, 0, 0, quadVertexData);
    //Enable or disable a generic vertex attribute array
    glEnableVertexAttribArray(ATTRIB_VERTEX);
    
    /*
     The texture vertices are set up such that we flip the texture vertically
     This is so that our top left origin buffers match OpenGL's bottom left texture coordinate system
     */
    CGRect textureSamplingRect = CGRectMake(0, 0, 1, 1);
    GLfloat quadTextureData[] = {
        CGRectGetMinX(textureSamplingRect), CGRectGetMaxY(textureSamplingRect),
        CGRectGetMaxX(textureSamplingRect), CGRectGetMaxY(textureSamplingRect),
        CGRectGetMinX(textureSamplingRect), CGRectGetMinY(textureSamplingRect),
        CGRectGetMaxX(textureSamplingRect), CGRectGetMinY(textureSamplingRect)
    };
    glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, 0, 0, quadTextureData);
    glEnableVertexAttribArray(ATTRIB_TEXCOORD);
    
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    
    glBindRenderbuffer(GL_RENDERBUFFER, _colorBufferHandle);
    [_context presentRenderbuffer:GL_RENDERBUFFER];
    
    [self cleanUpTextures];
    //Periodic texture cache flush every frame
    CVOpenGLESTextureCacheFlush(_videoTextureCache, 0);
    
    if(_videoTextureCache){
        CFRelease(_videoTextureCache);
    }
}

# pragma mark - OpenGL setup
- (void)setupGL
{
    if(!_context || ![EAGLContext setCurrentContext:_context])
        return;
    
    [self setupBuffers];
    [self loadShaders];
    
    glUseProgram(self.program);
    
    glUniform1i(uniforms[UNIFORM_Y], 0);
    glUniform1i(uniforms[UNIFORM_UV], 1);
    glUniform1f(uniforms[UNIFORM_ROTATION_ANGLE], 0);
    glUniformMatrix3fv(uniforms[UNIFORM_COLOR_CONVERSION_MATRIX],
                       1,
                       GL_FALSE,
                       _preferredConversion);
}

# pragma mark - Utilities
- (void)setupBuffers
{
    glDisable(GL_DEPTH_TEST);
    
    glEnableVertexAttribArray(ATTRIB_VERTEX);
    glVertexAttribPointer(ATTRIB_VERTEX,
                          2,
                          GL_FLOAT,
                          GL_FALSE,
                          2 * sizeof(GLfloat),
                          0);
    
    glEnableVertexAttribArray(ATTRIB_TEXCOORD);
    glVertexAttribPointer(ATTRIB_TEXCOORD,
                          2,
                          GL_FLOAT,
                          GL_FALSE,
                          2 * sizeof(GLfloat),
                          0);
    
    [self createBuffers];
}

- (void)createBuffers
{
    glGenBuffers(1, &_frameBufferHandle);
    glBindFramebuffer(GL_FRAMEBUFFER, _frameBufferHandle);
    
    glGenRenderbuffers(1, &_colorBufferHandle);
    glBindRenderbuffer(GL_RENDERBUFFER, _colorBufferHandle);
    
    [_context   renderbufferStorage:GL_RENDERBUFFER fromDrawable:self];
    //Set width & height buffer
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &_backingWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &_backingHeight);
    
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _colorBufferHandle);
    if(glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
    {
        NSLog(@"Failed to make complete framebuffer object %x", glCheckFramebufferStatus(GL_FRAMEBUFFER));
    }
}

- (void)releaseBuffers
{
    if(_frameBufferHandle)
    {
        glDeleteFramebuffers(1, &_frameBufferHandle);
        _frameBufferHandle = 0;
    }
    if(_colorBufferHandle)
    {
        glDeleteRenderbuffers(1, &_colorBufferHandle);
        _colorBufferHandle = 0;
    }
}

- (void)resetRenderBuffer
{
    if(!_context || [EAGLContext setCurrentContext:_context])
    {
        return;
    }
    
    [self releaseBuffers];
}

- (void)cleanUpTextures
{
    if(_lumaTexture)
    {
        CFRelease(_lumaTexture);
        _lumaTexture = NULL;
    }
    if(_chromaTexture)
    {
        CFRelease(_chromaTexture);
        _chromaTexture = NULL;
    }
}

- (BOOL)loadShaders
{
    GLuint vertShader = 0, fragShader = 0;
    NSURL *vertShaderURL, *fragShaderURL;
    
    //Create the shader program
    self.program = glCreateProgram();
    
    vertShaderURL = [[NSBundle mainBundle] URLForResource:@"vertexShader" withExtension:@"glsl"];
    if(![self compileShader:&vertShader type:GL_VERTEX_SHADER URL:vertShaderURL])
    {
        NSLog(@"Failed to compile vertex shader");
        return NO;
    }
    
    fragShaderURL = [[NSBundle mainBundle] URLForResource:@"fragmentShader" withExtension:@"glsl"];
    if(![self compileShader:&fragShader type:GL_FRAGMENT_SHADER URL:fragShaderURL])
    {
        NSLog(@"Failed to compile fragment shader");
        return NO;
    }
    
    glAttachShader(self.program, vertShader);
    glAttachShader(self.program, fragShader);
    
    //Bind attribute locations. This needs to be done prior to linking
    glBindAttribLocation(self.program, ATTRIB_VERTEX, "position");
    glBindAttribLocation(self.program, ATTRIB_TEXCOORD, "texCoord");
    
    //Link the program
    if(![self linkProgram:self.program])
    {
        NSLog(@"Failed to link program: %d", self.program);
        
        if(vertShader)
        {
            glDeleteShader(vertShader);
            vertShader = 0;
        }
        if(fragShader)
        {
            glDeleteShader(fragShader);
            fragShader = 0;
        }
        if(self.program)
        {
            glDeleteProgram(self.program);
            self.program = 0;
        }
        return NO;
    }
    
    //Get uniform locations.
    uniforms[UNIFORM_Y] = glGetUniformLocation(self.program, "SamplerY");
    uniforms[UNIFORM_UV] = glGetUniformLocation(self.program, "SamplerUV");
    uniforms[UNIFORM_ROTATION_ANGLE] = glGetUniformLocation(self.program, "preferredRotation");
    uniforms[UNIFORM_COLOR_CONVERSION_MATRIX] = glGetUniformLocation(self.program, "colorConversionMatrix");
    
    //Release vertex and fragment shaders
    if(vertShader)
    {
        glDetachShader(self.program, vertShader);
        glDeleteShader(vertShader);
    }
    if(fragShader)
    {
        glDetachShader(self.program, fragShader);
        glDeleteShader(fragShader);
    }
    
    return YES;
}

- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type URL:(NSURL *)URL
{
    NSError *error;
    NSString *sourceString = [[NSString alloc] initWithContentsOfURL:URL encoding:NSUTF8StringEncoding error:&error];
    if(sourceString == nil)
    {
        NSLog(@"Failed to load vertex shader : %@", [error localizedDescription]);
        return NO;
    }
    
    GLint status;
    const GLchar *source;
    source = (GLchar *)[sourceString UTF8String];
    
    *shader = glCreateShader(type);
    glShaderSource(*shader, 1, &source, NULL);
    glCompileShader(*shader);
    
#if defined(BUG)
    GLint logLength;
    glGetShaderiv(*shader, GL_INFO_LOG_LENGTH, &logLength);
    if(logLength > 0)
    {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetShaderinfoLog(*shader, logLength, &logLength, log);
        NSLog(@"Shader compile log:\n%s", log);
        free(log);
    }
#endif
    
    glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
    if(status == 0)
    {
        glDeleteShader(*shader);
        return NO;
    }
    return YES;
}

- (BOOL)linkProgram:(GLuint)prog
{
    GLint status;
    glLinkProgram(prog);
    
    GLint logLength;
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if(logLength > 0)
    {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program link log:\n%s", log);
        free(log);
    }
    glGetProgramiv(prog, GL_LINK_STATUS, &status);
    if(status == 0)
    {
        return NO;
    }
    return YES;
}

- (void)dealloc
{
    if(!_context || [EAGLContext setCurrentContext:_context])
    {
        return;
    }
    
    [self cleanUpTextures];
    
    if(_pixelBuffer)
    {
        CVPixelBufferRelease(_pixelBuffer);
    }
    
    if(self.program)
    {
        glDeleteProgram(self.program);
        self.program = 0;
    }
    if(_context)
    {
        _context = nil;
    }
}
@end
