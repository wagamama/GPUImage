#import "GPUImageCIFilterWrapper.h"
#import "GPUImageFilter.h"
#import <AVFoundation/AVFoundation.h>

@implementation GPUImageCIFilterWrapper
{
    CIContext *context;
    CIFilter *filter;
    CIImage *image;
    CIImage *result;
}

@synthesize preventRendering = _preventRendering;
@synthesize currentlyReceivingMonochromeInput;

#pragma mark -
#pragma mark Initialization

- (id)initWitCIFilterName:(NSString *)name keysAndValues:(id)key0, ... NS_REQUIRES_NIL_TERMINATION;
{
    if (!(self = [super init]))
    {
        return nil;
    }
    
    _preventRendering = NO;
    currentlyReceivingMonochromeInput = NO;
    inputRotation = kGPUImageNoRotation;
    imageCaptureSemaphore = dispatch_semaphore_create(0);
    dispatch_semaphore_signal(imageCaptureSemaphore);
    
    [GPUImageContext useImageProcessingContext];
    GPUImageContext *imageContext = [GPUImageContext sharedImageProcessingContext];
    NSDictionary *options = @{ (id)kCIContextWorkingColorSpace: (id)kCFNull };
    // TODO: no need to create CIContext for every filter
    context = [CIContext contextWithEAGLContext:imageContext.context options:options];
    filter = [CIFilter filterWithName:name];
    NSMutableArray *values = [[NSMutableArray alloc] init];
    va_list args;
    va_start(args, key0);
    for (id arg = key0; arg != nil; arg = va_arg(args, id))
    {
        [values addObject:arg];
    }
    va_end(args);
    for (int i = 0; i < values.count; i+=2)
    {
        [filter setValue:values[i+1] forKey:(NSString *)values[i]];
    }
    
    return self;
}

- (void)dealloc;
{
#if ( (__IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_6_0) || (!defined(__IPHONE_6_0)) )
    if (imageCaptureSemaphore != NULL)
    {
        dispatch_release(imageCaptureSemaphore);
    }
#endif
}

#pragma mark -
#pragma mark Managing the display FBOs

- (CGSize)sizeOfFBO;
{
    CGSize outputSize = [self maximumOutputSize];
    if ( (CGSizeEqualToSize(outputSize, CGSizeZero)) || (inputTextureSize.width < outputSize.width) )
    {
        return inputTextureSize;
    }
    else
    {
        return outputSize;
    }
}

#pragma mark -
#pragma mark Rendering

- (void)renderToTextureWithVertices:(const GLfloat *)vertices textureCoordinates:(const GLfloat *)textureCoordinates;
{
    if (self.preventRendering)
    {
        [firstInputFramebuffer unlock];
        return;
    }
    
    outputFramebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:[self sizeOfFBO] textureOptions:self.outputTextureOptions onlyTexture:NO];
    [outputFramebuffer activateFramebuffer];
    if (usingNextFrameForImageCapture)
    {
        [outputFramebuffer lock];
    }
    
    NSDictionary *options = @{ (id)kCIImageColorSpace: (id)kCFNull };
    image = [CIImage imageWithCVPixelBuffer:firstInputFramebuffer.renderTarget options:options];
    [filter setValue:(id)image forKey:kCIInputImageKey];
    result = filter.outputImage;
    [context render:result toCVPixelBuffer:outputFramebuffer.renderTarget];
    
    [firstInputFramebuffer unlock];
    
    if (usingNextFrameForImageCapture)
    {
        dispatch_semaphore_signal(imageCaptureSemaphore);
    }
}

