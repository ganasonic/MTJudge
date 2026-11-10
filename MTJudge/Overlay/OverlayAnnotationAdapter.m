#import "OverlayAnnotationAdapter.h"
#import "../SkeletonConnections.h"

// Axis names are stored as 軸1 / 軸2 for compatibility with existing annotations.
// Screen angles retain the existing color sectors; 12 o'clock is -90 degrees.
static NSArray<UIColor *> *MTJOverlayAxisColors(void) { return @[UIColor.yellowColor, UIColor.systemRedColor, UIColor.systemGreenColor]; }
static NSInteger MTJOverlayAxisColorIndex(CGFloat degrees, NSString *tool) {
    while (degrees < -180) degrees += 360; while (degrees >= 180) degrees -= 360;
    CGFloat vertical = fabs(fabs(degrees)-90), horizontal = MIN(fabs(degrees),180-fabs(degrees));
    if ([tool isEqualToString:@"軸1"]) { if (vertical <= 15) return 2; if (horizontal <= 45) return 1; }
    else if ([tool isEqualToString:@"軸2"]) { if (vertical <= 30) return 2; if (horizontal <= 30) return 1; }
    else { if (vertical <= 15) return 1; if (horizontal <= 30) return 2; }
    return 0;
}
static void MTJOverlayAddClockArc(CGMutablePathRef path, CGPoint center, CGFloat radius, CGFloat start, CGFloat end) {
    CGFloat a = start*M_PI/180, b = end*M_PI/180;
    CGPathMoveToPoint(path,NULL,center.x+radius*cos(a),center.y+radius*sin(a));
    CGPathAddArc(path,NULL,center.x,center.y,radius,a,b,false);
}
static CGPathRef MTJOverlayAxisClockPath(CGPoint center, CGFloat radius, NSString *tool, NSInteger color) {
    CGMutablePathRef path = CGPathCreateMutable();
    if (!isfinite(radius) || radius <= 0) return path;
    NSInteger run = -180;
    for (NSInteger degree=-179; degree<=180; degree++) {
        if (degree == 180 || MTJOverlayAxisColorIndex(degree+.5,tool) != MTJOverlayAxisColorIndex(run+.5,tool)) {
            if (MTJOverlayAxisColorIndex(run+.5,tool) == color) MTJOverlayAddClockArc(path,center,radius,run,degree);
            run = degree;
        }
    }
    for (NSInteger tick=0; tick<12; tick++) {
        CGFloat degrees = -90 + tick*30;
        if (MTJOverlayAxisColorIndex(degrees,tool) != color) continue;
        CGFloat angle = degrees*M_PI/180, inside = radius*(tick%3 == 0 ? .84 : .915);
        CGPathMoveToPoint(path,NULL,center.x+radius*cos(angle),center.y+radius*sin(angle));
        CGPathAddLineToPoint(path,NULL,center.x+inside*cos(angle),center.y+inside*sin(angle));
    }
    return path;
}
static CGPathRef MTJOverlayAxisBoundaryPath(CGPoint center, CGFloat radius, NSString *tool, NSInteger color) {
    CGMutablePathRef path = CGPathCreateMutable();
    if (!isfinite(radius) || radius <= 0) return path;
    for (NSInteger degree=-180; degree<180; degree++) {
        NSInteger before = MTJOverlayAxisColorIndex(degree-.5,tool), after = MTJOverlayAxisColorIndex(degree+.5,tool);
        if (before == after || (before != 0 ? before : after) != color) continue;
        CGFloat angle = degree*M_PI/180;
        CGPathMoveToPoint(path,NULL,center.x,center.y);
        CGPathAddLineToPoint(path,NULL,center.x+radius*cos(angle),center.y+radius*sin(angle));
    }
    return path;
}
static void MTJOverlayDrawAxisSectors(CGContextRef ctx, CGPoint center, CGFloat radius, NSString *tool) {
    CGContextSaveGState(ctx); CGContextSetLineDash(ctx,0,NULL,0); CGContextSetLineCap(ctx,kCGLineCapRound);
    NSArray<UIColor *> *colors = MTJOverlayAxisColors();
    CGFloat dash[] = {4,4};
    CGContextSetLineDash(ctx,0,dash,2);
    for (NSInteger color=1; color<colors.count; color++) {
        CGPathRef boundaries = MTJOverlayAxisBoundaryPath(center,radius,tool,color);
        CGContextSetStrokeColorWithColor(ctx,colors[color].CGColor);
        CGContextAddPath(ctx,boundaries); CGContextStrokePath(ctx); CGPathRelease(boundaries);
    }
    CGContextSetLineDash(ctx,0,NULL,0);
    for (NSInteger color=0; color<colors.count; color++) {
        CGPathRef path = MTJOverlayAxisClockPath(center,radius,tool,color);
        CGContextSetStrokeColorWithColor(ctx,colors[color].CGColor); CGContextAddPath(ctx,path); CGContextStrokePath(ctx); CGPathRelease(path);
    }
    CGContextRestoreGState(ctx);
}

