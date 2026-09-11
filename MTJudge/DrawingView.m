
#import "DrawingView.h"
#import "ReductionViewControler.h"


@implementation DrawingView

- (id)initWithCoder:(NSCoder *)coder {
	NSLog(@"ログ（%-20s,%-24s:%5d）in\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
    if (self = [super initWithCoder:coder]) {
        int width = self.bounds.size.width;
        int height = self.bounds.size.height;
        course_len_px = height;//コースの画像高さ
        data = malloc(width * height * 4);
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        context = CGBitmapContextCreate(data, width, height, 8, 4 * width, 
                                        colorSpace, kCGImageAlphaPremultipliedFirst);
        CGColorSpaceRelease(colorSpace);
        
        [self clear];
		
    }
	NSLog(@"ログ（%-20s,%-24s:%5dout\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
    return self;
}

- (void)setDelegate:(id)deletage {
	_delegate = deletage;
}

- (void)drawRect:(CGRect)rect {
	//NSLog(@"ログ（%-20s,%-24s:%5d）in\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
    // Drawing code
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRef currentContext = UIGraphicsGetCurrentContext();
    CGContextDrawImage(currentContext, rect, image);
    CGImageRelease(image);
	//NSLog(@"ログ（%-20s,%-24s:%5dout\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
}

- (void)clear{
	//NSLog(@"ログ（%-20s,%-24s:%5d）in\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
    CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, 1.0);
    CGContextFillRect(context, self.bounds);

	//コントロールゲート描画
	CGContextSetRGBStrokeColor(context, 0.0, 0.0, 1.0, 0.5);
	for (int i = 0; i<course_len_px; i++) {
		CGContextMoveToPoint(context, 0.0, (course_len_px/10)*i);
		CGContextAddLineToPoint(context, self.bounds.size.width, (course_len_px/10)*i);
	}
	CGContextStrokePath(context);
    [self setNeedsDisplay];
	//NSLog(@"ログ（%-20s,%-24s:%5dout\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
}

- (void)toggleColor:(BOOL)isBlack{
	//NSLog(@"ログ（%-20s,%-24s:%5d）in\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
    if(isBlack){
        CGContextSetRGBStrokeColor(context, 0.0, 0.0, 0.0, 1.0);
    }else{
        CGContextSetRGBStrokeColor(context, 1.0, 1.0, 1.0, 1.0);
    }
	//NSLog(@"ログ（%-20s,%-24s:%5dout\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
}

- (void)setLineWidth:(CGFloat)width{
	//NSLog(@"ログ（%-20s,%-24s:%5d）in\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
    CGContextSetLineWidth(context, width);
	//NSLog(@"ログ（%-20s,%-24s:%5dout\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
}

- (UIImage *)UIImage{
    CGImageRef cgimage = CGBitmapContextCreateImage(context);
    UIImage *image = [UIImage imageWithCGImage:cgimage];
    CGImageRelease(cgimage);
    return image;
}

-(void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
	[_delegate setSideDirection:0];
	[_delegate setFallDirection:0];
    startPoint = [[touches anyObject] locationInView:self];
	[_delegate createLabel:startPoint];
}

-(void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
#if false
    endPoint = [[touches anyObject] locationInView:self];
	int dX = fabs(endPoint.x-startPoint.x);
	int dY = fabs(endPoint.y-startPoint.y);

	[_delegate setSideDirection:dX];
	[_delegate setFallDirection:dY];
	[_delegate createLabel:endPoint];
#else
    endPoint = [[touches anyObject] locationInView:self];
	int dX = fabs(endPoint.x-startPoint.x);
	int dY = fabs(endPoint.y-startPoint.y);
    
	[_delegate setSideDirection:dX];
	[_delegate setFallDirection:dY];
	[_delegate recalculate:endPoint];
#endif
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)evnet {
//	NSLog(@"ログ（%-20s,%-24s:%5d）in\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
    CGPoint p = [[touches anyObject] locationInView:self];
    CGPoint q = [[touches anyObject] previousLocationInView:self];
    
    CGContextSetLineCap(context, kCGLineCapRound);
    CGContextBeginPath(context);
    CGContextMoveToPoint(context, q.x, q.y);
    CGContextAddLineToPoint(context, p.x, p.y);
    CGContextStrokePath(context);
    [self setNeedsDisplay];

    endPoint = [[touches anyObject] locationInView:self];
	int dX = fabs(endPoint.x-startPoint.x);
	int dY = fabs(endPoint.y-startPoint.y);
    
	[_delegate setSideDirection:dX];
	[_delegate setFallDirection:dY];
    [_delegate showLabelReduction];
//	NSLog(@"ログ（%-20s,%-24s:%5dout\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
}


- (void)dealloc {
	free(data);
	CGContextRelease(context);
//    [super dealloc];
}


@end
