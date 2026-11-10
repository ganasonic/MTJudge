#import "OverlayMetalView.h"
@interface OverlayMetalView ()
@property CIContext *imageContext;
@property id<MTLCommandQueue> commandQueue;
@property CIImage *pendingImage;
@property dispatch_semaphore_t frameSlots;
@property BOOL submittedFrame;
@property(atomic,readwrite,nullable) NSError *renderError;
@end
@implementation OverlayMetalView
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame device:MTLCreateSystemDefaultDevice()])) {
        self.framebufferOnly=NO; self.paused=YES; self.enableSetNeedsDisplay=NO; self.autoResizeDrawable=YES;
        self.colorPixelFormat=MTLPixelFormatBGRA8Unorm;
        self.imageContext=self.device?[CIContext contextWithMTLDevice:self.device options:@{kCIContextCacheIntermediates:@NO}]:nil;
        self.commandQueue=[self.device newCommandQueue]; self.backgroundColor=UIColor.blackColor;
        self.frameSlots=dispatch_semaphore_create(2);
        self.delegate=self;
        ((CAMetalLayer *)self.layer).allowsNextDrawableTimeout=YES;
    } return self;
}
- (CIImage *)warp:(CIImage *)image matrix:(simd_double3x3)matrix target:(CGSize)size {
    NSArray *points=@[[NSValue valueWithCGPoint:CGPointMake(0,0)],[NSValue valueWithCGPoint:CGPointMake(1,0)],[NSValue valueWithCGPoint:CGPointMake(1,1)],[NSValue valueWithCGPoint:CGPointMake(0,1)]];
    NSMutableArray *v=[NSMutableArray array];
    for(NSValue *p in points) { CGPoint q=MTJOverlayProject(matrix,p.CGPointValue); if(!isfinite(q.x)||!isfinite(q.y)||fabs(q.x)>20||fabs(q.y)>20) return nil; [v addObject:[CIVector vectorWithX:q.x*size.width Y:(1-q.y)*size.height]]; }
    return [image imageByApplyingFilter:@"CIPerspectiveTransform" withInputParameters:@{@"inputTopLeft":v[0],@"inputTopRight":v[1],@"inputBottomRight":v[2],@"inputBottomLeft":v[3]}];
}
- (BOOL)displayMain:(CIImage *)main sub:(CIImage *)sub matrix:(simd_double3x3)matrix mask:(CIImage *)mask opacity:(CGFloat)opacity mainAnnotation:(CIImage *)mainAnnotation subAnnotation:(CIImage *)subAnnotation {
    if(!main||!self.window||!self.device||self.drawableSize.width<1||self.drawableSize.height<1) return NO;
    CGRect extent=main.extent; CGSize size=extent.size;
    CIImage *result=main;
    if(sub && MTJOverlayMatrixIsValid(matrix)) {
        CIImage *warped=[self warp:sub matrix:matrix target:size];
        if(warped) {
            // An opaque source rectangle supplies a validity mask outside the warped image.
            CIImage *alpha=mask?:[[CIImage imageWithColor:CIColor.whiteColor] imageByCroppingToRect:sub.extent];
            alpha=[alpha imageByApplyingTransform:CGAffineTransformMakeScale(sub.extent.size.width/alpha.extent.size.width,sub.extent.size.height/alpha.extent.size.height)];
            alpha=[self warp:alpha matrix:matrix target:size];
            alpha=[alpha imageByApplyingFilter:@"CIColorMatrix" withInputParameters:@{@"inputRVector":[CIVector vectorWithX:opacity Y:0 Z:0 W:0],@"inputGVector":[CIVector vectorWithX:0 Y:opacity Z:0 W:0],@"inputBVector":[CIVector vectorWithX:0 Y:0 Z:opacity W:0]}];
            CIImage *black=[[CIImage imageWithColor:CIColor.blackColor] imageByCroppingToRect:extent];
            alpha=[alpha imageByCompositingOverImage:black];
            if(alpha) result=[warped imageByApplyingFilter:@"CIBlendWithMask" withInputParameters:@{kCIInputBackgroundImageKey:main,kCIInputMaskImageKey:alpha}];
        }
    }
    if(mainAnnotation) {
        mainAnnotation=[mainAnnotation imageByApplyingTransform:CGAffineTransformMakeScale(size.width/mainAnnotation.extent.size.width,size.height/mainAnnotation.extent.size.height)];
        result=[mainAnnotation imageByCompositingOverImage:result];
    }
    if(sub && subAnnotation) {
        subAnnotation=[subAnnotation imageByApplyingTransform:CGAffineTransformMakeScale(sub.extent.size.width/subAnnotation.extent.size.width,sub.extent.size.height/subAnnotation.extent.size.height)];
        CIImage *warped=[self warp:subAnnotation matrix:matrix target:size]; if(warped) result=[warped imageByCompositingOverImage:result];
    }
    result=[result imageByCroppingToRect:extent];
    CGSize output=self.drawableSize; CGFloat scale=MIN(output.width/size.width,output.height/size.height);
    CGFloat x=(output.width-size.width*scale)/2,y=(output.height-size.height*scale)/2;
    self.videoRect=CGRectMake(x/self.contentScaleFactor,y/self.contentScaleFactor,size.width*scale/self.contentScaleFactor,size.height*scale/self.contentScaleFactor);
    result=[result imageByApplyingTransform:CGAffineTransformMakeScale(scale,scale)]; result=[result imageByApplyingTransform:CGAffineTransformMakeTranslation(x,y)];
    CIImage *black=[[CIImage imageWithColor:CIColor.blackColor] imageByCroppingToRect:CGRectMake(0,0,output.width,output.height)]; result=[result imageByCompositingOverImage:black];
    self.pendingImage=result;
    self.submittedFrame=NO;
    // MTKView releases its currentDrawable at the end of draw(). Never acquire/present
    // drawables directly from the controller's display link outside this lifecycle.
    [self draw];
    return self.submittedFrame;
}
- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    // The controller recomputes aspect-fit geometry on its next display-link tick.
}
- (void)drawInMTKView:(MTKView *)view {
    CIImage *image=self.pendingImage;
    if(!image||!self.window) return;
    // Drop a frame instead of waiting for the GPU on the UI thread. Paused redraws
    // return NO to the controller so it can retry on the next display-link tick.
    dispatch_semaphore_t slots=self.frameSlots;
    if(dispatch_semaphore_wait(slots,DISPATCH_TIME_NOW)!=0) return;
    id<CAMetalDrawable> drawable=view.currentDrawable;
    id<MTLCommandBuffer> buffer=drawable?[self.commandQueue commandBuffer]:nil;
    if(!buffer) { dispatch_semaphore_signal(slots); return; }
    CIRenderDestination *destination=[[CIRenderDestination alloc] initWithWidth:drawable.texture.width height:drawable.texture.height pixelFormat:self.colorPixelFormat commandBuffer:buffer mtlTextureProvider:^id<MTLTexture> { return drawable.texture; }];
    destination.flipped=YES;
    NSError *error=nil;
    CIRenderTask *task=[self.imageContext startTaskToRender:image fromRect:CGRectMake(0,0,drawable.texture.width,drawable.texture.height) toDestination:destination atPoint:CGPointZero error:&error];
    if(!task) { self.renderError=error; dispatch_semaphore_signal(slots); return; }
    __weak typeof(self) weakSelf=self;
    [buffer addCompletedHandler:^(id<MTLCommandBuffer> completed) {
        // Retain both the CI graph (including video pixel buffers) and render task
        // until the corresponding command buffer is finished.
        (void)image.extent; (void)task;
        weakSelf.renderError=completed.error;
        dispatch_semaphore_signal(slots);
    }];
    [buffer presentDrawable:drawable]; [buffer commit];
    self.submittedFrame=YES;
}
@end