@interface OverlayAnnotationPainter : NSObject
@property CGRect bounds;
- (void)drawAnnotation:(NSDictionary *)item inContext:(CGContextRef)context;
@end
@implementation OverlayAnnotationPainter
- (CGPoint)pointFromValue:(NSArray *)value { return CGPointMake([value[0] doubleValue] * self.bounds.size.width, [value[1] doubleValue] * self.bounds.size.height); }
- (void)drawReversedText:(NSString *)text atPoint:(CGPoint)point color:(UIColor *)background inContext:(CGContextRef)ctx {
    if (!text.length) return;
    NSDictionary *measureAttributes = @{NSFontAttributeName:[UIFont boldSystemFontOfSize:18]};
    CGSize size = [text sizeWithAttributes:measureAttributes];
    CGRect box = CGRectInset(CGRectMake(point.x, point.y, size.width + 12, size.height + 6), -0.5, -0.5);
    CGContextSaveGState(ctx);
    CGContextSetFillColorWithColor(ctx, [background colorWithAlphaComponent:.92].CGColor);
    CGContextAddPath(ctx, [UIBezierPath bezierPathWithRoundedRect:box cornerRadius:6].CGPath);
    CGContextFillPath(ctx);
    CGFloat red = 0, green = 0, blue = 0, alpha = 1; [background getRed:&red green:&green blue:&blue alpha:&alpha];
    BOOL useBlackText = ((red > .75 && green > .75 && blue < .35) || (green > .65 && red < .35 && blue < .35) || (red > .82 && green > .82 && blue > .82));
    UIColor *textColor = useBlackText ? UIColor.blackColor : UIColor.whiteColor;
    [text drawAtPoint:CGPointMake(box.origin.x + 6, box.origin.y + 3) withAttributes:@{NSFontAttributeName:[UIFont boldSystemFontOfSize:18], NSForegroundColorAttributeName:textColor}];
    CGContextRestoreGState(ctx);
}
- (void)drawAnnotation:(NSDictionary *)item inContext:(CGContextRef)ctx { NSArray *values = item[@"points"]; if (values.count < 1) return; NSMutableArray<NSValue *> *points = [NSMutableArray array]; for (NSArray *v in values) [points addObject:[NSValue valueWithCGPoint:[self pointFromValue:v]]]; UIColor *color = [UIColor colorWithRed:[item[@"r"] doubleValue] green:[item[@"g"] doubleValue] blue:[item[@"b"] doubleValue] alpha:[item[@"a"] doubleValue]]; CGContextSetStrokeColorWithColor(ctx, color.CGColor); CGContextSetFillColorWithColor(ctx, [UIColor colorWithRed:[item[@"br"] doubleValue] green:[item[@"bg"] doubleValue] blue:[item[@"bb"] doubleValue] alpha:[item[@"ba"] doubleValue]].CGColor); CGContextSetLineWidth(ctx, [item[@"width"] doubleValue] > 0 ? [item[@"width"] doubleValue] : 3.0); if ([item[@"style"] isEqualToString:@"点線"]) { CGFloat pattern[] = {4, 4}; CGContextSetLineDash(ctx, 0, pattern, 2); } else if ([item[@"style"] isEqualToString:@"鎖線"]) { CGFloat pattern[] = {12, 8}; CGContextSetLineDash(ctx, 0, pattern, 2); } else { CGContextSetLineDash(ctx, 0, NULL, 0); }
    NSString *tool = item[@"tool"] ?: @"直線"; CGPoint first = points.firstObject.CGPointValue; CGPoint last = points.lastObject.CGPointValue;
    if ([tool isEqualToString:@"軸1"] || [tool isEqualToString:@"軸2"] || [tool isEqualToString:@"軸3D"]) {
        MTJOverlayDrawAxisSectors(ctx, first, hypot(last.x-first.x, last.y-first.y), tool);
    }
    else if ([tool isEqualToString:@"丸"]) {
        CGFloat radius = hypot(last.x-first.x, last.y-first.y);
        UIColor *fill = [color colorWithAlphaComponent:0.20];
        CGContextSetFillColorWithColor(ctx, fill.CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(first.x-radius, first.y-radius, radius*2, radius*2));
    }
    else if ([tool isEqualToString:@"楕円"] || [tool isEqualToString:@"四角"] || [tool isEqualToString:@"三角"]) {
        CGRect rect = CGRectStandardize(CGRectMake(first.x, first.y, last.x-first.x, last.y-first.y)); CGFloat angle = [item[@"rotation"] doubleValue]; CGPoint center = CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
        UIColor *fill = [color colorWithAlphaComponent:0.20];
        CGContextSaveGState(ctx); CGContextTranslateCTM(ctx, center.x, center.y); CGContextRotateCTM(ctx, angle); CGContextTranslateCTM(ctx, -center.x, -center.y); CGContextSetFillColorWithColor(ctx, fill.CGColor);
        if ([tool isEqualToString:@"楕円"]) CGContextFillEllipseInRect(ctx, rect);
        else if ([tool isEqualToString:@"三角"]) { CGContextBeginPath(ctx); CGContextMoveToPoint(ctx, CGRectGetMidX(rect), CGRectGetMinY(rect)); CGContextAddLineToPoint(ctx, CGRectGetMaxX(rect), CGRectGetMaxY(rect)); CGContextAddLineToPoint(ctx, CGRectGetMinX(rect), CGRectGetMaxY(rect)); CGContextClosePath(ctx); CGContextFillPath(ctx); }
        else CGContextFillRect(ctx, rect);
        CGContextRestoreGState(ctx);
    }
    else if ([tool isEqualToString:@"x"]) { CGFloat arm = MAX(4.0, hypot(last.x-first.x, last.y-first.y)), rotation = [item[@"rotation"] doubleValue]; CGContextSaveGState(ctx); CGContextTranslateCTM(ctx, first.x, first.y); CGContextRotateCTM(ctx, rotation); CGContextMoveToPoint(ctx, -arm, 0); CGContextAddLineToPoint(ctx, arm, 0); CGContextMoveToPoint(ctx, 0, -arm); CGContextAddLineToPoint(ctx, 0, arm); CGContextStrokePath(ctx); CGContextRestoreGState(ctx); }
    else if ([tool isEqualToString:@"角度"] && points.count >= 3) {
        CGPoint p0 = points[0].CGPointValue, p1 = points[1].CGPointValue, p2 = points[2].CGPointValue;
        CGContextMoveToPoint(ctx, p0.x, p0.y); CGContextAddLineToPoint(ctx, p1.x, p1.y); CGContextAddLineToPoint(ctx, p2.x, p2.y); CGContextStrokePath(ctx);
        CGVector v0 = CGVectorMake(p0.x-p1.x, p0.y-p1.y), v1 = CGVectorMake(p2.x-p1.x, p2.y-p1.y);
        CGFloat denominator = hypot(v0.dx, v0.dy) * hypot(v1.dx, v1.dy);
        CGFloat angle = denominator > 0 ? acos(MAX(-1, MIN(1, (v0.dx*v1.dx + v0.dy*v1.dy) / denominator))) * 180.0 / M_PI : 0;
        NSString *value = [NSString stringWithFormat:@"%.1f°", angle];
        [self drawReversedText:value atPoint:CGPointMake(p1.x + 8, p1.y - 24) color:color inContext:ctx];
    }
    else if ([tool isEqualToString:@"フリー"]) {
        CGContextMoveToPoint(ctx, first.x, first.y);
        for (NSValue *v in points) CGContextAddLineToPoint(ctx, v.CGPointValue.x, v.CGPointValue.y);
        CGContextStrokePath(ctx);
    }
    else if ([tool isEqualToString:@"直線"] && [item[@"category"] isEqualToString:@"基準"]) {
        CGContextMoveToPoint(ctx, first.x, first.y); CGContextAddLineToPoint(ctx, last.x, last.y); CGContextStrokePath(ctx);
        CGFloat dx=fabs(last.x-first.x), dy=fabs(last.y-first.y);
        CGFloat diagonalAngle=atan2(dy, dx)*180.0/M_PI;
        // 矩形の底辺方向（水平線）と対角線が作る内角を常に表示する。
        CGFloat displayAngle=MAX(0.0, MIN(180.0, diagonalAngle));
        NSString *value=[NSString stringWithFormat:@"%.1f°", displayAngle];
        [self drawReversedText:value atPoint:CGPointMake(last.x+8, last.y-24) color:color inContext:ctx];
    }
    else if ([tool isEqualToString:@"直線"] && [item[@"category"] isEqualToString:@"対象"]) {
        CGContextMoveToPoint(ctx, first.x, first.y); CGContextAddLineToPoint(ctx, last.x, last.y); CGContextStrokePath(ctx);
        if (item[@"angle"]) {
            NSString *value = [NSString stringWithFormat:@"%.1f°", [item[@"angle"] doubleValue]];
            [self drawReversedText:value atPoint:CGPointMake((first.x+last.x)/2.0+6, (first.y+last.y)/2.0-22) color:color inContext:ctx];
        }
    }
    else if ([tool isEqualToString:@"文字"]) {
        NSString *text = item[@"text"] ?: @"";
        if ([text isEqualToString:@"👍"] || [text isEqualToString:@"👎"]) { if ([item[@"textReversed"] boolValue]) [self drawReversedText:text atPoint:first color:color inContext:ctx]; else [text drawAtPoint:first withAttributes:@{NSFontAttributeName:[UIFont boldSystemFontOfSize:28], NSForegroundColorAttributeName:color}]; return; }
        UIFont *font = [UIFont boldSystemFontOfSize:22];
        CGSize textSize = [text sizeWithAttributes:@{NSFontAttributeName:font}];
        CGFloat dx = last.x - first.x, dy = last.y - first.y;
        CGPoint origin = CGPointMake(dx >= 0 ? last.x : last.x - textSize.width, dy >= 0 ? last.y : last.y - textSize.height);
        CGPoint connect = CGPointMake(dx >= 0 ? origin.x : origin.x + textSize.width, dy >= 0 ? origin.y : origin.y + textSize.height);
        CGContextMoveToPoint(ctx, first.x, first.y); CGContextAddLineToPoint(ctx, connect.x, connect.y); CGContextStrokePath(ctx);
        CGFloat arrowAngle = atan2(connect.y-first.y, connect.x-first.x), arrowSize = 12;
        CGContextMoveToPoint(ctx, first.x, first.y); CGContextAddLineToPoint(ctx, first.x + arrowSize*cos(arrowAngle-M_PI/6), first.y + arrowSize*sin(arrowAngle-M_PI/6));
        CGContextMoveToPoint(ctx, first.x, first.y); CGContextAddLineToPoint(ctx, first.x + arrowSize*cos(arrowAngle+M_PI/6), first.y + arrowSize*sin(arrowAngle+M_PI/6)); CGContextStrokePath(ctx);
        if ([item[@"textReversed"] boolValue]) [self drawReversedText:text atPoint:origin color:color inContext:ctx];
        else [text drawAtPoint:origin withAttributes:@{NSFontAttributeName:font, NSForegroundColorAttributeName:color}];
    } else { CGContextMoveToPoint(ctx, first.x, first.y); for (NSValue *v in points) CGContextAddLineToPoint(ctx, v.CGPointValue.x, v.CGPointValue.y); CGContextStrokePath(ctx); if ([tool isEqualToString:@"矢印"] && points.count > 1) { CGFloat angle = atan2(last.y-first.y, last.x-first.x), size = 12; CGContextMoveToPoint(ctx, first.x, first.y); CGContextAddLineToPoint(ctx, first.x+size*cos(angle-M_PI/6), first.y+size*sin(angle-M_PI/6)); CGContextMoveToPoint(ctx, first.x, first.y); CGContextAddLineToPoint(ctx, first.x+size*cos(angle+M_PI/6), first.y+size*sin(angle+M_PI/6)); CGContextStrokePath(ctx); } }
}
@end