- (void)informTargetsAboutNewFrameAtTime:(CMTime)frameTime;
{
    if (self.frameProcessingCompletionBlock != NULL)
    {
        self.frameProcessingCompletionBlock(self, frameTime);
    }
    
    // Get all targets the framebuffer so they can grab a lock on it
    for (id<GPUImageInput> currentTarget in targets)
    {
        if (currentTarget != self.targetToIgnoreForUpdates)
        {
            NSInteger indexOfObject = [targets indexOfObject:currentTarget];
            NSInteger textureIndex = [[targetTextureIndices objectAtIndex:indexOfObject] integerValue];
            
            [self setInputFramebufferForTarget:currentTarget atIndex:textureIndex];
            [currentTarget setInputSize:[self outputFrameSize] atIndex:textureIndex];
        }
    }
    
    // Release our hold so it can return to the cache immediately upon processing
    [[self framebufferForOutput] unlock];
    
    if (usingNextFrameForImageCapture)
    {
        //        usingNextFrameForImageCapture = NO;
    }
    else
    {
        [self removeOutputFramebuffer];
    }
    
    // Trigger processing last, so that our unlock comes first in serial execution, avoiding the need for a callback
    for (id<GPUImageInput> currentTarget in targets)
    {
        if (currentTarget != self.targetToIgnoreForUpdates)
        {
            NSInteger indexOfObject = [targets indexOfObject:currentTarget];
            NSInteger textureIndex = [[targetTextureIndices objectAtIndex:indexOfObject] integerValue];
            [currentTarget newFrameReadyAtTime:frameTime atIndex:textureIndex];
        }
    }
}

- (CGSize)outputFrameSize;
{
    return inputTextureSize;
}

#pragma mark -
#pragma mark GPUImageInput

- (void)newFrameReadyAtTime:(CMTime)frameTime atIndex:(NSInteger)textureIndex;
{
    static const GLfloat imageVertices[] = {
        -1.0f, -1.0f,
        1.0f, -1.0f,
        -1.0f,  1.0f,
        1.0f,  1.0f,
    };
    
    [self renderToTextureWithVertices:imageVertices textureCoordinates:[GPUImageFilter textureCoordinatesForRotation:inputRotation]];
    
    [self informTargetsAboutNewFrameAtTime:frameTime];
}

- (void)setInputFramebuffer:(GPUImageFramebuffer *)newInputFramebuffer atIndex:(NSInteger)textureIndex;
{
    firstInputFramebuffer = newInputFramebuffer;
    [firstInputFramebuffer lock];
}

- (NSInteger)nextAvailableTextureIndex;
{
    return 0;
}

- (CGSize)rotatedSize:(CGSize)sizeToRotate forIndex:(NSInteger)textureIndex;
{
    CGSize rotatedSize = sizeToRotate;
    
    if (GPUImageRotationSwapsWidthAndHeight(inputRotation))
    {
        rotatedSize.width = sizeToRotate.height;
        rotatedSize.height = sizeToRotate.width;
    }
    
    return rotatedSize;
}

- (void)setInputSize:(CGSize)newSize atIndex:(NSInteger)textureIndex;
{
    if (self.preventRendering)
    {
        return;
    }
    
    if (overrideInputSize)
    {
        if (CGSizeEqualToSize(forcedMaximumSize, CGSizeZero))
        {
            
        }
        else
        {
            CGRect insetRect = AVMakeRectWithAspectRatioInsideRect(newSize, CGRectMake(0.0, 0.0, forcedMaximumSize.width, forcedMaximumSize.height));
            inputTextureSize = insetRect.size;
        }
    }
    else
    {
        CGSize rotatedSize = [self rotatedSize:newSize forIndex:textureIndex];
        
        if (CGSizeEqualToSize(rotatedSize, CGSizeZero))
        {
            inputTextureSize = rotatedSize;
        }
        else if (!CGSizeEqualToSize(inputTextureSize, rotatedSize))
        {
            inputTextureSize = rotatedSize;
        }
    }
}

- (void)setInputRotation:(GPUImageRotationMode)newInputRotation atIndex:(NSInteger)textureIndex;
{
    inputRotation = newInputRotation;
}

- (CGSize)maximumOutputSize;
{
    return CGSizeZero;
}

- (void)endProcessing;
{
    if (!isEndProcessing)
    {
        isEndProcessing = YES;
        
        for (id<GPUImageInput> currentTarget in targets)
        {
            [currentTarget endProcessing];
        }
    }
}

- (BOOL)wantsMonochromeInput;
{
    return NO;
}

#pragma mark -
#pragma mark Accessors

@end
