#import "GPUImageOutput.h"

/** GPUImage's CIFilter wrapper class
 
 Wrap CIFilter as GPUImageFilter
 */
@interface GPUImageCIFilterWrapper : GPUImageOutput <GPUImageInput>
{
    GPUImageFramebuffer *firstInputFramebuffer;
    
    BOOL isEndProcessing;
    
    CGSize currentFilterSize;
    GPUImageRotationMode inputRotation;
    
    BOOL currentlyReceivingMonochromeInput;
    
    dispatch_semaphore_t imageCaptureSemaphore;
}

@property(readonly) CVPixelBufferRef renderTarget;
@property(readwrite, nonatomic) BOOL preventRendering;
@property(readwrite, nonatomic) BOOL currentlyReceivingMonochromeInput;

/// @name Initialization

/**
 Initialize with CIFilter name and input values
 
 @param name CIFilter name
 @param key0, Input values
 */
- (id)initWitCIFilterName:(NSString *)name keysAndValues:key0, ... NS_REQUIRES_NIL_TERMINATION;

/// @name Managing the display FBOs

/** Size of the frame buffer object
 */
- (CGSize)sizeOfFBO;

/// @name Rendering

- (void)renderToTextureWithVertices:(const GLfloat *)vertices textureCoordinates:(const GLfloat *)textureCoordinates;
- (void)informTargetsAboutNewFrameAtTime:(CMTime)frameTime;
- (CGSize)outputFrameSize;

@end