@interface OverlayAnnotationAdapter ()
@property NSArray *annotations;
@property NSArray *poses;
@property OverlayAnnotationPainter *painter;
@property NSString *cacheKey;
@property CIImage *cachedImage;
@end
@implementation OverlayAnnotationAdapter
- (instancetype)initWithVideoURL:(NSURL *)url {
    if((self=[super init])) {
        _painter=[OverlayAnnotationPainter new];
        NSData *d=[NSData dataWithContentsOfURL:[url URLByAppendingPathExtension:@"drawing.json"]];
        id a=d?[NSJSONSerialization JSONObjectWithData:d options:0 error:nil]:nil;
        _annotations=[a isKindOfClass:NSArray.class]?a:@[];
        d=[NSData dataWithContentsOfURL:[url URLByAppendingPathExtension:@"pose.json"]];
        a=d?[NSJSONSerialization JSONObjectWithData:d options:0 error:nil]:nil;
        _poses=[a isKindOfClass:NSArray.class]?a:@[];
    } return self;
}
- (CIImage *)imageAtTime:(double)time size:(CGSize)size joints:(NSDictionary *)joints skeleton:(BOOL)skeleton drawings:(BOOL)drawings color:(UIColor *)color {
    if(!skeleton&&!drawings) return nil;
    NSMutableArray *visible=[NSMutableArray array];
    if(drawings) for(id item in self.annotations) if([item isKindOfClass:NSDictionary.class] && [item[@"points"] isKindOfClass:NSArray.class]) {
        BOOL valid=YES; for(id p in item[@"points"]) if(![p isKindOfClass:NSArray.class]||[p count]<2||![p[0] isKindOfClass:NSNumber.class]||![p[1] isKindOfClass:NSNumber.class]) { valid=NO; break; }
        double start=[item[@"start"] doubleValue],end=[item[@"end"] isKindOfClass:NSNumber.class]?[item[@"end"] doubleValue]:DBL_MAX;
        if(valid&&time+.03>=start&&time<=end+.03) [visible addObject:item];
    }
    // Prefer the existing pose cache when its original timestamp matches this frame.
    NSDictionary *body=skeleton?joints:@{}; double distance=.075;
    if(skeleton) for(id frame in self.poses) if([frame isKindOfClass:NSDictionary.class]) {
        double d=fabs([frame[@"timestamp"] doubleValue]-time);
        if(d<distance&&[frame[@"joints"] isKindOfClass:NSDictionary.class]) {
            distance=d; NSMutableDictionary *converted=[NSMutableDictionary dictionary];
            for(NSString *name in frame[@"joints"]) {
                NSDictionary *p=frame[@"joints"][name];
                if([p isKindOfClass:NSDictionary.class]) converted[name]=@{@"x":p[@"x"]?:@0,@"y":@(1-[p[@"y"] doubleValue]),@"confidence":p[@"confidence"]?:@0};
            } body=converted;
        }
    }
    NSString *key=[NSString stringWithFormat:@"%@/%@/%@/%@",visible,body,NSStringFromCGSize(size),color];
    if([key isEqual:self.cacheKey]) return self.cachedImage;
    self.cacheKey=key;
    if(!visible.count&&!body.count) { self.cachedImage=nil; return nil; }
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat]; format.scale=1; format.opaque=NO;
    UIImage *image=[[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        self.painter.bounds=(CGRect){CGPointZero,size};
        for(NSDictionary *item in visible) { CGContextSaveGState(context.CGContext); [self.painter drawAnnotation:item inContext:context.CGContext]; CGContextRestoreGState(context.CGContext); }
        CGContextRef ctx=context.CGContext; CGContextSetStrokeColorWithColor(ctx,color.CGColor); CGContextSetLineWidth(ctx,2);
        for(NSArray *connection in SkeletonConnections()) {
            NSDictionary *a=body[connection[0]],*b=body[connection[1]];
            if([a[@"confidence"] doubleValue]<.15||[b[@"confidence"] doubleValue]<.15) continue;
            CGContextMoveToPoint(ctx,[a[@"x"] doubleValue]*size.width,[a[@"y"] doubleValue]*size.height);
            CGContextAddLineToPoint(ctx,[b[@"x"] doubleValue]*size.width,[b[@"y"] doubleValue]*size.height); CGContextStrokePath(ctx);
        }
    }];
    self.cachedImage=[CIImage imageWithCGImage:image.CGImage]; return self.cachedImage;
}
@end
