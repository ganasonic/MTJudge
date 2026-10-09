#import "WaterJumpReceivedPlayerViewController.h"
#import "WaterJumpComparisonViewController.h"
#import "WaterJumpSettingsViewController.h"
#import "MTJudge-Swift.h"
#import <Vision/Vision.h>
#import "../SkeletonConnections.h"
#import "../Analysis/VideoPoseAnalysisManager.h"
#import "../Analysis/TakeoffAnalysisConfig.h"
#import "../Analysis/TakeoffAngleAnalyzer.h"
#import "../StrobeFeature.h"

@interface WJDrawingOptionsViewController : UITableViewController
@property (nonatomic, copy) NSArray<NSDictionary *> *options;
@property (nonatomic, copy) NSString *selectedValue;
@property (nonatomic, copy) void (^selectionHandler)(NSString *value);
@property (nonatomic, copy) void (^cancelHandler)(void);
@end

@implementation WJDrawingOptionsViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 68, 0, 0);
    self.tableView.rowHeight = 56;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel:)];
    if (@available(iOS 15.0, *)) self.sheetPresentationController.prefersGrabberVisible = YES;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.options.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"WJDrawingOptionCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"WJDrawingOptionCell"];
    NSDictionary *option = self.options[indexPath.row];
    cell.textLabel.text = option[@"display"] ?: option[@"value"];
    cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
    cell.imageView.image = option[@"image"];
    cell.imageView.tintColor = UIColor.labelColor;
    cell.accessoryType = [option[@"value"] isEqualToString:self.selectedValue] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *option = self.options[indexPath.row];
    NSString *value = option[@"value"];
    if (self.selectionHandler) self.selectionHandler(value);
    [self dismissViewControllerAnimated:YES completion:nil];
}
- (void)cancel:(id)sender { if (self.cancelHandler) self.cancelHandler(); [self dismissViewControllerAnimated:YES completion:nil]; }
@end

static CGSize WJDrawingOrientedTrackSize(AVAssetTrack *track) {
    CGRect rect = CGRectApplyAffineTransform(CGRectMake(0, 0, fabs(track.naturalSize.width), fabs(track.naturalSize.height)), track.preferredTransform);
    return CGSizeMake(fabs(rect.size.width), fabs(rect.size.height));
}
static CGAffineTransform WJDrawingNormalizedTrackTransform(AVAssetTrack *track) {
    CGRect rect = CGRectApplyAffineTransform(CGRectMake(0, 0, fabs(track.naturalSize.width), fabs(track.naturalSize.height)), track.preferredTransform);
    CGAffineTransform t = track.preferredTransform; t.tx -= rect.origin.x; t.ty -= rect.origin.y; return t;
}

// 軸描画の時計方向セクター。角度は画面座標系（12時方向が -90度）で扱う。
static void WJDrawAxisSectors(CGContextRef ctx, CGPoint center, CGFloat radius, NSString *tool) {
    UIColor *yellow = [UIColor.yellowColor colorWithAlphaComponent:.20];
    UIColor *green = [UIColor.systemGreenColor colorWithAlphaComponent:.20];
    UIColor *red = [UIColor.systemRedColor colorWithAlphaComponent:.20];
    CGContextSetFillColorWithColor(ctx, yellow.CGColor);
    CGContextMoveToPoint(ctx, center.x, center.y);
    CGContextAddArc(ctx, center.x, center.y, radius, 0, (CGFloat)(M_PI * 2), false);
    CGContextClosePath(ctx); CGContextFillPath(ctx);
    NSArray *sectors = nil;
    if ([tool isEqualToString:@"軸1"]) sectors = @[@[@(-105), @(-75), green], @[@(75), @(105), green], @[@(-45), @(45), red], @[@(135), @(225), red]];
    else if ([tool isEqualToString:@"軸2"]) sectors = @[@[@(-120), @(-60), green], @[@(60), @(120), green], @[@(-30), @(30), red], @[@(150), @(210), red]];
    else sectors = @[@[@(-105), @(-75), red], @[@(75), @(105), red], @[@(-30), @(30), green], @[@(150), @(210), green]];
    for (NSArray *sector in sectors) {
        CGFloat start = [sector[0] doubleValue] * M_PI / 180.0, end = [sector[1] doubleValue] * M_PI / 180.0;
        CGContextSetFillColorWithColor(ctx, [sector[2] CGColor]); CGContextMoveToPoint(ctx, center.x, center.y);
        CGContextAddArc(ctx, center.x, center.y, radius, start, end, false); CGContextClosePath(ctx); CGContextFillPath(ctx);
    }
}
static CGPathRef WJAxisSectorPath(CGPoint center, CGFloat radius, CGFloat start, CGFloat end) {
    CGMutablePathRef path = CGPathCreateMutable(); CGPathMoveToPoint(path, NULL, center.x, center.y);
    CGPathAddArc(path, NULL, center.x, center.y, radius, start, end, false); CGPathCloseSubpath(path); return path;
}

static NSArray<NSURL *> *WJPlayerVideoAndRelatedJSONFiles(NSURL *videoURL) {
    if (!videoURL) return @[];
    NSMutableArray<NSURL *> *targets = [NSMutableArray arrayWithObject:videoURL];
    NSURL *directory = [videoURL URLByDeletingLastPathComponent];
    NSString *prefix = [videoURL.lastPathComponent stringByAppendingString:@"."];
    NSArray<NSURL *> *entries = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:directory includingPropertiesForKeys:nil options:0 error:nil];
    for (NSURL *entry in entries) if ([entry.lastPathComponent hasPrefix:prefix] && [entry.lastPathComponent.lowercaseString hasSuffix:@".json"]) [targets addObject:entry];
    return targets;
}

@interface WJDrawingCanvas : UIView
@property (nonatomic, copy) NSArray<NSDictionary *> *annotations;
@property (nonatomic, assign) CMTime currentTime;
@property (nonatomic, assign) BOOL drawingEnabled;
@property (nonatomic, copy) NSString *tool;
@property (nonatomic, copy) NSString *drawingText;
@property (nonatomic, strong) UIColor *foregroundColor;
@property (nonatomic, strong) UIColor *backgroundColorForDrawing;
@property (nonatomic, copy) void (^commitBlock)(NSArray<NSValue *> *points);
@property (nonatomic, copy) void (^tapBlock)(CGPoint point);
@end

@implementation WJDrawingCanvas {
    NSMutableArray<NSValue *> *_activePoints;
}
- (instancetype)initWithFrame:(CGRect)frame { if ((self = [super initWithFrame:frame])) { self.backgroundColor = UIColor.clearColor; self.userInteractionEnabled = NO; self.foregroundColor = UIColor.yellowColor; self.tool = @"直線"; _activePoints = [NSMutableArray array]; } return self; }
- (void)setAnnotations:(NSArray<NSDictionary *> *)annotations { _annotations = [annotations copy]; [self setNeedsDisplay]; }
- (void)setCurrentTime:(CMTime)currentTime { _currentTime = currentTime; [self setNeedsDisplay]; }
- (BOOL)visible:(NSDictionary *)item { double now = CMTimeGetSeconds(self.currentTime), start = [item[@"start"] doubleValue]; id endValue = item[@"end"]; double end = [endValue isKindOfClass:NSNumber.class] ? [endValue doubleValue] : CGFLOAT_MAX; if (!isfinite(now) || !isfinite(start)) return NO; return now + .03 >= start && now <= end + .03; }
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
        WJDrawAxisSectors(ctx, first, hypot(last.x-first.x, last.y-first.y), tool);
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
        if ([text isEqualToString:@"👍"] || [text isEqualToString:@"👎"]) { [text drawAtPoint:first withAttributes:@{NSFontAttributeName:[UIFont boldSystemFontOfSize:28], NSForegroundColorAttributeName:color}]; return; }
        UIFont *font = [UIFont boldSystemFontOfSize:22];
        CGSize textSize = [text sizeWithAttributes:@{NSFontAttributeName:font}];
        CGFloat dx = last.x - first.x, dy = last.y - first.y;
        CGPoint origin = CGPointMake(dx >= 0 ? last.x : last.x - textSize.width, dy >= 0 ? last.y : last.y - textSize.height);
        CGPoint connect = CGPointMake(dx >= 0 ? origin.x : origin.x + textSize.width, dy >= 0 ? origin.y : origin.y + textSize.height);
        CGContextMoveToPoint(ctx, first.x, first.y); CGContextAddLineToPoint(ctx, connect.x, connect.y); CGContextStrokePath(ctx);
        CGFloat arrowAngle = atan2(connect.y-first.y, connect.x-first.x), arrowSize = 12;
        CGContextMoveToPoint(ctx, first.x, first.y); CGContextAddLineToPoint(ctx, first.x + arrowSize*cos(arrowAngle-M_PI/6), first.y + arrowSize*sin(arrowAngle-M_PI/6));
        CGContextMoveToPoint(ctx, first.x, first.y); CGContextAddLineToPoint(ctx, first.x + arrowSize*cos(arrowAngle+M_PI/6), first.y + arrowSize*sin(arrowAngle+M_PI/6)); CGContextStrokePath(ctx);
        [text drawAtPoint:origin withAttributes:@{NSFontAttributeName:font, NSForegroundColorAttributeName:color}];
    } else { CGContextMoveToPoint(ctx, first.x, first.y); for (NSValue *v in points) CGContextAddLineToPoint(ctx, v.CGPointValue.x, v.CGPointValue.y); CGContextStrokePath(ctx); if ([tool isEqualToString:@"矢印"] && points.count > 1) { CGFloat angle = atan2(last.y-first.y, last.x-first.x), size = 12; CGContextMoveToPoint(ctx, first.x, first.y); CGContextAddLineToPoint(ctx, first.x+size*cos(angle-M_PI/6), first.y+size*sin(angle-M_PI/6)); CGContextMoveToPoint(ctx, first.x, first.y); CGContextAddLineToPoint(ctx, first.x+size*cos(angle+M_PI/6), first.y+size*sin(angle+M_PI/6)); CGContextStrokePath(ctx); } }
}
- (void)drawPreviewInContext:(CGContextRef)ctx {
    if (_activePoints.count < 1) return;
    CGPoint first = _activePoints.firstObject.CGPointValue, last = _activePoints.lastObject.CGPointValue;
    CGContextSetStrokeColorWithColor(ctx, self.foregroundColor.CGColor); CGContextSetLineWidth(ctx, 3.0);
    NSString *tool = self.tool ?: @"直線";
    UIColor *previewFill = self.foregroundColor;
    if ([tool isEqualToString:@"文字"]) {
        if (_activePoints.count > 1) {
            NSString *text = self.drawingText ?: @""; UIFont *font = [UIFont boldSystemFontOfSize:22]; CGSize textSize = [text sizeWithAttributes:@{NSFontAttributeName:font}];
            if ([text isEqualToString:@"👍"] || [text isEqualToString:@"👎"]) { [text drawAtPoint:first withAttributes:@{NSFontAttributeName:[UIFont boldSystemFontOfSize:28], NSForegroundColorAttributeName:self.foregroundColor}]; return; }
            CGFloat dx = last.x-first.x, dy = last.y-first.y;
            CGPoint origin = CGPointMake(dx >= 0 ? last.x : last.x-textSize.width, dy >= 0 ? last.y : last.y-textSize.height);
            CGPoint connect = CGPointMake(dx >= 0 ? origin.x : origin.x+textSize.width, dy >= 0 ? origin.y : origin.y+textSize.height);
            CGFloat a = atan2(connect.y-first.y, connect.x-first.x), s = 12;
            CGContextMoveToPoint(ctx, first.x, first.y); CGContextAddLineToPoint(ctx, connect.x, connect.y);
            CGContextMoveToPoint(ctx, first.x, first.y); CGContextAddLineToPoint(ctx, first.x+s*cos(a-M_PI/6), first.y+s*sin(a-M_PI/6));
            CGContextMoveToPoint(ctx, first.x, first.y); CGContextAddLineToPoint(ctx, first.x+s*cos(a+M_PI/6), first.y+s*sin(a+M_PI/6)); CGContextStrokePath(ctx);
            if (text.length) [text drawAtPoint:origin withAttributes:@{NSFontAttributeName:font, NSForegroundColorAttributeName:self.foregroundColor}];
        }
        return;
    }
    if ([tool isEqualToString:@"角度"]) {
        CGContextMoveToPoint(ctx, first.x, first.y); if (_activePoints.count > 1) CGContextAddLineToPoint(ctx, _activePoints[1].CGPointValue.x, _activePoints[1].CGPointValue.y); if (_activePoints.count > 2) { CGContextMoveToPoint(ctx, _activePoints[1].CGPointValue.x, _activePoints[1].CGPointValue.y); CGContextAddLineToPoint(ctx, last.x, last.y); } CGContextStrokePath(ctx); return;
    }
    if ([tool isEqualToString:@"軌道"]) { CGContextMoveToPoint(ctx, first.x, first.y); for (NSValue *v in _activePoints) CGContextAddLineToPoint(ctx, v.CGPointValue.x, v.CGPointValue.y); CGContextStrokePath(ctx); return; }
    if ([tool isEqualToString:@"フリー"]) { CGContextMoveToPoint(ctx, first.x, first.y); for (NSValue *v in _activePoints) CGContextAddLineToPoint(ctx, v.CGPointValue.x, v.CGPointValue.y); CGContextStrokePath(ctx); return; }
    if ([tool isEqualToString:@"軸1"] || [tool isEqualToString:@"軸2"] || [tool isEqualToString:@"軸3D"]) { WJDrawAxisSectors(ctx, first, hypot(last.x-first.x,last.y-first.y), self.tool); return; }
    if ([tool isEqualToString:@"丸"]) { CGFloat r=hypot(last.x-first.x,last.y-first.y); CGContextSetFillColorWithColor(ctx, [previewFill colorWithAlphaComponent:.2].CGColor); CGContextFillEllipseInRect(ctx, CGRectMake(first.x-r, first.y-r, r*2, r*2)); return; }
    if ([tool isEqualToString:@"楕円"] || [tool isEqualToString:@"四角"] || [tool isEqualToString:@"三角"]) { CGRect rect=CGRectStandardize(CGRectMake(first.x,first.y,last.x-first.x,last.y-first.y)); CGContextSetFillColorWithColor(ctx,[previewFill colorWithAlphaComponent:.2].CGColor); if ([tool isEqualToString:@"楕円"]) CGContextFillEllipseInRect(ctx,rect); else if ([tool isEqualToString:@"三角"]) { CGContextBeginPath(ctx); CGContextMoveToPoint(ctx,CGRectGetMidX(rect),CGRectGetMinY(rect)); CGContextAddLineToPoint(ctx,CGRectGetMaxX(rect),CGRectGetMaxY(rect)); CGContextAddLineToPoint(ctx,CGRectGetMinX(rect),CGRectGetMaxY(rect)); CGContextClosePath(ctx); CGContextFillPath(ctx); } else CGContextFillRect(ctx,rect); return; }
    if ([tool isEqualToString:@"x"]) { CGFloat arm=MAX(4.0, hypot(last.x-first.x,last.y-first.y)); CGContextMoveToPoint(ctx,first.x-arm,first.y); CGContextAddLineToPoint(ctx,first.x+arm,first.y); CGContextMoveToPoint(ctx,first.x,first.y-arm); CGContextAddLineToPoint(ctx,first.x,first.y+arm); CGContextStrokePath(ctx); }
    else { CGContextMoveToPoint(ctx, first.x, first.y); CGContextAddLineToPoint(ctx, last.x, last.y); CGContextStrokePath(ctx); }
    if ([tool isEqualToString:@"矢印"]) { CGFloat a=atan2(last.y-first.y,last.x-first.x),s=12; CGContextMoveToPoint(ctx,first.x,first.y); CGContextAddLineToPoint(ctx,first.x+s*cos(a-M_PI/6),first.y+s*sin(a-M_PI/6)); CGContextMoveToPoint(ctx,first.x,first.y); CGContextAddLineToPoint(ctx,first.x+s*cos(a+M_PI/6),first.y+s*sin(a+M_PI/6)); CGContextStrokePath(ctx); }
}
- (void)drawRect:(CGRect)rect { CGContextRef ctx = UIGraphicsGetCurrentContext(); for (NSDictionary *item in self.annotations) if ([self visible:item]) [self drawAnnotation:item inContext:ctx]; [self drawPreviewInContext:ctx]; }
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { if (!self.drawingEnabled) return; CGPoint p=[[touches anyObject] locationInView:self]; if ([self.tool isEqualToString:@"角度"]) { // ドラッグ方式と、点を順番にタップする方式の両方を受け付ける。
        if (_activePoints.count < 3) [_activePoints addObject:[NSValue valueWithCGPoint:p]];
    } else if ([self.tool isEqualToString:@"軌道"]) {
        [_activePoints addObject:[NSValue valueWithCGPoint:p]];
    } else {
        [_activePoints removeAllObjects]; [_activePoints addObject:[NSValue valueWithCGPoint:p]];
    } [self setNeedsDisplay]; }
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { if (!self.drawingEnabled || _activePoints.count==0) return; CGPoint p=[[touches anyObject] locationInView:self]; if ([self.tool isEqualToString:@"軌道"] || [self.tool isEqualToString:@"フリー"]) { [_activePoints addObject:[NSValue valueWithCGPoint:p]]; } else { if (_activePoints.count==1) [_activePoints addObject:[NSValue valueWithCGPoint:p]]; else _activePoints[_activePoints.count-1]=[NSValue valueWithCGPoint:p]; } [self setNeedsDisplay]; }
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!self.drawingEnabled || _activePoints.count == 0) return;
    // touchesMoved が最後のサンプルを届けないことがあるため、終了位置を必ず保存する。
    CGPoint finalPoint = [[touches anyObject] locationInView:self];
    if ([self.tool isEqualToString:@"フリー"] || [self.tool isEqualToString:@"x"]) {
        [_activePoints addObject:[NSValue valueWithCGPoint:finalPoint]];
    } else if (![self.tool isEqualToString:@"軌道"] && ![self.tool isEqualToString:@"角度"]) {
        if (_activePoints.count == 1) [_activePoints addObject:[NSValue valueWithCGPoint:finalPoint]];
        else _activePoints[_activePoints.count - 1] = [NSValue valueWithCGPoint:finalPoint];
    }
    if ([self.tool isEqualToString:@"角度"] && _activePoints.count < 3) { [self setNeedsDisplay]; return; }
    if (self.commitBlock) self.commitBlock([_activePoints copy]);
    if (![self.tool isEqualToString:@"軌道"]) [_activePoints removeAllObjects];
    [self setNeedsDisplay];
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    // システムジェスチャーや画面遷移でキャンセルされた入力は確定しない。
    // 前回のプレビュー点を残すと、次の軸3D描画に混入して消失するため破棄する。
    [_activePoints removeAllObjects];
    [self setNeedsDisplay];
}
@end

@interface WaterJumpReceivedPlayerViewController () <UIColorPickerViewControllerDelegate>
@property (nonatomic, assign) float wjSelectedSpeed;
@property (nonatomic, strong) UIView *speedControlContainer;
@property (nonatomic, weak) UIView *speedControlHost;
@property (nonatomic, strong) UISlider *speedSlider;
@property (nonatomic, strong) UISlider *positionSlider;
@property (nonatomic, strong) UILabel *speedValueLabel;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) NSTimer *speedHideTimer;
@property (nonatomic, strong) UIView *featureControlContainer;
@property (nonatomic, strong) UIButton *compareButton;
@property (nonatomic, strong) UIButton *loopStartButton;
@property (nonatomic, strong) UIButton *loopEndButton;
@property (nonatomic, strong) UIButton *loopButton;
@property (nonatomic, strong) UIButton *frameStepButton;
@property (nonatomic, strong) UIButton *frameBackButton;
@property (nonatomic, strong) UILongPressGestureRecognizer *slowMotionGesture;
@property (nonatomic, strong) UILongPressGestureRecognizer *slowMotionBackGesture;
@property (nonatomic, assign) BOOL slowMotionActive;
@property (nonatomic, assign) BOOL suppressNextFrameStep;
@property (nonatomic, assign) BOOL suppressNextFrameBack;
@property (nonatomic, strong) UIButton *mirrorButton;
@property (nonatomic, assign) CMTime loopStartTime;
@property (nonatomic, assign) CMTime loopEndTime;
@property (nonatomic, assign) BOOL loopEnabled;
@property (nonatomic, assign) BOOL loopSeekInProgress;
@property (nonatomic, assign) BOOL mirroredPlayback;
@property (nonatomic, strong) id playbackTimeObserver;
@property (nonatomic, assign) NSInteger automaticLoopLimit;
@property (nonatomic, assign) NSInteger automaticLoopCount;
@property (nonatomic, strong) NSDate *automaticLoopDeadline;
@property (nonatomic, assign) BOOL handlingAutomaticLoop;
@property (nonatomic, strong) UILabel *analysisLabel;
@property (nonatomic, copy) NSArray<NSDictionary *> *analysisFrames;
@property (nonatomic, strong) TakeoffAnalysisConfig *takeoffConfig;
@property (nonatomic, strong) UIButton *takeoffButton;
@property (nonatomic, strong) UIButton *strobeButton;
@property (nonatomic, strong) UIButton *skeletonButton;
@property (nonatomic, strong) UIButton *deleteButton;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIButton *infoButton;
@property (nonatomic, strong) UIButton *shareButton;
@property (nonatomic, strong) UIButton *exportButton;
@property (nonatomic, strong) UIButton *favoriteButton;
@property (nonatomic, strong) UIImageView *favoriteIndicator;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, assign) BOOL favorite;
@property (nonatomic, assign) NSInteger takeoffSetupStep;
@property (nonatomic, strong) UILabel *ankleAnalysisLabel;
@property (nonatomic, strong) UILabel *kneeAnalysisLabel;
@property (nonatomic, strong) UILabel *hipAnalysisLabel;
@property (nonatomic, strong) UILabel *torsoAnalysisLabel;
@property (nonatomic, strong) CAShapeLayer *skeletonOverlayLayer;
@property (nonatomic, assign) BOOL skeletonVisible;
@property (nonatomic, copy) NSArray<NSURL *> *playlist;
@property (nonatomic, assign) NSInteger playlistIndex;
@property (nonatomic, strong) UIPanGestureRecognizer *playlistPanGesture;
@property (nonatomic, strong) UIPanGestureRecognizer *playlistOverlayPanGesture;
@property (nonatomic, assign) BOOL switchingPlaylist;
@property (nonatomic, strong) UIButton *drawingButton;
@property (nonatomic, strong) WJDrawingCanvas *drawingCanvas;
@property (nonatomic, strong) UIView *drawingPalette;
@property (nonatomic, strong) UIView *drawingTextPalette;
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *drawingAnnotations;
@property (nonatomic, assign) BOOL drawingMode;
@property (nonatomic, assign) CMTime drawingModeStartTime;
@property (nonatomic, copy) NSString *drawingTool;
@property (nonatomic, copy) NSString *drawingCategory;
@property (nonatomic, copy) NSString *drawingLineStyle;
@property (nonatomic, strong) UIColor *drawingForegroundColor;
@property (nonatomic, strong) UIColor *drawingBackgroundColor;
@property (nonatomic, copy) NSString *drawingText;
@property (nonatomic, strong) NSMutableArray<NSString *> *customDrawingTexts;
@property (nonatomic, assign) NSInteger drawingModeInitialAnnotationCount;
@property (nonatomic, strong) UIButton *rotationHandle;
@property (nonatomic, strong) UIButton *resizeHandle;
@property (nonatomic, strong) NSMutableDictionary *activeDrawingAnnotation;
@property (nonatomic, strong) UIColorPickerViewController *drawingColorPicker;
@property (nonatomic, assign) BOOL drawingColorPickerForBackground;
@end

@implementation WaterJumpReceivedPlayerViewController

- (instancetype)initWithVideoURL:(NSURL *)url {
    if ((self = [super init])) {
        _wjSelectedSpeed = 1.0f;
        _loopStartTime = kCMTimeInvalid;
        _loopEndTime = kCMTimeInvalid;
        self.player = [AVPlayer playerWithURL:url];
        self.videoGravity = AVLayerVideoGravityResizeAspect;
        self.modalPresentationStyle = UIModalPresentationFullScreen;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
        // AVPlayerViewController標準の「…」メニューは表示せず、MTJudge独自の操作群を使う。
        self.showsPlaybackControls = NO;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // iPadの既定のページシート変換を避け、受信動画は常に画面全体へ表示する。
    self.modalPresentationStyle = UIModalPresentationFullScreen;
    self.modalPresentationCapturesStatusBarAppearance = YES;
    self.view.backgroundColor = UIColor.blackColor;
    [self buildSpeedControls];
    self.analysisLabel = [UILabel new];
    self.analysisLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.analysisLabel.numberOfLines = 0;
    self.analysisLabel.textColor = UIColor.whiteColor;
    self.analysisLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightSemibold];
    self.analysisLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:.55];
    self.analysisLabel.layer.cornerRadius = 8;
    self.analysisLabel.clipsToBounds = YES;
    self.analysisLabel.text = @"解析データなし";
    self.analysisLabel.hidden = YES;
    UIView *host = self.contentOverlayView ?: self.view;
    [host addSubview:self.analysisLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.analysisLabel.leadingAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.leadingAnchor constant:16],
        [self.analysisLabel.topAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.topAnchor constant:56],
        [self.analysisLabel.widthAnchor constraintGreaterThanOrEqualToConstant:150]
    ]];
    self.favoriteIndicator = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"heart.fill"]];
    self.favoriteIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.favoriteIndicator.tintColor = UIColor.systemPinkColor;
    self.favoriteIndicator.hidden = YES;
    [host addSubview:self.favoriteIndicator];
    [NSLayoutConstraint activateConstraints:@[
        [self.favoriteIndicator.centerXAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.centerXAnchor],
        [self.favoriteIndicator.topAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.topAnchor constant:16],
        [self.favoriteIndicator.widthAnchor constraintEqualToConstant:30],
        [self.favoriteIndicator.heightAnchor constraintEqualToConstant:30]
    ]];
    self.ankleAnalysisLabel = [self makePartAnalysisLabel];
    self.kneeAnalysisLabel = [self makePartAnalysisLabel];
    self.hipAnalysisLabel = [self makePartAnalysisLabel];
    self.torsoAnalysisLabel = [self makePartAnalysisLabel];
    for (UILabel *label in @[self.ankleAnalysisLabel, self.kneeAnalysisLabel, self.hipAnalysisLabel, self.torsoAnalysisLabel]) {
        [host addSubview:label];
        label.hidden = YES;
    }
    self.skeletonOverlayLayer = [CAShapeLayer layer];
    self.skeletonOverlayLayer.strokeColor = [UIColor colorWithRed:0.20 green:0.95 blue:1.0 alpha:.95].CGColor;
    self.skeletonOverlayLayer.fillColor = UIColor.clearColor.CGColor;
    self.skeletonOverlayLayer.lineWidth = 2.5;
    self.skeletonOverlayLayer.lineCap = kCALineCapRound;
    self.skeletonOverlayLayer.hidden = YES;
    self.skeletonVisible = NO;
    [host.layer addSublayer:self.skeletonOverlayLayer];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerDidReachEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
    [self installPlaylistGestures];
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // contentOverlayViewがsafe areaだけのサイズになる環境でも、Player全体を覆う。
    self.contentOverlayView.frame = self.view.bounds;
    if (self.drawingCanvas && self.speedControlHost) self.drawingCanvas.frame = self.speedControlHost.bounds;
    [self updateRotationHandlePosition];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self installPlaylistGestures];
    [self showSpeedControls];
    if (!self.playbackTimeObserver) {
        __weak typeof(self) weakSelf = self;
        self.playbackTimeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMake(1, 30) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
            [weakSelf updatePositionSlider];
            [weakSelf updateAnalysisForTime:time];
            [weakSelf updateDrawingCanvasForTime:time];
            if (weakSelf.loopEnabled && CMTIME_IS_VALID(weakSelf.loopStartTime) && CMTIME_IS_VALID(weakSelf.loopEndTime) && CMTimeCompare(weakSelf.loopEndTime, weakSelf.loopStartTime) > 0) {
                if (!weakSelf.loopSeekInProgress && CMTimeCompare(time, weakSelf.loopEndTime) >= 0) {
                    AVPlayer *player = weakSelf.player; weakSelf.loopEnabled = NO;
                    weakSelf.loopSeekInProgress = YES;
                    [player seekToTime:weakSelf.loopStartTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) { dispatch_async(dispatch_get_main_queue(), ^{ weakSelf.loopSeekInProgress = NO; if (finished && weakSelf.player == player) { weakSelf.loopEnabled = YES; player.rate = weakSelf.wjSelectedSpeed; } }); }];
                }
                return;
            }
            // A/B 区間が未設定のときは、リピートボタンで動画全体をループする。
            if (weakSelf.loopEnabled && (!CMTIME_IS_VALID(weakSelf.loopStartTime) || !CMTIME_IS_VALID(weakSelf.loopEndTime))) {
                double duration = CMTimeGetSeconds(weakSelf.player.currentItem.duration);
                double current = CMTimeGetSeconds(time);
                if (!weakSelf.loopSeekInProgress && isfinite(duration) && duration > 0 && isfinite(current) && current >= duration - 0.08) {
                    AVPlayer *player = weakSelf.player;
                    weakSelf.loopSeekInProgress = YES;
                    [player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
                        dispatch_async(dispatch_get_main_queue(), ^{ weakSelf.loopSeekInProgress = NO; if (finished && weakSelf.player == player) player.rate = weakSelf.wjSelectedSpeed; });
                    }];
                }
                return;
            }
            double duration = CMTimeGetSeconds(weakSelf.player.currentItem.duration);
            double current = CMTimeGetSeconds(time);
            if (weakSelf.automaticLoopLimit == 0 || !isfinite(duration) || duration <= 0 || !isfinite(current) || current < duration - 0.15) return;
            [weakSelf handleAutomaticLoopAtEnd];
        }];
    }
    [self resetAndPlay];
    [self loadDrawingAnnotations];
    [self loadAnalysisForCurrentVideo];
    [self refreshFavoriteState];
}

- (void)installPlaylistGestures {
    if (!self.playlistPanGesture) {
        self.playlistPanGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePlaylistPan:)];
        self.playlistPanGesture.cancelsTouchesInView = YES;
        self.playlistPanGesture.maximumNumberOfTouches = 1;
        [self.view addGestureRecognizer:self.playlistPanGesture];
    }
    if (self.contentOverlayView && !self.playlistOverlayPanGesture) {
        self.playlistOverlayPanGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePlaylistPan:)];
        self.playlistOverlayPanGesture.cancelsTouchesInView = YES;
        self.playlistOverlayPanGesture.maximumNumberOfTouches = 1;
        [self.contentOverlayView addGestureRecognizer:self.playlistOverlayPanGesture];
    }
}

- (void)playerDidReachEnd:(NSNotification *)notification {
    if (notification.object != self.player.currentItem) return;
    if (self.loopEnabled) {
        if (self.loopSeekInProgress) return;
        self.loopSeekInProgress = YES;
        CMTime target = (CMTIME_IS_VALID(self.loopStartTime) && CMTIME_IS_VALID(self.loopEndTime) && CMTimeCompare(self.loopEndTime, self.loopStartTime) > 0) ? self.loopStartTime : kCMTimeZero;
        [self.player seekToTime:target toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
            dispatch_async(dispatch_get_main_queue(), ^{ self.loopSeekInProgress = NO; if (finished) self.player.rate = self.wjSelectedSpeed; });
        }];
        return;
    }
    if (self.playbackEndedHandler) {
        self.player.rate = 0;
        void (^handler)(void) = self.playbackEndedHandler;
        self.playbackEndedHandler = nil;
        [self dismissViewControllerAnimated:YES completion:handler];
        return;
    }
    [self handleAutomaticLoopAtEnd];
}

- (void)loadAnalysisForCurrentVideo {
    if (!self.skeletonVisible) {
        self.analysisFrames = nil;
        self.analysisLabel.hidden = YES;
        self.skeletonOverlayLayer.hidden = YES;
        return;
    }
    NSURL *url = [(AVURLAsset *)self.player.currentItem.asset URL];
    if (!url) return;
    self.analysisFrames = [[VideoPoseAnalysisManager sharedManager] loadFrameDataForVideoURL:url];
    self.takeoffConfig = [TakeoffAnalysisConfig configForVideoURL:url];
    if (self.analysisFrames.count) { self.analysisLabel.hidden = NO; [self updateAnalysisForTime:self.player.currentTime]; return; }
    for (UILabel *label in @[self.ankleAnalysisLabel, self.kneeAnalysisLabel, self.hipAnalysisLabel, self.torsoAnalysisLabel]) label.hidden = YES;
    self.analysisLabel.hidden = YES;
    __weak typeof(self) weakSelf = self;
    [[VideoPoseAnalysisManager sharedManager] analyzeVideoURL:url completion:^(NSURL *resultURL, NSError *error) {
        if (!weakSelf || error) return;
        weakSelf.analysisFrames = [[VideoPoseAnalysisManager sharedManager] loadFrameDataForVideoURL:url];
        weakSelf.takeoffConfig = [TakeoffAnalysisConfig configForVideoURL:url];
        weakSelf.analysisLabel.hidden = weakSelf.analysisFrames.count == 0;
        if (!weakSelf.analysisFrames.count) for (UILabel *label in @[weakSelf.ankleAnalysisLabel, weakSelf.kneeAnalysisLabel, weakSelf.hipAnalysisLabel, weakSelf.torsoAnalysisLabel]) label.hidden = YES;
        [weakSelf updateAnalysisForTime:weakSelf.player.currentTime];
    }];
}

- (void)updateAnalysisForTime:(CMTime)time {
    if (!self.skeletonVisible || !self.analysisFrames.count) {
        self.skeletonOverlayLayer.hidden = YES;
        self.analysisLabel.hidden = YES;
        for (UILabel *label in @[self.ankleAnalysisLabel, self.kneeAnalysisLabel, self.hipAnalysisLabel, self.torsoAnalysisLabel]) label.hidden = YES;
        return;
    }
    double timestamp = CMTimeGetSeconds(time); NSDictionary *best = nil; double distance = DBL_MAX;
    for (NSDictionary *frame in self.analysisFrames) { double candidate = [frame[@"timestamp"] doubleValue]; double d = fabs(candidate - timestamp); if (d < distance) { distance = d; best = frame; } }
    if (!best || distance > .25) {
        self.skeletonOverlayLayer.hidden = YES;
        for (UILabel *label in @[self.ankleAnalysisLabel, self.kneeAnalysisLabel, self.hipAnalysisLabel, self.torsoAnalysisLabel]) label.hidden = YES;
        return;
    }
    [self drawSkeletonForFrame:best];
    NSDictionary *takeoff = self.takeoffConfig ? [TakeoffAngleAnalyzer resultForFrame:best config:self.takeoffConfig] : nil;
    if (takeoff) {
        NSString *ankle = takeoff[@"ankleAngle"] ? [NSString stringWithFormat:@"%.1f°", [takeoff[@"ankleAngle"] doubleValue]] : @"--";
        NSString *knee = takeoff[@"kneeAngle"] ? [NSString stringWithFormat:@"%.1f°", [takeoff[@"kneeAngle"] doubleValue]] : @"--";
        NSString *hip = takeoff[@"hipAngle"] ? [NSString stringWithFormat:@"%.1f°", [takeoff[@"hipAngle"] doubleValue]] : @"--";
        NSString *torso = takeoff[@"torsoRampAngle"] ? [NSString stringWithFormat:@"%.1f°", [takeoff[@"torsoRampAngle"] doubleValue]] : @"--";
        // 踏切解析時は4項目を左上にまとめず、対応する関節の右側へ表示する。
        self.analysisLabel.hidden = YES;
        NSString *side = [takeoff[@"analysisSide"] isEqualToString:@"RIGHT"] ? @"right" : @"left";
        NSDictionary *joints = best[@"joints"];
        NSDictionary *ankleJoint = joints[[NSString stringWithFormat:@"%@Ankle", side]];
        NSDictionary *kneeJoint = joints[[NSString stringWithFormat:@"%@Knee", side]];
        NSDictionary *hipJoint = joints[[NSString stringWithFormat:@"%@Hip", side]];
        NSDictionary *shoulderJoint = joints[[NSString stringWithFormat:@"%@Shoulder", side]];
        self.ankleAnalysisLabel.text = [NSString stringWithFormat:@"ANKLE %@", ankle];
        self.kneeAnalysisLabel.text = [NSString stringWithFormat:@"KNEE %@", knee];
        self.hipAnalysisLabel.text = [NSString stringWithFormat:@"HIP %@", hip];
        self.torsoAnalysisLabel.text = [NSString stringWithFormat:@"TORSO %@", torso];
        [self positionPartLabel:self.ankleAnalysisLabel besideJoint:ankleJoint host:self.contentOverlayView ?: self.view];
        [self positionPartLabel:self.kneeAnalysisLabel besideJoint:kneeJoint host:self.contentOverlayView ?: self.view];
        [self positionPartLabel:self.hipAnalysisLabel besideJoint:hipJoint host:self.contentOverlayView ?: self.view];
        [self positionPartLabel:self.torsoAnalysisLabel besideJoint:shoulderJoint host:self.contentOverlayView ?: self.view];
        return;
    }
    for (UILabel *label in @[self.ankleAnalysisLabel, self.kneeAnalysisLabel, self.hipAnalysisLabel, self.torsoAnalysisLabel]) label.hidden = YES;
    self.analysisLabel.hidden = NO;
    NSString *left = best[@"leftKneeAngle"] ? [NSString stringWithFormat:@"L %d°", (int)round([best[@"leftKneeAngle"] doubleValue])] : @"L --";
    NSString *right = best[@"rightKneeAngle"] ? [NSString stringWithFormat:@"R %d°", (int)round([best[@"rightKneeAngle"] doubleValue])] : @"R --";
    NSString *torso = best[@"torsoVerticalAngle"] ? [NSString stringWithFormat:@"%.1f°", [best[@"torsoVerticalAngle"] doubleValue]] : @"--";
    NSString *absorption = best[@"absorption"] ? [NSString stringWithFormat:@"%d%%", (int)round([best[@"absorption"] doubleValue])] : @"--";
    self.analysisLabel.text = [NSString stringWithFormat:@"KNEE\n%@  %@\nTORSO  %@\nABSORPTION  %@", left, right, torso, absorption];
}

- (void)drawSkeletonForFrame:(NSDictionary *)frame {
    UIView *host = self.contentOverlayView ?: self.view;
    NSDictionary *joints = frame[@"joints"];
    if (![joints isKindOfClass:NSDictionary.class] || host.bounds.size.width <= 0 || host.bounds.size.height <= 0) { self.skeletonOverlayLayer.hidden = YES; return; }
    UIBezierPath *path = [UIBezierPath bezierPath];
    for (NSArray<NSString *> *connection in SkeletonConnections()) {
        NSDictionary *a = joints[connection.firstObject];
        NSDictionary *b = joints[connection.lastObject];
        if (![a isKindOfClass:NSDictionary.class] || ![b isKindOfClass:NSDictionary.class]) continue;
        if ([a[@"confidence"] doubleValue] <= .1 || [b[@"confidence"] doubleValue] <= .1) continue;
        CGPoint p1 = CGPointMake([a[@"x"] doubleValue] * host.bounds.size.width, (1.0 - [a[@"y"] doubleValue]) * host.bounds.size.height);
        CGPoint p2 = CGPointMake([b[@"x"] doubleValue] * host.bounds.size.width, (1.0 - [b[@"y"] doubleValue]) * host.bounds.size.height);
        [path moveToPoint:p1]; [path addLineToPoint:p2];
    }
    self.skeletonOverlayLayer.frame = host.bounds;
    self.skeletonOverlayLayer.path = path.CGPath;
    self.skeletonOverlayLayer.hidden = !self.skeletonVisible || path.isEmpty;
}

- (UILabel *)makePartAnalysisLabel {
    UILabel *label = [UILabel new];
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightSemibold];
    label.backgroundColor = [UIColor colorWithWhite:0 alpha:.62];
    label.layer.cornerRadius = 5;
    label.clipsToBounds = YES;
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 1;
    return label;
}

- (void)positionPartLabel:(UILabel *)label besideJoint:(NSDictionary *)joint host:(UIView *)host {
    if (![joint isKindOfClass:NSDictionary.class] || !joint[@"x"] || !joint[@"y"]) { label.hidden = YES; return; }
    CGFloat x = (CGFloat)[joint[@"x"] doubleValue] * host.bounds.size.width;
    CGFloat y = (CGFloat)(1.0 - [joint[@"y"] doubleValue]) * host.bounds.size.height;
    CGSize size = [label sizeThatFits:CGSizeMake(150, 28)];
    CGFloat left = MIN(MAX(x + 12.0, 8.0), MAX(8.0, host.bounds.size.width - size.width - 8.0));
    CGFloat top = MIN(MAX(y - size.height * .5, 8.0), MAX(8.0, host.bounds.size.height - size.height - 8.0));
    label.frame = CGRectMake(left, top, MAX(size.width + 10.0, 72.0), MAX(size.height, 24.0));
    label.hidden = NO;
}

- (void)handleAutomaticLoopAtEnd {
    if (self.handlingAutomaticLoop || self.automaticLoopLimit == 0) return;
    if (self.automaticLoopDeadline && [[NSDate date] compare:self.automaticLoopDeadline] != NSOrderedAscending) { self.automaticLoopLimit = 0; return; }
    if (self.automaticLoopLimit > 0 && self.automaticLoopCount >= self.automaticLoopLimit) { self.automaticLoopLimit = 0; return; }
    self.handlingAutomaticLoop = YES;
    self.automaticLoopCount += 1;
    __weak typeof(self) weakSelf = self;
    [self.player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.handlingAutomaticLoop = NO;
            if (finished) weakSelf.player.rate = weakSelf.wjSelectedSpeed;
        });
    }];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
    [self.speedHideTimer invalidate];
    if (self.playbackTimeObserver) [self.player removeTimeObserver:self.playbackTimeObserver];
}

- (void)buildSpeedControls {
    // AVPlayerViewControllerの標準プレイヤーより前面に表示されるoverlayへ追加する。
    // self.view直下ではOSの標準コントロールに隠れる場合がある。
    UIView *host = self.contentOverlayView ?: self.view;
    self.speedControlHost = host;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(playerTapped:)];
    tap.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tap];
    if (self.contentOverlayView) {
        UITapGestureRecognizer *overlayTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(playerTapped:)];
        overlayTap.cancelsTouchesInView = NO;
        [self.contentOverlayView addGestureRecognizer:overlayTap];
    }
    self.speedControlContainer = [[UIView alloc] init];
    self.speedControlContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.speedControlContainer.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    self.speedControlContainer.layer.cornerRadius = 12;
    self.speedControlContainer.hidden = YES;
    [host addSubview:self.speedControlContainer];
    self.speedSlider = [UISlider new];
    self.speedSlider.translatesAutoresizingMaskIntoConstraints = NO;
    self.speedSlider.minimumValue = 0.25;
    self.speedSlider.maximumValue = 1.0;
    self.speedSlider.value = 1.0;
    self.speedSlider.minimumTrackTintColor = [UIColor colorWithWhite:0.82 alpha:0.75];
    self.speedSlider.maximumTrackTintColor = [UIColor colorWithWhite:0.55 alpha:0.35];
    self.speedSlider.accessibilityLabel = @"再生速度";
    [self.speedSlider addTarget:self action:@selector(speedSliderChanged:) forControlEvents:UIControlEventValueChanged];
    self.speedValueLabel = [UILabel new];
    self.speedValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.speedValueLabel.textColor = UIColor.whiteColor;
    self.speedValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightSemibold];
    self.speedValueLabel.text = @"1.00×";
    self.timeLabel = [UILabel new];
    self.timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.timeLabel.textColor = [UIColor colorWithWhite:1 alpha:.82];
    self.timeLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium];
    self.timeLabel.text = @"00:00.00/00:00.00";
    self.timeLabel.textAlignment = NSTextAlignmentCenter;
    self.timeLabel.adjustsFontSizeToFitWidth = YES;
    self.timeLabel.minimumScaleFactor = .65;
    self.timeLabel.hidden = YES;
    [self.speedControlContainer addSubview:self.speedSlider];
    [self.speedControlContainer addSubview:self.speedValueLabel];
    // 時刻表示はシークバー付近に置くと上部の操作アイコンと重なるため、
    // プレイヤー上部中央へ独立配置する。
    [host addSubview:self.timeLabel];
    self.positionSlider = [UISlider new];
    self.positionSlider.translatesAutoresizingMaskIntoConstraints = NO;
    self.positionSlider.minimumValue = 0;
    self.positionSlider.maximumValue = 1;
    self.positionSlider.minimumTrackTintColor = UIColor.systemBlueColor;
    self.positionSlider.accessibilityLabel = @"再生位置";
    [self.positionSlider addTarget:self action:@selector(positionSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.speedControlContainer addSubview:self.positionSlider];
    [NSLayoutConstraint activateConstraints:@[
        [self.speedControlContainer.centerXAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.centerXAnchor],
        [self.speedControlContainer.bottomAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.bottomAnchor constant:-24],
        [self.speedControlContainer.widthAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.widthAnchor constant:-32],
        [self.speedControlContainer.widthAnchor constraintLessThanOrEqualToConstant:900],
        [self.speedControlContainer.heightAnchor constraintEqualToConstant:88],
        // シークバーは左右の操作ボタンの間だけを使う。
        // 時刻表示を上部へ移したため、シークバー左側の空白をなくし、
        // 再生ボタンの直後から開始する。
        [self.positionSlider.leadingAnchor constraintEqualToAnchor:self.speedControlContainer.leadingAnchor constant:56],
        // コマ戻しボタンと重ならないよう、右端にアイコン幅の約半分を追加で確保する。
        [self.positionSlider.trailingAnchor constraintEqualToAnchor:self.speedControlContainer.trailingAnchor constant:-82],
        [self.positionSlider.centerYAnchor constraintEqualToAnchor:self.speedControlContainer.topAnchor constant:30],
        [self.speedSlider.leadingAnchor constraintEqualToAnchor:self.speedControlContainer.leadingAnchor constant:12],
        [self.speedSlider.bottomAnchor constraintEqualToAnchor:self.speedControlContainer.bottomAnchor constant:-6],
        [self.speedSlider.centerYAnchor constraintEqualToAnchor:self.speedControlContainer.bottomAnchor constant:-25],
        [self.speedSlider.trailingAnchor constraintEqualToAnchor:self.speedValueLabel.leadingAnchor constant:-8],
        [self.speedValueLabel.trailingAnchor constraintEqualToAnchor:self.speedControlContainer.trailingAnchor constant:-12],
        [self.speedValueLabel.centerYAnchor constraintEqualToAnchor:self.speedSlider.centerYAnchor],
        [self.speedValueLabel.widthAnchor constraintEqualToConstant:42],
        // 上中央のお気に入り表示（約16〜46pt）と重ならないよう、その下へ配置する。
        [self.timeLabel.topAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.topAnchor constant:54],
        [self.timeLabel.centerXAnchor constraintEqualToAnchor:host.centerXAnchor],
        [self.timeLabel.widthAnchor constraintEqualToConstant:150],
        [self.timeLabel.heightAnchor constraintEqualToConstant:22]
    ]];
    self.featureControlContainer = [[UIView alloc] init];
    self.featureControlContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.featureControlContainer.backgroundColor = UIColor.clearColor;
    self.featureControlContainer.layer.cornerRadius = 0;
    self.featureControlContainer.hidden = YES;
    [host addSubview:self.featureControlContainer];
    self.loopStartButton = [self featureButtonWithSymbol:@"a.circle" action:@selector(setLoopStart:) label:@"A点を設定"];
    self.loopEndButton = [self featureButtonWithSymbol:@"b.circle" action:@selector(setLoopEnd:) label:@"B点を設定"];
    self.loopButton = [self featureButtonWithSymbol:@"repeat" action:@selector(toggleLoop:) label:@"A-Bリピート"];
    self.frameStepButton = [self featureButtonWithSymbol:@"forward.frame" action:@selector(stepOneFrame:) label:@"1フレーム進む"];
    self.slowMotionGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(frameStepLongPressed:)];
    self.slowMotionGesture.minimumPressDuration = 0.45;
    self.slowMotionGesture.cancelsTouchesInView = YES;
    [self.frameStepButton addGestureRecognizer:self.slowMotionGesture];
    self.frameBackButton = [self featureButtonWithSymbol:@"backward.frame" action:@selector(stepOneFrameBack:) label:@"1フレーム戻る"];
    self.slowMotionBackGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(frameBackLongPressed:)];
    self.slowMotionBackGesture.minimumPressDuration = 0.45;
    self.slowMotionBackGesture.cancelsTouchesInView = YES;
    [self.frameBackButton addGestureRecognizer:self.slowMotionBackGesture];
    self.mirrorButton = [self featureButtonWithSymbol:@"arrow.left.and.right.righttriangle.left.righttriangle.right" action:@selector(toggleMirror:) label:@"左右反転"];
    self.takeoffButton = [self featureButtonWithSymbol:@"figure.skiing.downhill" action:@selector(toggleTakeoffSetup:) label:@"Takeoff解析設定"];
    self.takeoffButton.enabled = NO;
    self.takeoffButton.alpha = .4;
    self.skeletonButton = [self featureButtonWithSymbol:@"figure.stand" action:@selector(toggleSkeleton:) label:@"骨格線表示"];
    self.strobeButton = [self featureButtonWithSymbol:@"camera.aperture" action:@selector(toggleStrobe:) label:@"ストロボ画像"];
    self.strobeButton.tintColor = UIColor.systemOrangeColor;
    self.compareButton = [self featureButtonWithSymbol:@"plus.rectangle.on.rectangle" action:@selector(selectComparisonVideo:) label:@"比較する動画を選択"];
    self.compareButton.tintColor = UIColor.systemGreenColor;
    self.deleteButton = [self featureButtonWithSymbol:@"trash" action:@selector(deleteCurrentVideo:) label:@"再生中の動画を削除"];
    self.deleteButton.tintColor = UIColor.systemRedColor;
    self.deleteButton.hidden = YES;
    self.playButton = [self featureButtonWithSymbol:@"pause.fill" action:@selector(togglePlay:) label:@"再生・一時停止"];
    self.playButton.hidden = YES;
    self.shareButton = [self featureButtonWithSymbol:@"square.and.arrow.up" action:@selector(shareCurrentVideo:) label:@"動画を共有"];
    self.exportButton = [self featureButtonWithSymbol:@"square.and.arrow.down" action:@selector(exportDrawingVideo:) label:@"描画付き動画を書き出す"];
    self.favoriteButton = [self featureButtonWithSymbol:@"heart" action:@selector(toggleFavorite:) label:@"お気に入り"];
    self.favoriteButton.hidden = YES;
    self.closeButton = [self featureButtonWithSymbol:@"xmark" action:@selector(closePlayer:) label:@"閉じる"];
    self.closeButton.tintColor = UIColor.whiteColor;
    // 閉じる操作は常に見えるよう、機能ボタン列から分離して左上へ固定する。
    self.closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [host addSubview:self.closeButton];
    [NSLayoutConstraint activateConstraints:@[
        [self.closeButton.leadingAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.leadingAnchor constant:12],
        [self.closeButton.topAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.topAnchor constant:12],
        [self.closeButton.widthAnchor constraintEqualToConstant:38],
        [self.closeButton.heightAnchor constraintEqualToConstant:36]
    ]];
    self.infoButton = [self featureButtonWithSymbol:@"info.circle" action:@selector(showVideoInfo:) label:@"動画情報"];
    self.infoButton.tintColor = UIColor.whiteColor;
    self.infoButton.translatesAutoresizingMaskIntoConstraints = NO;
    [host addSubview:self.infoButton];
    [NSLayoutConstraint activateConstraints:@[
        [self.infoButton.leadingAnchor constraintEqualToAnchor:self.closeButton.trailingAnchor constant:12],
        [self.infoButton.centerYAnchor constraintEqualToAnchor:self.closeButton.centerYAnchor],
        [self.infoButton.widthAnchor constraintEqualToConstant:38],
        [self.infoButton.heightAnchor constraintEqualToConstant:36]
    ]];
    self.drawingButton = [self featureButtonWithSymbol:@"pencil" action:@selector(toggleDrawingMode:) label:@"描画モード"]; 
    self.drawingButton.tintColor = UIColor.systemYellowColor;
    self.drawingButton.hidden = YES;
    self.drawingButton.translatesAutoresizingMaskIntoConstraints = NO;
    [host addSubview:self.drawingButton];
    [NSLayoutConstraint activateConstraints:@[
        [self.drawingButton.leadingAnchor constraintEqualToAnchor:self.closeButton.trailingAnchor constant:76],
        [self.drawingButton.topAnchor constraintEqualToAnchor:self.closeButton.topAnchor],
        [self.drawingButton.widthAnchor constraintEqualToConstant:38], [self.drawingButton.heightAnchor constraintEqualToConstant:36]
    ]];
    self.drawingCanvas = [[WJDrawingCanvas alloc] initWithFrame:host.bounds];
    self.drawingCanvas.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.drawingCanvas.hidden = YES;
    [host addSubview:self.drawingCanvas];
    self.rotationHandle = [self featureButtonWithSymbol:@"arrow.triangle.2.circlepath" action:@selector(rotationHandleTapped:) label:@"図形を回転"];
    self.rotationHandle.hidden = YES;
    self.rotationHandle.translatesAutoresizingMaskIntoConstraints = YES;
    [host addSubview:self.rotationHandle];
    UIPanGestureRecognizer *rotationPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(rotateDrawing:)];
    [self.rotationHandle addGestureRecognizer:rotationPan];
    self.resizeHandle = [self featureButtonWithSymbol:@"arrow.up.left.and.arrow.down.right" action:@selector(resizeHandleTapped:) label:@"図形の大きさを変更"];
    self.resizeHandle.hidden = YES;
    self.resizeHandle.translatesAutoresizingMaskIntoConstraints = YES;
    [host addSubview:self.resizeHandle];
    UIPanGestureRecognizer *resizePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(resizeDrawing:)];
    [self.resizeHandle addGestureRecognizer:resizePan];
    self.drawingAnnotations = [NSMutableArray array];
    self.drawingTool = @"直線";
    self.drawingCategory = @"汎用";
    self.drawingLineStyle = @"実線";
    [self loadDrawingTextOptions];
    self.drawingForegroundColor = UIColor.greenColor;
    self.drawingBackgroundColor = UIColor.clearColor;
    self.drawingCanvas.foregroundColor = self.drawingForegroundColor;
    self.drawingCanvas.backgroundColorForDrawing = self.drawingBackgroundColor;
    __weak typeof(self) weakSelf = self;
    self.drawingCanvas.commitBlock = ^(NSArray<NSValue *> *points) { [weakSelf commitDrawingPoints:points]; };
    self.drawingCanvas.tapBlock = ^(CGPoint point) { [weakSelf drawingTextTappedAtPoint:point]; };
    [self buildDrawingPaletteInHost:host];
    // iPhoneの横幅でも操作できるよう、再生・コマ送り・お気に入り・削除は
    // 横一列のグループから外して固定位置に置く。
    self.frameBackButton.hidden = YES;
    self.frameStepButton.hidden = YES;
    for (UIButton *button in @[self.playButton, self.frameBackButton, self.frameStepButton, self.favoriteButton, self.deleteButton]) {
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [host addSubview:button];
    }
    [NSLayoutConstraint activateConstraints:@[
        [self.playButton.leadingAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.leadingAnchor constant:10],
        [self.playButton.centerYAnchor constraintEqualToAnchor:self.positionSlider.centerYAnchor],
        [self.playButton.widthAnchor constraintEqualToConstant:38], [self.playButton.heightAnchor constraintEqualToConstant:36],
        [self.frameStepButton.trailingAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.trailingAnchor constant:-10],
        [self.frameStepButton.centerYAnchor constraintEqualToAnchor:self.positionSlider.centerYAnchor],
        [self.frameStepButton.widthAnchor constraintEqualToConstant:38], [self.frameStepButton.heightAnchor constraintEqualToConstant:36],
        [self.frameBackButton.trailingAnchor constraintEqualToAnchor:self.frameStepButton.leadingAnchor constant:-4],
        [self.frameBackButton.centerYAnchor constraintEqualToAnchor:self.positionSlider.centerYAnchor],
        [self.frameBackButton.widthAnchor constraintEqualToConstant:38], [self.frameBackButton.heightAnchor constraintEqualToConstant:36],
        [self.favoriteButton.trailingAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.trailingAnchor constant:-16],
        [self.favoriteButton.topAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.topAnchor constant:12],
        [self.favoriteButton.widthAnchor constraintEqualToConstant:38], [self.favoriteButton.heightAnchor constraintEqualToConstant:36],
        // 削除は操作列と共有ボタンから離し、画面左中央に固定する。
        [self.deleteButton.leadingAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.leadingAnchor constant:10],
        [self.deleteButton.centerYAnchor constraintEqualToAnchor:host.centerYAnchor],
        [self.deleteButton.widthAnchor constraintEqualToConstant:38], [self.deleteButton.heightAnchor constraintEqualToConstant:36]
    ]];
    // 共有はお気に入りの直下へ固定し、中央の解析ボタン列から外す。
    self.shareButton.translatesAutoresizingMaskIntoConstraints = NO;
    [host addSubview:self.shareButton];
    [NSLayoutConstraint activateConstraints:@[
        [self.shareButton.trailingAnchor constraintEqualToAnchor:self.favoriteButton.leadingAnchor constant:-6],
        [self.shareButton.topAnchor constraintEqualToAnchor:self.favoriteButton.topAnchor],
        [self.shareButton.widthAnchor constraintEqualToConstant:38], [self.shareButton.heightAnchor constraintEqualToConstant:36]
    ]];
    self.exportButton.translatesAutoresizingMaskIntoConstraints = NO;
    [host addSubview:self.exportButton];
    [NSLayoutConstraint activateConstraints:@[
        [self.exportButton.trailingAnchor constraintEqualToAnchor:self.shareButton.leadingAnchor constant:-6],
        [self.exportButton.topAnchor constraintEqualToAnchor:self.favoriteButton.topAnchor],
        [self.exportButton.widthAnchor constraintEqualToConstant:38], [self.exportButton.heightAnchor constraintEqualToConstant:36]
    ]];
    // A点からTakeoffまでを画面幅の80%に広げ、均等間隔で配置する。
    UIStackView *featureStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.loopStartButton, self.loopEndButton, self.loopButton, self.mirrorButton, self.skeletonButton, self.takeoffButton, self.strobeButton, self.compareButton]];
    featureStack.translatesAutoresizingMaskIntoConstraints = NO;
    featureStack.axis = UILayoutConstraintAxisHorizontal;
    featureStack.alignment = UIStackViewAlignmentCenter;
    featureStack.distribution = UIStackViewDistributionEqualSpacing;
    featureStack.spacing = 5;
    [self.featureControlContainer addSubview:featureStack];
    [NSLayoutConstraint activateConstraints:@[
        [self.featureControlContainer.centerXAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.centerXAnchor],
        [self.featureControlContainer.bottomAnchor constraintEqualToAnchor:self.speedControlContainer.topAnchor constant:-8],
        [self.featureControlContainer.widthAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.widthAnchor multiplier:0.94],
        [self.featureControlContainer.widthAnchor constraintLessThanOrEqualToConstant:700],
        [self.featureControlContainer.heightAnchor constraintEqualToConstant:44],
        [featureStack.leadingAnchor constraintEqualToAnchor:self.featureControlContainer.leadingAnchor constant:8],
        [featureStack.trailingAnchor constraintEqualToAnchor:self.featureControlContainer.trailingAnchor constant:-8],
        [featureStack.topAnchor constraintEqualToAnchor:self.featureControlContainer.topAnchor constant:4],
        [featureStack.bottomAnchor constraintEqualToAnchor:self.featureControlContainer.bottomAnchor constant:-4]
    ]];
}

- (void)buildDrawingPaletteInHost:(UIView *)host {
    self.drawingPalette = [[UIView alloc] initWithFrame:CGRectMake(8, 120, 112, 348)];
    self.drawingPalette.backgroundColor = [UIColor colorWithWhite:0 alpha:.72];
    self.drawingPalette.layer.cornerRadius = 10;
    self.drawingPalette.hidden = YES;
    [host addSubview:self.drawingPalette];
    NSArray *titles = @[@"カテゴリ", @"描画種別", @"色", @"文字", @"線種"];
    NSArray *actions = @[@"drawingCategoryMenu:", @"drawingToolMenu:", @"drawingForegroundMenu:", @"drawingTextMenu:", @"drawingLineStyleMenu:"];
    for (NSInteger i = 0; i < titles.count; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.frame = CGRectMake(6, 8 + i * 46, 100, 38);
        [button setTitle:titles[i] forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        button.titleLabel.numberOfLines = 2;
        button.titleLabel.textAlignment = NSTextAlignmentCenter;
        button.titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
        button.titleLabel.adjustsFontSizeToFitWidth = NO;
        button.contentEdgeInsets = UIEdgeInsetsMake(2, 2, 2, 2);
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        button.backgroundColor = [UIColor colorWithWhite:1 alpha:.14];
        button.layer.cornerRadius = 6;
        button.tag = i + 1;
        [button addTarget:self action:NSSelectorFromString(actions[i]) forControlEvents:UIControlEventTouchUpInside];
        [self.drawingPalette addSubview:button];
    }
    UIButton *undo = [UIButton buttonWithType:UIButtonTypeSystem];
    undo.frame = CGRectMake(6, 8 + titles.count * 46, 100, 38);
    undo.accessibilityLabel = @"直前の描画を取り消す";
    [undo setImage:[UIImage systemImageNamed:@"arrow.uturn.backward"] forState:UIControlStateNormal];
    [undo setTitle:nil forState:UIControlStateNormal];
    undo.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [undo setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    undo.backgroundColor = [UIColor colorWithWhite:1 alpha:.14];
    undo.layer.cornerRadius = 6;
    [undo addTarget:self action:@selector(undoDrawing:) forControlEvents:UIControlEventTouchUpInside];
    [self.drawingPalette addSubview:undo];
    UIButton *clear = [UIButton buttonWithType:UIButtonTypeSystem];
    clear.frame = CGRectMake(6, 8 + (titles.count + 1) * 46, 100, 38);
    [clear setTitle:nil forState:UIControlStateNormal];
    [clear setImage:[UIImage systemImageNamed:@"trash"] forState:UIControlStateNormal];
    clear.accessibilityLabel = @"カテゴリの描画を削除";
    clear.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [clear setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
    clear.backgroundColor = [UIColor colorWithWhite:1 alpha:.14];
    clear.layer.cornerRadius = 6;
    [clear addTarget:self action:@selector(clearDrawingCategory:) forControlEvents:UIControlEventTouchUpInside];
    [self.drawingPalette addSubview:clear];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(moveDrawingPalette:)];
    [self.drawingPalette addGestureRecognizer:pan];
    [self refreshDrawingPaletteState];
    // 「文字」選択時だけ、左側パレットの反対側に表示する専用ボタン群。
    self.drawingTextPalette = [[UIView alloc] initWithFrame:CGRectMake(host.bounds.size.width - 138, 120, 130, 430)];
    self.drawingTextPalette.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    self.drawingTextPalette.backgroundColor = [UIColor colorWithWhite:0 alpha:.55];
    self.drawingTextPalette.layer.cornerRadius = 10;
    self.drawingTextPalette.hidden = YES;
    [host addSubview:self.drawingTextPalette];
    NSArray *textOptions = self.customDrawingTexts ?: [self defaultDrawingTextOptions];
    for (NSUInteger i = 0; i < textOptions.count; i++) {
        NSString *value = textOptions[i];
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.frame = CGRectMake(6, 6 + (CGFloat)i * 36.0, 118, 32);
        [button setTitle:value forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        button.titleLabel.adjustsFontSizeToFitWidth = YES;
        button.backgroundColor = [UIColor colorWithWhite:1 alpha:.12];
        button.layer.cornerRadius = 6;
        button.accessibilityLabel = [NSString stringWithFormat:@"文字 %@", value];
        button.accessibilityIdentifier = value;
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [button addTarget:self action:@selector(selectDrawingTextButton:) forControlEvents:UIControlEventTouchUpInside];
        [self.drawingTextPalette addSubview:button];
    }
}
- (void)clearDrawingCategory:(id)sender {
    NSString *category = self.drawingCategory ?: @"汎用";
    NSIndexSet *indexes = [self.drawingAnnotations indexesOfObjectsPassingTest:^BOOL(NSDictionary *obj, NSUInteger idx, BOOL *stop) { return [obj[@"category"] isEqualToString:category]; }];
    [self.drawingAnnotations removeObjectsAtIndexes:indexes];
    self.drawingCanvas.annotations = self.drawingAnnotations;
    [self saveDrawingAnnotations];
}
- (void)undoDrawing:(id)sender {
    if (!self.drawingMode || self.drawingAnnotations.count <= self.drawingModeInitialAnnotationCount) return;
    [self.drawingAnnotations removeLastObject];
    self.activeDrawingAnnotation = nil;
    self.drawingCanvas.annotations = self.drawingAnnotations;
    [self updateRotationHandlePosition];
    [self saveDrawingAnnotations];
}
- (void)refreshDrawingPaletteState {
    // パレットで選択した描画種別を実際の入力キャンバスへ同期する。
    self.drawingCanvas.tool = self.drawingTool ?: @"直線";
    self.drawingTextPalette.hidden = !(self.drawingMode && [self.drawingTool isEqualToString:@"文字"]);
    BOOL textMenuVisible = self.drawingMode && [self.drawingTool isEqualToString:@"文字"];
    self.shareButton.hidden = textMenuVisible;
    self.exportButton.hidden = textMenuVisible;
    self.drawingCanvas.drawingText = self.drawingText ?: @"";
    self.drawingCanvas.foregroundColor = self.drawingForegroundColor ?: UIColor.greenColor;
    self.drawingCanvas.backgroundColorForDrawing = self.drawingBackgroundColor ?: UIColor.clearColor;
    BOOL shape = [self.drawingTool isEqualToString:@"楕円"] || [self.drawingTool isEqualToString:@"四角"] || [self.drawingTool isEqualToString:@"三角"];
    BOOL axis = [self.drawingTool isEqualToString:@"軸1"] || [self.drawingTool isEqualToString:@"軸2"] || [self.drawingTool isEqualToString:@"軸3D"];
    BOOL text = [self.drawingTool isEqualToString:@"文字"];
    BOOL lineOnlyCategory = [self.drawingCategory isEqualToString:@"基準"] || [self.drawingCategory isEqualToString:@"対象"];
    NSArray *titles = @[@"カテゴリ", @"描画種別", @"色", @"文字", @"線種"];
    NSArray *values = @[self.drawingCategory ?: @"汎用", [self drawingToolDisplayName:self.drawingTool ?: @"直線"], [self colorNameForColor:self.drawingForegroundColor], self.drawingText.length ? self.drawingText : @"未選択", self.drawingLineStyle ?: @"実線"];
    for (UIView *view in self.drawingPalette.subviews) if ([view isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)view;
        if (button.tag >= 1 && button.tag <= 5) {
            NSInteger index = button.tag - 1;
            NSString *title = titles[index], *value = values[index];
            if (index == 3) {
                [button setImage:[UIImage systemImageNamed:@"textformat"] forState:UIControlStateNormal];
                [button setAttributedTitle:nil forState:UIControlStateNormal];
                button.tintColor = UIColor.whiteColor;
                button.accessibilityLabel = @"文字メニュー";
            } else {
                NSArray *symbols = @[@"square.grid.2x2", @"pencil.tip", @"paintpalette", @"textformat", @"line.3.horizontal"];
                [button setImage:[UIImage systemImageNamed:symbols[index]] forState:UIControlStateNormal];
                [button setTitle:nil forState:UIControlStateNormal];
                button.accessibilityLabel = [NSString stringWithFormat:@"%@メニュー（現在 %@）", title, value];
                if (index == 2) button.tintColor = self.drawingForegroundColor ?: UIColor.greenColor;
            }
        }
        if (button.tag == 2) { button.enabled = !lineOnlyCategory; button.alpha = lineOnlyCategory ? .35 : 1.0; }
        if (button.tag == 3) { button.enabled = !axis; button.alpha = axis ? .35 : 1.0; }
        if (button.tag == 4) { button.enabled = text; button.alpha = text ? 1.0 : .35; }
    }
}

- (NSURL *)drawingMetadataURL {
    NSURL *videoURL = [(AVURLAsset *)self.player.currentItem.asset URL];
    return videoURL ? [videoURL URLByAppendingPathExtension:@"drawing.json"] : nil;
}
- (void)loadDrawingAnnotations {
    [self.drawingAnnotations removeAllObjects];
    self.activeDrawingAnnotation = nil;
    self.rotationHandle.hidden = YES;
    self.resizeHandle.hidden = YES;
    NSURL *url = [self drawingMetadataURL];
    NSData *data = url ? [NSData dataWithContentsOfURL:url] : nil;
    NSArray *items = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if ([items isKindOfClass:NSArray.class]) for (NSDictionary *item in items) if ([item isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *copy = [item mutableCopy];
        NSString *category = copy[@"category"];
        if ([copy[@"tool"] isEqualToString:@"線"]) copy[@"tool"] = @"直線";
        if ([category isEqualToString:@"踏切"]) copy[@"category"] = @"基準";
        else if ([category isEqualToString:@"人"]) copy[@"category"] = @"対象";
        else if ([category isEqualToString:@"その他"] || !category.length) copy[@"category"] = @"汎用";
        [self.drawingAnnotations addObject:copy];
    }
    self.drawingCanvas.hidden = self.drawingAnnotations.count == 0;
    self.drawingCanvas.annotations = self.drawingAnnotations;
    self.drawingCanvas.currentTime = self.player.currentTime;
}
- (void)saveDrawingAnnotations {
    NSURL *url = [self drawingMetadataURL];
    if (!url) return;
    NSData *data = [NSJSONSerialization dataWithJSONObject:self.drawingAnnotations options:NSJSONWritingPrettyPrinted error:nil];
    if (data) [data writeToURL:url options:NSDataWritingAtomic error:nil];
}
- (void)updateDrawingCanvasForTime:(CMTime)time {
    if (!self.drawingCanvas) return;
    self.drawingCanvas.currentTime = time;
    self.drawingCanvas.annotations = self.drawingAnnotations;
}
- (void)toggleDrawingMode:(id)sender {
    if (self.player.rate > 0) return;
    self.drawingMode = !self.drawingMode;
    if (self.drawingMode) {
        self.drawingModeInitialAnnotationCount = self.drawingAnnotations.count;
        self.drawingModeStartTime = self.player.currentTime;
        self.playlistPanGesture.enabled = NO;
        self.playlistOverlayPanGesture.enabled = NO;
        self.drawingCanvas.frame = self.speedControlHost.bounds;
        self.drawingCanvas.userInteractionEnabled = YES;
        [self.speedControlHost bringSubviewToFront:self.drawingCanvas];
        [self.speedControlHost bringSubviewToFront:self.drawingPalette];
        [self.speedControlHost bringSubviewToFront:self.drawingTextPalette];
        [self.speedControlHost bringSubviewToFront:self.drawingButton];
        [self.speedControlHost bringSubviewToFront:self.rotationHandle];
        [self.speedControlHost bringSubviewToFront:self.resizeHandle];
        self.drawingCanvas.drawingEnabled = YES;
        self.drawingCanvas.hidden = NO;
        self.drawingPalette.hidden = NO;
        self.deleteButton.hidden = YES;
        self.favoriteButton.hidden = YES;
        self.infoButton.hidden = YES;
        self.closeButton.hidden = YES;
        [self.drawingButton setImage:[UIImage systemImageNamed:@"pencil.circle.fill"] forState:UIControlStateNormal];
        [self.speedHideTimer invalidate];
    } else {
        double end = CMTimeGetSeconds(self.player.currentTime);
        for (NSMutableDictionary *item in self.drawingAnnotations) if (item[@"end"] == [NSNull null]) item[@"end"] = @(end);
        [self saveDrawingAnnotations];
        self.drawingCanvas.drawingEnabled = NO;
        self.drawingCanvas.userInteractionEnabled = NO;
        self.drawingPalette.hidden = YES;
        self.deleteButton.hidden = NO;
        self.favoriteButton.hidden = NO;
        self.infoButton.hidden = NO;
        self.closeButton.hidden = NO;
        self.playlistPanGesture.enabled = YES;
        self.playlistOverlayPanGesture.enabled = YES;
        [self.drawingButton setImage:[UIImage systemImageNamed:@"pencil"] forState:UIControlStateNormal];
        [self showSpeedControls];
    }
    self.drawingCanvas.currentTime = self.player.currentTime;
    self.drawingCanvas.annotations = self.drawingAnnotations;
    [self refreshDrawingPaletteState];
}
- (void)moveDrawingPalette:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.drawingPalette.superview];
    CGPoint center = self.drawingPalette.center;
    center.x += translation.x; center.y += translation.y;
    CGFloat half = self.drawingPalette.bounds.size.width / 2.0;
    center.x = MAX(half + 4, MIN(self.drawingPalette.superview.bounds.size.width - half - 4, center.x));
    center.y = MAX(self.drawingPalette.bounds.size.height / 2 + 8, MIN(self.drawingPalette.superview.bounds.size.height - self.drawingPalette.bounds.size.height / 2 - 8, center.y));
    self.drawingPalette.center = center;
    [gesture setTranslation:CGPointZero inView:self.drawingPalette.superview];
}
- (NSDictionary *)colorComponents:(UIColor *)color background:(BOOL)background {
    CGFloat r=0,g=0,b=0,a=1; [color getRed:&r green:&g blue:&b alpha:&a];
    return background ? @{ @"br": @(r), @"bg": @(g), @"bb": @(b), @"ba": @(a) } : @{ @"r": @(r), @"g": @(g), @"b": @(b), @"a": @(a) };
}
- (void)commitDrawingPoints:(NSArray<NSValue *> *)points {
    if (!self.drawingMode || points.count == 0) return;
    NSString *tool = self.drawingTool ?: @"直線";
    if ([self.drawingCategory isEqualToString:@"基準"]) {
        tool = @"直線";
        NSIndexSet *old = [self.drawingAnnotations indexesOfObjectsPassingTest:^BOOL(NSDictionary *obj, NSUInteger idx, BOOL *stop) { return [obj[@"category"] isEqualToString:@"基準"]; }];
        [self.drawingAnnotations removeObjectsAtIndexes:old];
    }
    NSMutableArray *normalized = [NSMutableArray array];
    for (NSValue *value in points) {
        CGPoint p = value.CGPointValue;
        [normalized addObject:@[@(MAX(0, MIN(1, p.x / MAX(self.drawingCanvas.bounds.size.width, 1)))), @(MAX(0, MIN(1, p.y / MAX(self.drawingCanvas.bounds.size.height, 1))))]];
    }
    if ([tool isEqualToString:@"軌道"]) {
        NSIndexSet *oldTrajectory = [self.drawingAnnotations indexesOfObjectsPassingTest:^BOOL(NSDictionary *obj, NSUInteger idx, BOOL *stop) {
            return [obj[@"tool"] isEqualToString:@"軌道"] && [obj[@"start"] doubleValue] == CMTimeGetSeconds(self.drawingModeStartTime);
        }];
        [self.drawingAnnotations removeObjectsAtIndexes:oldTrajectory];
    }
    double startTime = CMTimeGetSeconds(self.drawingModeStartTime); if (!isfinite(startTime)) startTime = 0;
    NSMutableDictionary *item = [@{ @"tool": tool, @"category": self.drawingCategory ?: @"汎用", @"style": self.drawingLineStyle ?: @"実線", @"points": normalized, @"start": @(startTime), @"end": [NSNull null], @"width": @3.0, @"text": self.drawingText ?: @"" } mutableCopy];
    [item addEntriesFromDictionary:[self colorComponents:self.drawingForegroundColor background:NO]];
    [item addEntriesFromDictionary:[self colorComponents:self.drawingBackgroundColor background:YES]];
    if ([self.drawingCategory isEqualToString:@"基準"] && normalized.count >= 2) {
        NSArray *p0=normalized.firstObject, *p1=normalized.lastObject;
        CGFloat dx=fabs([p1[0] doubleValue]-[p0[0] doubleValue]);
        CGFloat dy=fabs([p1[1] doubleValue]-[p0[1] doubleValue]);
        CGFloat diagonalAngle = atan2(dy, dx) * 180.0 / M_PI;
        // 対角線で分割された矩形の「下側」の三角形について、終了点の直角ではない内角を求める。
        // 矩形の底辺方向と対角線の内角。開始点・終了点の上下関係では切り替えない。
        CGFloat angle = diagonalAngle;
        angle = MAX(0.0, MIN(180.0, angle));
        item[@"angle"] = @(angle);
    }
    [self.drawingAnnotations addObject:item];
    [self updatePersonAnglesForCurrentRamp];
    if ([tool isEqualToString:@"楕円"] || [tool isEqualToString:@"四角"] || [tool isEqualToString:@"三角"] || [tool isEqualToString:@"x"]) self.activeDrawingAnnotation = item;
    self.drawingCanvas.hidden = NO;
    self.drawingCanvas.annotations = self.drawingAnnotations;
    [self updateRotationHandlePosition];
    [self saveDrawingAnnotations];
}
- (void)updatePersonAnglesForCurrentRamp {
    NSDictionary *ramp = nil;
    for (NSDictionary *item in self.drawingAnnotations) if ([item[@"category"] isEqualToString:@"基準"]) { ramp = item; break; }
    if (!ramp) return;
    NSArray *rampPoints = ramp[@"points"]; if (rampPoints.count < 2) return;
    NSArray *r0 = rampPoints.firstObject, *r1 = rampPoints.lastObject;
    CGFloat rx = [r1[0] doubleValue] - [r0[0] doubleValue], ry = [r1[1] doubleValue] - [r0[1] doubleValue];
    CGFloat rampLength = hypot(rx, ry);
    for (NSMutableDictionary *item in self.drawingAnnotations) if ([item[@"category"] isEqualToString:@"対象"] && [item[@"tool"] isEqualToString:@"直線"]) {
        NSArray *points = item[@"points"]; if (points.count < 2) continue;
        NSArray *p0 = points.firstObject, *p1 = points.lastObject;
        CGFloat tx = [p1[0] doubleValue]-[p0[0] doubleValue], ty = [p1[1] doubleValue]-[p0[1] doubleValue];
        CGFloat targetLength = hypot(tx, ty);
        if (rampLength > 0.0001 && targetLength > 0.0001) {
            CGFloat cosine = fabs((rx * tx + ry * ty) / (rampLength * targetLength));
            cosine = MAX(0.0, MIN(1.0, cosine));
            item[@"angle"] = @(acos(cosine) * 180.0 / M_PI);
        }
    }
}
- (void)updateRotationHandlePosition {
    if (!self.activeDrawingAnnotation || !self.rotationHandle || self.drawingCanvas.hidden) { self.rotationHandle.hidden = YES; self.resizeHandle.hidden = YES; return; }
    NSArray *points = self.activeDrawingAnnotation[@"points"]; if (points.count < 2) { self.rotationHandle.hidden = YES; return; }
    NSArray *last = points.lastObject;
    CGFloat x = [last[0] doubleValue] * self.drawingCanvas.bounds.size.width;
    CGFloat y = [last[1] doubleValue] * self.drawingCanvas.bounds.size.height;
    self.rotationHandle.frame = CGRectMake(x - 18, y - 18, 36, 36);
    self.resizeHandle.frame = CGRectMake(x + 20, y - 18, 36, 36);
    self.rotationHandle.hidden = NO;
    self.resizeHandle.hidden = NO;
}
- (void)rotationHandleTapped:(id)sender { }
- (void)rotateDrawing:(UIPanGestureRecognizer *)gesture {
    if (!self.activeDrawingAnnotation) return;
    CGPoint point = [gesture locationInView:self.drawingCanvas];
    NSArray *points = self.activeDrawingAnnotation[@"points"]; if (points.count < 2) return;
    NSArray *first = points.firstObject, *last = points.lastObject;
    CGPoint center = [self.activeDrawingAnnotation[@"tool"] isEqualToString:@"x"] ? CGPointMake([first[0] doubleValue] * self.drawingCanvas.bounds.size.width, [first[1] doubleValue] * self.drawingCanvas.bounds.size.height) : CGPointMake(([first[0] doubleValue]+[last[0] doubleValue]) * .5 * self.drawingCanvas.bounds.size.width, ([first[1] doubleValue]+[last[1] doubleValue]) * .5 * self.drawingCanvas.bounds.size.height);
    CGFloat angle = atan2(point.y-center.y, point.x-center.x);
    self.activeDrawingAnnotation[@"rotation"] = @(angle);
    self.drawingCanvas.annotations = self.drawingAnnotations;
    [self saveDrawingAnnotations];
}
- (void)resizeHandleTapped:(id)sender { }
- (void)resizeDrawing:(UIPanGestureRecognizer *)gesture {
    if (!self.activeDrawingAnnotation) return;
    CGPoint point = [gesture locationInView:self.drawingCanvas];
    NSArray *points = self.activeDrawingAnnotation[@"points"]; if (points.count < 2) return;
    NSMutableArray *updated = [NSMutableArray arrayWithArray:points];
    updated[updated.count - 1] = @[@(MAX(0, MIN(1, point.x / MAX(self.drawingCanvas.bounds.size.width, 1)))), @(MAX(0, MIN(1, point.y / MAX(self.drawingCanvas.bounds.size.height, 1))))];
    self.activeDrawingAnnotation[@"points"] = updated;
    self.drawingCanvas.annotations = self.drawingAnnotations;
    [self updateRotationHandlePosition];
    [self saveDrawingAnnotations];
}
- (void)drawingTextTappedAtPoint:(CGPoint)point {
    if (!self.drawingMode || !self.drawingText.length) return;
    [self commitDrawingPoints:@[[NSValue valueWithCGPoint:point]]];
}
- (void)showDrawingMenu:(NSArray<NSString *> *)items title:(NSString *)title handler:(void (^)(NSString *value))handler {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *item in items) [alert addAction:[UIAlertAction actionWithTitle:item style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ handler(item); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    if (alert.popoverPresentationController) { alert.popoverPresentationController.sourceView = self.drawingPalette; alert.popoverPresentationController.sourceRect = self.drawingPalette.bounds; }
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)showDrawingOptions:(NSArray<NSDictionary *> *)options title:(NSString *)title handler:(void (^)(NSString *value))handler {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *option in options) {
        UIAlertAction *action = [UIAlertAction actionWithTitle:option[@"display"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ handler(option[@"value"]); }];
        [alert addAction:action];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    if (alert.popoverPresentationController) { alert.popoverPresentationController.sourceView = self.drawingPalette; alert.popoverPresentationController.sourceRect = self.drawingPalette.bounds; }
    [self presentViewController:alert animated:YES completion:nil];
}
- (NSDictionary *)drawingOption:(NSString *)value display:(NSString *)display selected:(NSString *)selected {
    return @{@"value": value, @"display": [NSString stringWithFormat:@"%@%@", display, [value isEqualToString:selected] ? @"    ✓" : @""]};
}
- (NSDictionary *)drawingOption:(NSString *)value display:(NSString *)display selected:(NSString *)selected image:(UIImage *)image {
    NSMutableDictionary *option = [[self drawingOption:value display:display selected:selected] mutableCopy]; if (image) option[@"image"] = image; return option;
}
- (UIImage *)drawingToolIcon:(NSString *)tool color:(UIColor *)color {
    CGSize size = CGSizeMake(34, 22); UIGraphicsBeginImageContextWithOptions(size, NO, 0); CGContextRef ctx = UIGraphicsGetCurrentContext(); CGContextSetStrokeColorWithColor(ctx, (color ?: UIColor.whiteColor).CGColor); CGContextSetFillColorWithColor(ctx, (color ?: UIColor.whiteColor).CGColor); CGContextSetLineWidth(ctx, 4);
    if ([tool isEqualToString:@"直線"]) { CGContextMoveToPoint(ctx, 3, 11); CGContextAddLineToPoint(ctx, 31, 11); CGContextStrokePath(ctx); }
    else if ([tool isEqualToString:@"矢印"]) { CGContextMoveToPoint(ctx, 3, 11); CGContextAddLineToPoint(ctx, 27, 11); CGContextStrokePath(ctx); CGContextMoveToPoint(ctx, 27, 11); CGContextAddLineToPoint(ctx, 20, 5); CGContextMoveToPoint(ctx, 27, 11); CGContextAddLineToPoint(ctx, 20, 17); CGContextStrokePath(ctx); }
    else if ([tool isEqualToString:@"丸"] || [tool isEqualToString:@"軸1"] || [tool isEqualToString:@"軸2"] || [tool isEqualToString:@"軸3D"]) CGContextFillEllipseInRect(ctx, CGRectMake(7, 1, 20, 20));
    else if ([tool isEqualToString:@"楕円"]) CGContextFillEllipseInRect(ctx, CGRectMake(2, 4, 30, 14));
    else if ([tool isEqualToString:@"四角"]) CGContextFillRect(ctx, CGRectMake(5, 3, 24, 16));
    else if ([tool isEqualToString:@"三角"]) { CGContextMoveToPoint(ctx, 17, 2); CGContextAddLineToPoint(ctx, 31, 20); CGContextAddLineToPoint(ctx, 3, 20); CGContextClosePath(ctx); CGContextFillPath(ctx); }
    else if ([tool isEqualToString:@"x"]) { CGContextMoveToPoint(ctx, 3, 11); CGContextAddLineToPoint(ctx, 31, 11); CGContextMoveToPoint(ctx, 17, 2); CGContextAddLineToPoint(ctx, 17, 20); CGContextStrokePath(ctx); }
    else if ([tool isEqualToString:@"角度"]) { CGContextMoveToPoint(ctx, 4, 18); CGContextAddLineToPoint(ctx, 16, 5); CGContextAddLineToPoint(ctx, 30, 18); CGContextStrokePath(ctx); }
    else if ([tool isEqualToString:@"軌道"]) { CGContextMoveToPoint(ctx, 3, 17); CGContextAddLineToPoint(ctx, 12, 12); CGContextAddLineToPoint(ctx, 20, 15); CGContextAddLineToPoint(ctx, 31, 5); CGContextStrokePath(ctx); CGContextFillEllipseInRect(ctx, CGRectMake(1, 15, 4, 4)); CGContextFillEllipseInRect(ctx, CGRectMake(29, 3, 4, 4)); }
    else if ([tool isEqualToString:@"フリー"]) { CGContextMoveToPoint(ctx, 3, 15); CGContextAddCurveToPoint(ctx, 8, 2, 14, 21, 20, 10); CGContextAddCurveToPoint(ctx, 24, 3, 28, 17, 31, 7); CGContextStrokePath(ctx); }
    else { CGContextFillRect(ctx, CGRectMake(13, 2, 8, 18)); }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return image;
}
- (NSString *)drawingToolGlyph:(NSString *)tool {
    NSDictionary *glyphs=@{@"文字":@"𝑇", @"直線":@"━━━━", @"矢印":@"━━▶", @"丸":@"●", @"軸1":@"◉¹", @"軸2":@"◉²", @"軸3D":@"◉³ᴰ", @"楕円":@"⬭", @"四角":@"■", @"三角":@"▲", @"x":@"✕", @"角度":@"∠", @"軌道":@"⌁", @"フリー":@"〰"};
    return glyphs[tool] ?: @"";
}
- (NSString *)drawingToolDisplayName:(NSString *)tool {
    NSDictionary *names=@{@"軸1":@"軸U", @"軸2":@"軸Flip", @"x":@"十字"};
    return names[tool] ?: tool;
}
- (UIImage *)drawingColorIcon:(UIColor *)color { CGSize size=CGSizeMake(24,24); UIGraphicsBeginImageContextWithOptions(size,NO,0); CGContextRef ctx=UIGraphicsGetCurrentContext(); CGContextSetFillColorWithColor(ctx,color.CGColor); CGContextFillEllipseInRect(ctx,CGRectMake(3,3,18,18)); UIImage *image=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return image; }
- (UIImage *)drawingLineStyleIcon:(NSString *)style { CGSize size=CGSizeMake(72,24); UIGraphicsBeginImageContextWithOptions(size,NO,0); CGContextRef ctx=UIGraphicsGetCurrentContext(); CGContextSetStrokeColorWithColor(ctx,UIColor.labelColor.CGColor); CGContextSetLineWidth(ctx,4.0); CGContextSetLineCap(ctx,kCGLineCapRound); if ([style isEqualToString:@"点線"]) { CGFloat p[]={1.5,7}; CGContextSetLineDash(ctx,0,p,2); } else if ([style isEqualToString:@"鎖線"]) { CGFloat p[]={12,7}; CGContextSetLineDash(ctx,0,p,2); } CGContextMoveToPoint(ctx,3,12); CGContextAddLineToPoint(ctx,69,12); CGContextStrokePath(ctx); UIImage *image=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return image; }
- (void)drawingToolMenu:(id)sender { NSArray *values=@[@"文字",@"直線",@"矢印",@"丸",@"軸1",@"軸2",@"軸3D",@"楕円",@"四角",@"三角",@"x",@"角度",@"軌道",@"フリー"]; NSMutableArray *options=[NSMutableArray array]; for (NSString *v in values) { NSString *display=[NSString stringWithFormat:@"%@    %@", [self drawingToolGlyph:v], [self drawingToolDisplayName:v]]; NSMutableDictionary *option=[[self drawingOption:v display:display selected:self.drawingTool] mutableCopy]; option[@"image"]=[self drawingToolIcon:v color:UIColor.labelColor]; [options addObject:option]; } [self showDrawingOptions:options title:@"描画種別" handler:^(NSString *v){ self.drawingTool=v; [self refreshDrawingPaletteState]; }]; }
- (void)drawingCategoryMenu:(id)sender { NSArray *values=@[@"汎用",@"基準",@"対象"]; NSMutableArray *options=[NSMutableArray array]; for (NSString *v in values) [options addObject:[self drawingOption:v display:v selected:self.drawingCategory]]; [self showDrawingOptions:options title:@"カテゴリ" handler:^(NSString *v){ self.drawingCategory=v; if ([v isEqualToString:@"基準"] || [v isEqualToString:@"対象"]) self.drawingTool=@"直線"; if ([v isEqualToString:@"基準"]) self.drawingLineStyle=@"点線"; [self refreshDrawingPaletteState]; }]; }
- (void)drawingLineStyleMenu:(id)sender { NSArray *values=@[@"実線",@"点線",@"鎖線"]; NSArray *samples=@[@"━━━━━━  実線",@"• • • • •  点線",@"━━  ━━  ━━  鎖線"]; NSMutableArray *options=[NSMutableArray array]; for (NSInteger i=0;i<values.count;i++) [options addObject:[self drawingOption:values[i] display:samples[i] selected:self.drawingLineStyle]]; [self showDrawingOptions:options title:@"線種" handler:^(NSString *v){ self.drawingLineStyle=v; [self refreshDrawingPaletteState]; }]; }
- (UIColor *)colorForName:(NSString *)name { NSDictionary *colors=@{@"緑":UIColor.greenColor,@"黄":UIColor.yellowColor,@"オレンジ":UIColor.orangeColor,@"ピンク":UIColor.systemPinkColor,@"明るい紫":UIColor.systemPurpleColor,@"赤":UIColor.redColor,@"青":UIColor.blueColor,@"白":UIColor.whiteColor}; return colors[name] ?: UIColor.greenColor; }
- (NSString *)colorNameForColor:(UIColor *)color { if (!color) return @"なし"; CGFloat r=0,g=0,b=0,a=1; [color getRed:&r green:&g blue:&b alpha:&a]; if (a <= 0.01) return @"なし"; NSDictionary *colors=@{@"黄":UIColor.yellowColor,@"緑":UIColor.greenColor,@"オレンジ":UIColor.orangeColor,@"ピンク":UIColor.systemPinkColor,@"明るい紫":UIColor.systemPurpleColor,@"赤":UIColor.redColor,@"青":UIColor.blueColor,@"白":UIColor.whiteColor}; for (NSString *name in colors) if ([color isEqual:colors[name]]) return name; return @"その他"; }
- (void)drawingColorMenu:(BOOL)background {
    NSArray *values=@[@"緑",@"黄",@"オレンジ",@"ピンク",@"明るい紫",@"赤",@"青",@"白",@"その他"];
    // UIAlertAction のタイトル内で個別に文字色を指定できないため、
    // 色が視認できる丸記号を先頭に置く（色名も併記してアクセシビリティを確保）。
    NSArray *icons=@[@"🟢  緑",@"🟡  黄",@"🟠  オレンジ",@"🩷  ピンク",@"🟣  明るい紫",@"🔴  赤",@"🔵  青",@"⚪  白",@"＋  その他"];
    NSArray *iconColors=@[UIColor.greenColor, UIColor.yellowColor, UIColor.orangeColor, [UIColor colorWithRed:1 green:.35 blue:.65 alpha:1], UIColor.systemPurpleColor, UIColor.redColor, UIColor.blueColor, UIColor.whiteColor, UIColor.lightGrayColor];
    UIColor *selectedColor = background ? self.drawingBackgroundColor : self.drawingForegroundColor;
    NSString *selected = [self colorNameForColor:selectedColor];
    NSMutableArray *options=[NSMutableArray array]; for (NSInteger i=0;i<values.count;i++) [options addObject:[self drawingOption:values[i] display:icons[i] selected:selected image:[self drawingColorIcon:iconColors[i]]]];
    [self showDrawingOptions:options title:@"色" handler:^(NSString *v){ if ([v isEqualToString:@"その他"]) { [self showColorPickerForBackground:background]; return; } if (background) self.drawingBackgroundColor=[self colorForName:v]; else self.drawingForegroundColor=[self colorForName:v]; [self refreshDrawingPaletteState]; }];
}
- (void)showColorPickerForBackground:(BOOL)background {
    self.drawingColorPickerForBackground = background;
    self.drawingColorPicker = [UIColorPickerViewController new];
    self.drawingColorPicker.delegate = self;
    self.drawingColorPicker.supportsAlpha = YES;
    self.drawingColorPicker.selectedColor = background ? self.drawingBackgroundColor : self.drawingForegroundColor;
    [self presentViewController:self.drawingColorPicker animated:YES completion:nil];
}
- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)viewController {
    if (self.drawingColorPickerForBackground) self.drawingBackgroundColor = viewController.selectedColor;
    else self.drawingForegroundColor = viewController.selectedColor;
    [self refreshDrawingPaletteState];
}
- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController {
    [self refreshDrawingPaletteState];
}
- (void)drawingForegroundMenu:(id)sender { [self drawingColorMenu:NO]; }
- (void)drawingBackgroundMenu:(id)sender { if (!([self.drawingTool isEqualToString:@"楕円"] || [self.drawingTool isEqualToString:@"四角"] || [self.drawingTool isEqualToString:@"三角"])) return; [self drawingColorMenu:YES]; }
- (NSURL *)drawingTextOptionsURL {
    NSURL *documents = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];
    return [documents URLByAppendingPathComponent:@"MTJudgeDrawingTexts.json"];
}
- (NSArray<NSString *> *)defaultDrawingTextOptions {
    return @[@"締める", @"伸ばす", @"見る", @"強く", @"上", @"前", @"下", @"後", @"👍", @"👎", @"⌨"];
}
- (void)loadDrawingTextOptions {
    NSArray *loaded = nil;
    NSData *data = [NSData dataWithContentsOfURL:[self drawingTextOptionsURL]];
    if (data.length) loaded = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![loaded isKindOfClass:NSArray.class]) {
        loaded = [[NSUserDefaults standardUserDefaults] arrayForKey:@"WJCustomDrawingTexts"];
    }
    // 代表文字は仕様で定めた順番を常に先頭へ固定する。旧JSONの配列順は採用しない。
    NSArray *defaults = [self defaultDrawingTextOptions];
    NSMutableArray *options = [NSMutableArray arrayWithArray:defaults];
    NSArray *removedLegacy = @[@"気合いだ！", @"気合いだ!", @"上に", @"前に", @"下に", @"後に"];
    for (id value in loaded) if ([value isKindOfClass:NSString.class] && [value length] > 0 && [value length] <= 16 && ![options containsObject:value] && ![removedLegacy containsObject:value]) [options addObject:value];
    self.customDrawingTexts = options;
    [self saveDrawingTextOptions];
}
- (void)saveDrawingTextOptions {
    if (!self.customDrawingTexts) return;
    NSData *data = [NSJSONSerialization dataWithJSONObject:self.customDrawingTexts options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToURL:[self drawingTextOptionsURL] options:NSDataWritingAtomic error:nil];
    [[NSUserDefaults standardUserDefaults] setObject:self.customDrawingTexts forKey:@"WJCustomDrawingTexts"];
}
- (void)selectDrawingTextButton:(UIButton *)sender {
    if (![self.drawingTool isEqualToString:@"文字"]) return;
    NSString *value = sender.accessibilityIdentifier ?: sender.currentTitle;
    if ([value isEqualToString:@"⌨"]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"文字入力" message:@"16文字以内で入力してください" preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = @"入力文字"; field.clearButtonMode = UITextFieldViewModeWhileEditing; }];
        [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"登録" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *text = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (text.length > 0 && text.length <= 16) {
                if (!self.customDrawingTexts) self.customDrawingTexts = [NSMutableArray array];
                if (![self.customDrawingTexts containsObject:text]) [self.customDrawingTexts addObject:text];
                [self saveDrawingTextOptions]; self.drawingText = text;
            }
            [self refreshDrawingPaletteState];
            self.drawingTextPalette.hidden = YES;
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *text = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (text.length > 0 && text.length <= 16) self.drawingText = text;
            [self refreshDrawingPaletteState];
            self.drawingTextPalette.hidden = YES;
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    if (value.length) { self.drawingText = value; [self refreshDrawingPaletteState]; self.drawingTextPalette.hidden = YES; }
}
- (void)drawingTextMenu:(id)sender {
    if (![self.drawingTool isEqualToString:@"文字"]) return;
    self.drawingTextPalette.hidden = NO;
    [self.drawingTextPalette.superview bringSubviewToFront:self.drawingTextPalette];
    return;
}


- (UIButton *)featureButtonWithSymbol:(NSString *)symbol action:(SEL)action label:(NSString *)label {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tintColor = UIColor.whiteColor;
    button.accessibilityLabel = label;
    button.backgroundColor = [UIColor colorWithWhite:0 alpha:0.25];
    button.layer.cornerRadius = 7;
    [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button.widthAnchor constraintEqualToConstant:38].active = YES;
    [button.heightAnchor constraintEqualToConstant:36].active = YES;
    return button;
}

- (void)replaceVideoURL:(NSURL *)url {
    if (!url || ![[NSFileManager defaultManager] fileExistsAtPath:url.path]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
        self.wjSelectedSpeed = 1.0f;
        self.loopStartTime = kCMTimeInvalid;
        self.loopEndTime = kCMTimeInvalid;
        self.loopEnabled = NO;
        self.loopSeekInProgress = NO;
        self.automaticLoopLimit = 0;
        self.automaticLoopCount = 0;
        self.automaticLoopDeadline = nil;
        self.skeletonVisible = NO;
        self.skeletonOverlayLayer.hidden = YES;
        self.drawingMode = NO;
        self.drawingCanvas.drawingEnabled = NO;
        self.drawingPalette.hidden = YES;
        self.drawingButton.hidden = YES;
        self.takeoffButton.enabled = NO;
        self.takeoffButton.alpha = .4;
        [self.player replaceCurrentItemWithPlayerItem:item];
        self.mirroredPlayback = NO;
        self.skeletonVisible = NO;
        self.skeletonOverlayLayer.hidden = YES;
        [self applyMirrorToPlayerLayers];
        [self updateSpeedSlider];
        [self refreshFeatureButtons];
        [self loadDrawingAnnotations];
        [self resetAndPlay];
        [self loadAnalysisForCurrentVideo];
        [self refreshFavoriteState];
    });
}

- (void)refreshFavoriteState {
    NSURL *url = [(AVURLAsset *)self.player.currentItem.asset URL];
    self.favorite = url && [[[NSUserDefaults standardUserDefaults] arrayForKey:@"WJFavoriteVideoPaths"] containsObject:url.path];
    [self.favoriteButton setImage:[UIImage systemImageNamed:(self.favorite ? @"heart.fill" : @"heart")] forState:UIControlStateNormal];
    self.favoriteButton.tintColor = self.favorite ? UIColor.systemPinkColor : UIColor.whiteColor;
    self.favoriteIndicator.hidden = !self.favorite;
}

- (void)setPlaylist:(NSArray<NSURL *> *)playlist currentIndex:(NSInteger)index {
    self.playlist = [playlist copy];
    self.playlistIndex = MAX(0, MIN(index, (NSInteger)self.playlist.count - 1));
}

- (void)handlePlaylistPan:(UIPanGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded || self.switchingPlaylist || self.playlist.count < 2) return;
    CGPoint translation = [gesture translationInView:gesture.view];
    if (fabs(translation.x) < 60.0 || fabs(translation.x) < fabs(translation.y) * 1.15) return;
    NSInteger next = self.playlistIndex + (translation.x < 0 ? 1 : -1);
    if (next < 0 || next >= (NSInteger)self.playlist.count) return;
    NSURL *url = self.playlist[next];
    if (![[NSFileManager defaultManager] fileExistsAtPath:url.path]) return;
    self.switchingPlaylist = YES;
    self.playlistIndex = next;
    [self replaceVideoURL:url];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ self.switchingPlaylist = NO; });
}

- (void)resetAndPlay {
    if (!self.player) return;
    [self configureAutomaticLoop];
    self.player.rate = 0.0f;
    [self.player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (finished && self.player.currentItem.status != AVPlayerItemStatusFailed) {
                self.player.rate = self.wjSelectedSpeed;
            }
        });
    }];
}

- (void)configureAutomaticLoop {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    self.automaticLoopLimit = 0;
    self.automaticLoopCount = 1;
    self.automaticLoopDeadline = nil;
    if (![defaults boolForKey:@"WJLoopPlayback"]) return;
    NSInteger count = [defaults integerForKey:@"WJLoopCount"]; if (count == 0) count = 3;
    if (count > 0) self.automaticLoopLimit = count;
    else if (count < 0) {
        NSInteger seconds = [defaults integerForKey:@"WJLoopDuration"];
        if (seconds > 0) self.automaticLoopDeadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
        self.automaticLoopLimit = -1;
    }
}

- (void)playerTapped:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded) return;
    // コントロール自体のタップは動画の再生状態を変えず、映像面のタップだけを
    // 再生／一時停止として扱う。
    CGPoint tapPoint = [gesture locationInView:self.view];
    UIView *hitView = [self.view hitTest:tapPoint withEvent:nil];
    if (hitView && (self.speedControlContainer && [hitView isDescendantOfView:self.speedControlContainer])) {
        [self showSpeedControls];
        return;
    }
    if (hitView && (self.featureControlContainer && [hitView isDescendantOfView:self.featureControlContainer])) {
        [self showSpeedControls];
        return;
    }
    if (self.takeoffSetupStep > 0 && self.takeoffSetupStep <= 5) {
        CGPoint point = [gesture locationInView:self.view];
        CGFloat width = MAX(self.view.bounds.size.width, 1.0), height = MAX(self.view.bounds.size.height, 1.0);
        CGPoint normalized = CGPointMake(MAX(0, MIN(1, point.x / width)), MAX(0, MIN(1, point.y / height)));
        if (self.takeoffSetupStep == 1) self.takeoffConfig.rampPointA = normalized;
        else if (self.takeoffSetupStep == 2) self.takeoffConfig.rampPointB = normalized;
        else if (self.takeoffSetupStep == 3) self.takeoffConfig.lipPoint = normalized;
        else if (self.takeoffSetupStep == 4) self.takeoffConfig.takeoffStartTime = self.player.currentTime;
        else if (self.takeoffSetupStep == 5) { self.takeoffConfig.lipExitTime = self.player.currentTime; self.takeoffConfig.enabled = YES; [self.takeoffConfig save]; self.takeoffSetupStep = 0; self.takeoffButton.backgroundColor = [UIColor colorWithWhite:0 alpha:.25]; [self updateAnalysisForTime:self.player.currentTime]; }
        if (self.takeoffSetupStep > 0) { self.takeoffSetupStep += 1; self.analysisLabel.hidden = NO; self.analysisLabel.text = [self takeoffSetupInstruction]; }
        [self showSpeedControls];
        return;
    }
    if (self.player.rate > 0.0) {
        [self.player pause];
        [self.playButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal];
        self.drawingButton.hidden = NO;
    }
    [self showSpeedControls];
}

- (NSString *)takeoffSetupInstruction { NSArray *steps = @[@"TAKEOFF設定\n動画上でRamp始点をタップ", @"TAKEOFF設定\n動画上でRamp終点をタップ", @"TAKEOFF設定\n動画上でLip位置をタップ", @"TAKEOFF設定\nサッツ開始フレームでタップ", @"TAKEOFF設定\nリップ離脱フレームでタップ"]; return steps[MAX(0, MIN(self.takeoffSetupStep - 1, (NSInteger)steps.count - 1))]; }
- (void)toggleTakeoffSetup:(id)sender {
    if (!self.skeletonVisible) return;
    if (self.takeoffSetupStep > 0) { self.takeoffSetupStep = 0; self.analysisLabel.hidden = self.analysisFrames.count == 0; self.takeoffButton.backgroundColor = [UIColor colorWithWhite:0 alpha:.25]; return; }
    NSURL *url = [(AVURLAsset *)self.player.currentItem.asset URL];
    self.takeoffConfig = [TakeoffAnalysisConfig configForVideoURL:url];
    self.takeoffSetupStep = 1;
    self.takeoffButton.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:.55];
    self.analysisLabel.hidden = NO; self.analysisLabel.text = [self takeoffSetupInstruction];
    [self showSpeedControls];
}

- (void)toggleStrobe:(id)sender {
    NSURL *url = [(AVURLAsset *)self.player.currentItem.asset URL];
    if (!url) return;
    [self.player pause];
    [self.playButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal];
    __weak typeof(self) weakSelf = self;
    StrobeConfigurationViewController *configuration = [[StrobeConfigurationViewController alloc] initWithVideoURL:url completion:^(NSURL *outputURL) {
        [weakSelf showSpeedControls];
    }];
    [self presentViewController:configuration animated:YES completion:nil];
}

// 通常の動画再生画面から、別の保存動画を選んで比較再生へ進む。
// 現在再生中の動画をMAIN、選択した動画をSUBとして扱う。
- (void)selectComparisonVideo:(id)sender {
    AVAsset *asset = self.player.currentItem.asset;
    NSURL *mainURL = [asset isKindOfClass:[AVURLAsset class]] ? [(AVURLAsset *)asset URL] : nil;
    if (!mainURL) return;
    __weak typeof(self) weakSelf = self;
    UIViewController *library = [WaterJumpSettingsViewController videoLibraryViewControllerForComparisonWithMainURL:mainURL selection:^(NSURL *url) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        WaterJumpComparisonViewController *comparison = [[WaterJumpComparisonViewController alloc] initWithMainURL:mainURL subURL:url];
        [self presentViewController:comparison animated:YES completion:^{ [comparison startPlayback]; }];
    }];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:library];
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)showSpeedControls {
    self.speedControlContainer.hidden = NO;
    self.featureControlContainer.hidden = NO;
    self.playButton.hidden = NO;
    self.frameBackButton.hidden = NO;
    self.frameStepButton.hidden = NO;
    self.favoriteButton.hidden = NO;
    self.infoButton.hidden = NO;
    self.deleteButton.hidden = NO;
    self.drawingButton.hidden = self.player.rate > 0;
    self.timeLabel.hidden = NO;
    [self.speedControlHost bringSubviewToFront:self.speedControlContainer];
    [self.speedControlHost bringSubviewToFront:self.playButton];
    [self.speedControlHost bringSubviewToFront:self.frameBackButton];
    [self.speedControlHost bringSubviewToFront:self.frameStepButton];
    [self.speedControlHost bringSubviewToFront:self.deleteButton];
    [self.speedControlHost bringSubviewToFront:self.shareButton];
    [self.speedControlHost bringSubviewToFront:self.exportButton];
    [self.speedControlHost bringSubviewToFront:self.favoriteButton];
    [self.speedControlHost bringSubviewToFront:self.closeButton];
    [self.speedControlHost bringSubviewToFront:self.infoButton];
    [self.speedControlHost bringSubviewToFront:self.drawingButton];
    [self.speedControlHost bringSubviewToFront:self.compareButton];
    [self.speedControlHost bringSubviewToFront:self.favoriteIndicator];
    // 文字メニュー表示中は、保存・共有などの再生操作より前面に固定する。
    if (self.drawingMode && [self.drawingTool isEqualToString:@"文字"] && !self.drawingTextPalette.hidden) {
        [self.speedControlHost bringSubviewToFront:self.drawingTextPalette];
    }
    [self.speedHideTimer invalidate];
    if (self.drawingMode) return;
    // A点を設定した後は、B点を設定するまで操作列を消さない。
    if (!(CMTIME_IS_VALID(self.loopStartTime) && !CMTIME_IS_VALID(self.loopEndTime))) {
        self.speedHideTimer = [NSTimer scheduledTimerWithTimeInterval:3.0 target:self selector:@selector(hideSpeedControls) userInfo:nil repeats:NO];
    }
}

- (void)hideSpeedControls {
    if (self.drawingMode) return;
    self.speedControlContainer.hidden = YES;
    self.featureControlContainer.hidden = YES;
    self.playButton.hidden = YES;
    self.frameBackButton.hidden = YES;
    self.frameStepButton.hidden = YES;
    self.favoriteButton.hidden = YES;
    self.deleteButton.hidden = YES;
    self.drawingButton.hidden = YES;
    self.infoButton.hidden = YES;
    self.timeLabel.hidden = YES;
    self.drawingPalette.hidden = YES;
}

- (void)speedSliderChanged:(UISlider *)slider {
    [self showSpeedControls];
    self.wjSelectedSpeed = roundf(slider.value * 100.0f) / 100.0f;
    slider.value = self.wjSelectedSpeed;
    self.speedValueLabel.text = [NSString stringWithFormat:@"%.2f×", self.wjSelectedSpeed];
    slider.accessibilityValue = self.speedValueLabel.text;
    AVPlayerItem *item = self.player.currentItem;
    if (!item) return;
    double duration = CMTimeGetSeconds(item.duration);
    double current = CMTimeGetSeconds(self.player.currentTime);
    BOOL atEnd = isfinite(duration) && duration > 0 && isfinite(current) && current >= duration - 0.05;
    if (atEnd) {
        [self.player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
            if (finished) dispatch_async(dispatch_get_main_queue(), ^{ self.player.rate = self.wjSelectedSpeed; });
        }];
    } else {
        // 一時停止中でも速度ボタンを押せば、その速度で再開する。
        self.player.rate = self.wjSelectedSpeed;
    }
}

- (void)updateSpeedSlider {
    self.speedSlider.value = self.wjSelectedSpeed;
    self.speedValueLabel.text = [NSString stringWithFormat:@"%.2f×", self.wjSelectedSpeed];
}

- (void)updatePositionSlider {
    double duration = CMTimeGetSeconds(self.player.currentItem.duration);
    double current = CMTimeGetSeconds(self.player.currentTime);
    if (isfinite(duration) && duration > 0 && isfinite(current) && !self.positionSlider.isTracking) self.positionSlider.value = MIN(1.0, MAX(0.0, current / duration));
    if (isfinite(duration) && duration > 0 && isfinite(current)) self.timeLabel.text = [NSString stringWithFormat:@"%@/%@", [self formattedPlaybackTime:current], [self formattedPlaybackTime:duration]];
}

- (NSString *)formattedPlaybackTime:(double)seconds {
    if (!isfinite(seconds) || seconds < 0) seconds = 0;
    NSInteger minutes = (NSInteger)(seconds / 60.0);
    double remainder = seconds - (minutes * 60.0);
    return [NSString stringWithFormat:@"%02ld:%05.2f", (long)minutes, remainder];
}

- (void)positionSliderChanged:(UISlider *)slider {
    double duration = CMTimeGetSeconds(self.player.currentItem.duration);
    if (!isfinite(duration) || duration <= 0) return;
    // シーク操作中のつまみの揺れを防ぐため、最初のタップ時点で停止する。
    [self.player pause];
    [self.playButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal];
    self.drawingButton.hidden = NO;
    CMTime time = CMTimeMakeWithSeconds(duration * slider.value, 600);
    [self.player seekToTime:time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:nil];
    self.timeLabel.text = [NSString stringWithFormat:@"%@/%@", [self formattedPlaybackTime:duration * slider.value], [self formattedPlaybackTime:duration]];
    [self showSpeedControls];
}

- (void)togglePlay:(id)sender {
    if (self.player.rate > 0) {
        [self.player pause];
        [self.playButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal];
    } else {
        self.player.rate = self.wjSelectedSpeed;
        [self.playButton setImage:[UIImage systemImageNamed:@"pause.fill"] forState:UIControlStateNormal];
    }
    self.drawingButton.hidden = self.player.rate > 0;
    if (self.player.rate > 0) {
        self.drawingCanvas.drawingEnabled = NO;
        self.drawingPalette.hidden = YES;
    }
    [self showSpeedControls];
}

- (void)closePlayer:(id)sender {
    void (^handler)(void) = self.closeHandler;
    self.closeHandler = nil;
    [self dismissViewControllerAnimated:YES completion:handler];
}

- (void)shareCurrentVideo:(id)sender {
    NSURL *url = [(AVURLAsset *)self.player.currentItem.asset URL];
    if (!url) return;
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    if (activity.popoverPresentationController) { activity.popoverPresentationController.sourceView = sender; activity.popoverPresentationController.sourceRect = [sender bounds]; }
    [self presentViewController:activity animated:YES completion:nil];
}

- (NSString *)wjExportTimestamp { NSDateFormatter *f = [NSDateFormatter new]; f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]; f.dateFormat = @"yyyyMMddHHmmssSSS"; return [f stringFromDate:[NSDate date]]; }
- (NSURL *)wjExportDirectory { NSURL *base = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject]; NSURL *dir = [base URLByAppendingPathComponent:@"Recordings" isDirectory:YES]; [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil]; return dir; }
- (UIColor *)wjAnnotationColor:(NSDictionary *)item { return [UIColor colorWithRed:[item[@"r"] doubleValue] green:[item[@"g"] doubleValue] blue:[item[@"b"] doubleValue] alpha:item[@"a"] ? [item[@"a"] doubleValue] : 1.0]; }
- (UIColor *)wjAnnotationTextColorForBackground:(UIColor *)background {
    CGFloat red = 0, green = 0, blue = 0, alpha = 1; [background getRed:&red green:&green blue:&blue alpha:&alpha];
    BOOL useBlack = ((red > .75 && green > .75 && blue < .35) || (green > .65 && red < .35 && blue < .35) || (red > .82 && green > .82 && blue > .82));
    return useBlack ? UIColor.blackColor : UIColor.whiteColor;
}
- (void)wjAnimateAnnotationLayer:(CALayer *)layer item:(NSDictionary *)item duration:(CFTimeInterval)duration {
    double start = [item[@"start"] doubleValue]; id endValue = item[@"end"]; double end = ([endValue isKindOfClass:NSNumber.class] ? [endValue doubleValue] : duration);
    start = MAX(0, MIN(duration, start)); end = MAX(start, MIN(duration, end));
    if (end <= start) end = MIN(duration, start + .05);
    layer.opacity = 0;
    CAKeyframeAnimation *fade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    fade.values = @[@0.0, @0.0, @1.0, @1.0, @0.0];
    fade.keyTimes = @[@0.0, @(start / MAX(duration, .001)), @(start / MAX(duration, .001)), @(end / MAX(duration, .001)), @(end / MAX(duration, .001))];
    fade.duration = duration; fade.beginTime = AVCoreAnimationBeginTimeAtZero; fade.removedOnCompletion = NO; fade.fillMode = kCAFillModeBoth;
    [layer addAnimation:fade forKey:@"wjAnnotationVisibility"];
}
- (void)wjAddDrawingOverlayToLayer:(CALayer *)overlay renderSize:(CGSize)size duration:(CFTimeInterval)duration {
    for (NSDictionary *item in self.drawingAnnotations) {
        NSArray *raw = item[@"points"]; if (![raw isKindOfClass:NSArray.class] || raw.count == 0) continue;
        NSMutableArray<NSValue *> *points = [NSMutableArray array];
        for (NSArray *p in raw) if ([p isKindOfClass:NSArray.class] && p.count >= 2) [points addObject:[NSValue valueWithCGPoint:CGPointMake([p[0] doubleValue] * size.width, [p[1] doubleValue] * size.height)]];
        if (!points.count) continue;
        UIColor *color = [self wjAnnotationColor:item]; CGFloat width = MAX(2.0, [item[@"width"] doubleValue] ?: 3.0);
        CAShapeLayer *shape = [CAShapeLayer layer]; shape.frame = CGRectMake(0, 0, size.width, size.height); shape.strokeColor = color.CGColor; shape.fillColor = UIColor.clearColor.CGColor; shape.lineWidth = width; shape.lineCap = kCALineCapRound; shape.lineJoin = kCALineJoinRound;
        NSString *style = item[@"style"]; if ([style isEqualToString:@"点線"]) shape.lineDashPattern = @[@4, @4]; else if ([style isEqualToString:@"鎖線"]) shape.lineDashPattern = @[@12, @8];
        CGMutablePathRef path = CGPathCreateMutable(); NSString *tool = item[@"tool"] ?: @"直線"; CGPoint first = points.firstObject.CGPointValue, last = points.lastObject.CGPointValue;
        if ([tool isEqualToString:@"軸1"] || [tool isEqualToString:@"軸2"] || [tool isEqualToString:@"軸3D"]) {
            CGFloat radius = hypot(last.x-first.x, last.y-first.y);
            UIColor *yellow = [UIColor.yellowColor colorWithAlphaComponent:.20], *green = [UIColor.systemGreenColor colorWithAlphaComponent:.20], *red = [UIColor.systemRedColor colorWithAlphaComponent:.20];
            NSArray *sectors = nil;
            if ([tool isEqualToString:@"軸1"]) sectors = @[@[@(-105), @(-75), green], @[@(75), @(105), green], @[@(-45), @(45), red], @[@(135), @(225), red]];
            else if ([tool isEqualToString:@"軸2"]) sectors = @[@[@(-120), @(-60), green], @[@(60), @(120), green], @[@(-30), @(30), red], @[@(150), @(210), red]];
            else sectors = @[@[@(-105), @(-75), red], @[@(75), @(105), red], @[@(-30), @(30), green], @[@(150), @(210), green]];
            NSArray *base = @[@[@(-180), @(180), yellow]]; sectors = [base arrayByAddingObjectsFromArray:sectors];
            for (NSArray *sector in sectors) {
                CGFloat start = [sector[0] doubleValue]*M_PI/180.0, end = [sector[1] doubleValue]*M_PI/180.0;
                CAShapeLayer *sectorLayer = [CAShapeLayer layer]; sectorLayer.frame = CGRectMake(0,0,size.width,size.height); sectorLayer.fillColor = [sector[2] CGColor]; sectorLayer.strokeColor = UIColor.clearColor.CGColor;
                sectorLayer.path = WJAxisSectorPath(first, radius, start, end); [overlay addSublayer:sectorLayer]; [self wjAnimateAnnotationLayer:sectorLayer item:item duration:duration];
            }
            continue;
        }
        if ([tool isEqualToString:@"丸"]) { CGFloat r = hypot(last.x-first.x,last.y-first.y); CGPathAddEllipseInRect(path, NULL, CGRectMake(first.x-r, first.y-r, r*2, r*2)); shape.fillColor = [color colorWithAlphaComponent:.2].CGColor; }
        else if ([tool isEqualToString:@"楕円"] || [tool isEqualToString:@"四角"] || [tool isEqualToString:@"三角"]) { CGRect rect = CGRectStandardize(CGRectMake(first.x, first.y, last.x-first.x, last.y-first.y)); if ([tool isEqualToString:@"楕円"]) CGPathAddEllipseInRect(path, NULL, rect); else if ([tool isEqualToString:@"三角"]) { CGPathMoveToPoint(path,NULL,CGRectGetMidX(rect),CGRectGetMinY(rect)); CGPathAddLineToPoint(path,NULL,CGRectGetMaxX(rect),CGRectGetMaxY(rect)); CGPathAddLineToPoint(path,NULL,CGRectGetMinX(rect),CGRectGetMaxY(rect)); CGPathCloseSubpath(path); } else CGPathAddRect(path,NULL,rect); shape.fillColor = [color colorWithAlphaComponent:.2].CGColor; }
        else if ([tool isEqualToString:@"x"]) { CGFloat arm=MAX(4.0, hypot(last.x-first.x,last.y-first.y)), rotation=[item[@"rotation"] doubleValue], c=cos(rotation), s=sin(rotation); CGPoint p1=CGPointMake(first.x+c*(-arm), first.y+s*(-arm)), p2=CGPointMake(first.x+c*arm, first.y+s*arm), p3=CGPointMake(first.x-s*(-arm), first.y+c*(-arm)), p4=CGPointMake(first.x-s*arm, first.y+c*arm); CGPathMoveToPoint(path,NULL,p1.x,p1.y); CGPathAddLineToPoint(path,NULL,p2.x,p2.y); CGPathMoveToPoint(path,NULL,p3.x,p3.y); CGPathAddLineToPoint(path,NULL,p4.x,p4.y); }
        else { CGPathMoveToPoint(path,NULL,first.x,first.y); for (NSValue *v in points.count > 1 ? [points subarrayWithRange:NSMakeRange(1, points.count-1)] : @[]) { CGPoint p = v.CGPointValue; CGPathAddLineToPoint(path,NULL,p.x,p.y); } }
        shape.path = path; CGPathRelease(path); [overlay addSublayer:shape]; [self wjAnimateAnnotationLayer:shape item:item duration:duration];
        NSString *text = item[@"text"]; NSNumber *angle = item[@"angle"]; if (text.length == 0 && angle) text = [NSString stringWithFormat:@"%.1f°", angle.doubleValue];
        if (text.length) { CATextLayer *label = [CATextLayer layer]; label.string = text; label.font = (__bridge CFTypeRef)@"Helvetica-Bold"; label.fontSize = 20; label.alignmentMode = kCAAlignmentCenter; label.contentsScale = UIScreen.mainScreen.scale; label.foregroundColor = [self wjAnnotationTextColorForBackground:color].CGColor; label.backgroundColor = [color colorWithAlphaComponent:.8].CGColor; label.cornerRadius = 5; label.frame = CGRectMake(last.x - 42, last.y - 16, 84, 32); [overlay addSublayer:label]; [self wjAnimateAnnotationLayer:label item:item duration:duration]; }
    }
}
- (void)exportDrawingVideo:(id)sender {
    NSURL *url = [(AVURLAsset *)self.player.currentItem.asset URL]; if (!url) return;
    if (!self.drawingAnnotations.count) [self loadDrawingAnnotations];
    AVAsset *asset = [AVAsset assetWithURL:url]; AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject; if (!track) return;
    CMTime duration = asset.duration; CGSize render = WJDrawingOrientedTrackSize(track);
    AVMutableComposition *composition = [AVMutableComposition composition]; AVMutableCompositionTrack *compTrack = [composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid]; AVAssetTrack *audioTrack = [asset tracksWithMediaType:AVMediaTypeAudio].firstObject; AVMutableCompositionTrack *audioComp = audioTrack ? [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid] : nil; NSError *error = nil; [compTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero,duration) ofTrack:track atTime:kCMTimeZero error:&error]; if (audioComp) [audioComp insertTimeRange:CMTimeRangeMake(kCMTimeZero,duration) ofTrack:audioTrack atTime:kCMTimeZero error:&error]; if (error) { [self showExportError:error]; return; }
    AVMutableVideoComposition *videoComposition = [AVMutableVideoComposition videoComposition]; videoComposition.renderSize = render; videoComposition.frameDuration = CMTimeMake(1, 30); AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction]; instruction.timeRange = CMTimeRangeMake(kCMTimeZero,duration); AVMutableVideoCompositionLayerInstruction *layerInstruction = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:compTrack]; [layerInstruction setTransform:WJDrawingNormalizedTrackTransform(track) atTime:kCMTimeZero]; instruction.layerInstructions = @[layerInstruction]; videoComposition.instructions = @[instruction];
    CALayer *parent = [CALayer layer]; parent.frame = CGRectMake(0,0,render.width,render.height); parent.geometryFlipped = YES; CALayer *videoLayer = [CALayer layer]; videoLayer.frame = parent.bounds; [parent addSublayer:videoLayer]; CALayer *overlay = [CALayer layer]; overlay.frame = parent.bounds; [parent addSublayer:overlay]; [self wjAddDrawingOverlayToLayer:overlay renderSize:render duration:CMTimeGetSeconds(duration)]; videoComposition.animationTool = [AVVideoCompositionCoreAnimationTool videoCompositionCoreAnimationToolWithPostProcessingAsVideoLayer:videoLayer inLayer:parent];
    NSString *stem = [[url URLByDeletingPathExtension].lastPathComponent stringByReplacingOccurrencesOfString:@"/" withString:@"_"]; NSURL *output = [[self wjExportDirectory] URLByAppendingPathComponent:[NSString stringWithFormat:@"%@_DRAWING_%@.MOV", stem, [self wjExportTimestamp]]]; AVAssetExportSession *session = [[AVAssetExportSession alloc] initWithAsset:composition presetName:AVAssetExportPresetHighestQuality]; session.outputURL = output; session.outputFileType = AVFileTypeQuickTimeMovie; session.videoComposition = videoComposition; if (audioComp) { AVMutableAudioMix *audioMix = [AVMutableAudioMix audioMix]; AVMutableAudioMixInputParameters *parameters = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:audioComp]; [parameters setVolume:1.0 atTime:kCMTimeZero]; audioMix.inputParameters = @[parameters]; session.audioMix = audioMix; } self.exportButton.enabled = NO; [session exportAsynchronouslyWithCompletionHandler:^{ dispatch_async(dispatch_get_main_queue(), ^{ self.exportButton.enabled = YES; if (session.status == AVAssetExportSessionStatusCompleted) [self presentExportedFile:output from:self.exportButton]; else [self showExportError:session.error ?: [NSError errorWithDomain:@"MTJudge.Export" code:2 userInfo:@{NSLocalizedDescriptionKey:@"描画付き動画を書き出せませんでした。"}]]; }); }];
}
- (void)presentExportedFile:(NSURL *)url from:(UIView *)source { UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil]; if (activity.popoverPresentationController) { activity.popoverPresentationController.sourceView = source; activity.popoverPresentationController.sourceRect = source.bounds; } [self presentViewController:activity animated:YES completion:nil]; }
- (void)showExportError:(NSError *)error { UIAlertController *a = [UIAlertController alertControllerWithTitle:@"書き出し失敗" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil]; }

- (void)toggleFavorite:(id)sender {
    NSURL *url = [(AVURLAsset *)self.player.currentItem.asset URL];
    if (!url) return;
    NSMutableArray *paths = [NSMutableArray arrayWithArray:[[NSUserDefaults standardUserDefaults] arrayForKey:@"WJFavoriteVideoPaths"] ?: @[]];
    if ([paths containsObject:url.path]) { [paths removeObject:url.path]; self.favorite = NO; }
    else { [paths addObject:url.path]; self.favorite = YES; }
    [[NSUserDefaults standardUserDefaults] setObject:paths forKey:@"WJFavoriteVideoPaths"];
    [self.favoriteButton setImage:[UIImage systemImageNamed:(self.favorite ? @"heart.fill" : @"heart")] forState:UIControlStateNormal];
    self.favoriteButton.tintColor = self.favorite ? UIColor.systemPinkColor : UIColor.whiteColor;
    self.favoriteIndicator.hidden = !self.favorite;
    [[NSNotificationCenter defaultCenter] postNotificationName:@"WJVideoFavoritesChanged" object:url];
    [self showSpeedControls];
}

- (void)refreshFeatureButtons {
    self.loopStartButton.accessibilityValue = CMTIME_IS_VALID(self.loopStartTime) ? [NSString stringWithFormat:@"A %.2f秒", CMTimeGetSeconds(self.loopStartTime)] : @"未設定";
    self.loopEndButton.accessibilityValue = CMTIME_IS_VALID(self.loopEndTime) ? [NSString stringWithFormat:@"B %.2f秒", CMTimeGetSeconds(self.loopEndTime)] : @"未設定";
    self.loopStartButton.backgroundColor = CMTIME_IS_VALID(self.loopStartTime) ? [UIColor.systemGreenColor colorWithAlphaComponent:.55] : [UIColor colorWithWhite:0 alpha:.25];
    self.loopEndButton.backgroundColor = CMTIME_IS_VALID(self.loopEndTime) ? [UIColor.systemGreenColor colorWithAlphaComponent:.55] : [UIColor colorWithWhite:0 alpha:.25];
    self.loopButton.backgroundColor = self.loopEnabled ? [UIColor.systemBlueColor colorWithAlphaComponent:0.5] : [UIColor colorWithWhite:0 alpha:0.25];
    self.mirrorButton.backgroundColor = self.mirroredPlayback ? [UIColor.systemBlueColor colorWithAlphaComponent:0.5] : [UIColor colorWithWhite:0 alpha:0.25];
    self.skeletonButton.backgroundColor = self.skeletonVisible ? [UIColor.systemBlueColor colorWithAlphaComponent:0.5] : [UIColor colorWithWhite:0 alpha:0.25];
}

- (void)showVideoInfo:(id)sender {
    NSURL *url = [(AVURLAsset *)self.player.currentItem.asset URL];
    if (!url) return;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    NSDictionary *values = [url resourceValuesForKeys:@[NSURLFileSizeKey, NSURLCreationDateKey] error:nil];
    NSNumber *size = values[NSURLFileSizeKey];
    NSDate *created = values[NSURLCreationDateKey];
    NSString *dateText = created ? [NSDateFormatter localizedStringFromDate:created dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterMediumStyle] : @"情報なし";
    double duration = CMTimeGetSeconds(asset.duration);
    NSString *durationText = isfinite(duration) ? [NSString stringWithFormat:@"%.2f 秒", duration] : @"情報なし";
    NSString *resolution = track ? [NSString stringWithFormat:@"%.0f × %.0f", fabs(track.naturalSize.width), fabs(track.naturalSize.height)] : @"情報なし";
    NSString *fps = (track && track.nominalFrameRate > 0) ? [NSString stringWithFormat:@"%.2f fps", track.nominalFrameRate] : @"情報なし";
    NSString *sizeText = size ? [NSString stringWithFormat:@"%.2f MB", size.doubleValue / 1048576.0] : @"情報なし";
    NSArray *tags = [self tagsForVideoURL:url];
    NSString *tagText = tags.count ? [tags componentsJoinedByString:@", "] : @"情報なし";
    NSString *message = [NSString stringWithFormat:@"ファイル名: %@\n撮影日時: %@\n撮影端末: 情報なし\n長さ: %@\n解像度: %@\nフレームレート: %@\nファイルサイズ: %@\nタグ: %@", url.lastPathComponent, dateText, durationText, resolution, fps, sizeText, tagText];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"動画情報" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"閉じる" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSArray<NSString *> *)tagsForVideoURL:(NSURL *)url {
    NSURL *sidecar = [url URLByAppendingPathExtension:@"tags.json"];
    NSData *data = [NSData dataWithContentsOfURL:sidecar];
    if (!data) {
        NSURL *stemSidecar = [[[url URLByDeletingPathExtension] URLByAppendingPathExtension:@"tags"] URLByAppendingPathExtension:@"json"];
        data = [NSData dataWithContentsOfURL:stemSidecar];
    }
    id object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if ([object isKindOfClass:NSArray.class]) {
        NSMutableArray *names = [NSMutableArray array];
        for (id item in (NSArray *)object) {
            if ([item isKindOfClass:NSString.class]) [names addObject:item];
            else if ([item isKindOfClass:NSDictionary.class] && [item[@"name"] isKindOfClass:NSString.class]) [names addObject:item[@"name"]];
        }
        if (names.count) return names;
    }
    if ([object isKindOfClass:NSDictionary.class]) {
        id tags = object[@"tags"] ?: object[@"selectedTags"];
        if ([tags isKindOfClass:NSArray.class]) {
            NSMutableArray *names = [NSMutableArray array];
            for (id item in (NSArray *)tags) {
                if ([item isKindOfClass:NSString.class]) [names addObject:item];
                else if ([item isKindOfClass:NSDictionary.class] && [item[@"name"] isKindOfClass:NSString.class]) [names addObject:item[@"name"]];
            }
            if (names.count) return names;
        }
    }
    NSArray *latest = [[NSUserDefaults standardUserDefaults] arrayForKey:@"LatestCameraRecordingTags"];
    if ([latest isKindOfClass:NSArray.class] && latest.count && [url.path isEqualToString:[[NSUserDefaults standardUserDefaults] stringForKey:@"LatestCameraRecordingPath"]]) {
        NSMutableArray *names = [NSMutableArray array];
        for (NSDictionary *item in latest) if ([item isKindOfClass:NSDictionary.class] && [item[@"name"] isKindOfClass:NSString.class]) [names addObject:item[@"name"]];
        if (names.count) return names;
    }
    return @[];
}

- (void)toggleSkeleton:(id)sender {
    self.skeletonVisible = !self.skeletonVisible;
    self.skeletonOverlayLayer.hidden = !self.skeletonVisible;
    self.takeoffButton.enabled = self.skeletonVisible;
    self.takeoffButton.alpha = self.skeletonVisible ? 1.0 : .4;
    if (!self.skeletonVisible) {
        self.takeoffSetupStep = 0;
        self.analysisLabel.hidden = YES;
        for (UILabel *label in @[self.ankleAnalysisLabel, self.kneeAnalysisLabel, self.hipAnalysisLabel, self.torsoAnalysisLabel]) label.hidden = YES;
    }
    [self refreshFeatureButtons];
    if (self.skeletonVisible) [self loadAnalysisForCurrentVideo];
    [self showSpeedControls];
}

- (void)deleteCurrentVideo:(id)sender {
    NSURL *url = [(AVURLAsset *)self.player.currentItem.asset URL];
    if (!url || ![url.pathExtension.lowercaseString isEqualToString:@"mov"]) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"動画を削除しますか？" message:url.lastPathComponent preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"削除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSFileManager *files = NSFileManager.defaultManager;
        NSError *error = nil;
        for (NSURL *target in WJPlayerVideoAndRelatedJSONFiles(url)) {
            if ([files fileExistsAtPath:target.path] && ![files removeItemAtURL:target error:&error]) break;
        }
        if (error) {
            UIAlertController *failure = [UIAlertController alertControllerWithTitle:@"削除できません" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [failure addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:failure animated:YES completion:nil];
        } else {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"WJVideoDeleted" object:url];
            [self dismissViewControllerAnimated:YES completion:nil];
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)setLoopStart:(id)sender {
    self.loopStartTime = self.player.currentTime;
    if (CMTIME_IS_VALID(self.loopEndTime) && CMTimeCompare(self.loopEndTime, self.loopStartTime) <= 0) {
        self.loopEndTime = kCMTimeInvalid;
        self.loopEnabled = NO;
    }
    [self.speedHideTimer invalidate];
    self.speedHideTimer = nil;
    [self refreshFeatureButtons];
}

- (void)setLoopEnd:(id)sender {
    if (!CMTIME_IS_VALID(self.loopStartTime)) return;
    CMTime current = self.player.currentTime;
    if (CMTimeCompare(current, self.loopStartTime) <= 0) { self.loopEnabled = NO; [self refreshFeatureButtons]; return; }
    self.loopEndTime = current;
    self.loopEnabled = YES;
    [self refreshFeatureButtons];
    [self showSpeedControls];
}

- (void)toggleLoop:(id)sender {
    // 再度タップした場合は、リピート動作だけでなくA/Bの設定も解除する。
    // 未設定時の「動画全体リピート」も同じトグルで解除できる。
    if (self.loopEnabled) {
        self.loopEnabled = NO;
        self.loopStartTime = kCMTimeInvalid;
        self.loopEndTime = kCMTimeInvalid;
        self.loopSeekInProgress = NO;
    } else {
        self.loopEnabled = YES;
    }
    [self refreshFeatureButtons];
    [self showSpeedControls];
}

- (CMTime)videoFrameDuration {
    AVAssetTrack *track = [self.player.currentItem.asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    CMTime duration = track.minFrameDuration;
    if (CMTIME_IS_VALID(duration) && duration.value > 0) return duration;
    float fps = track.nominalFrameRate;
    if (fps <= 0) fps = 30.0f;
    return CMTimeMakeWithSeconds(1.0 / fps, 600);
}

- (void)stepOneFrame:(id)sender {
    if (self.slowMotionActive || self.suppressNextFrameStep) {
        self.suppressNextFrameStep = NO;
        return;
    }
    [self.player pause];
    CMTime next = CMTimeAdd(self.player.currentTime, [self videoFrameDuration]);
    CMTime duration = self.player.currentItem.duration;
    if (CMTIME_IS_VALID(duration) && CMTimeCompare(next, duration) > 0) next = duration;
    [self.player seekToTime:next toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:nil];
}

- (void)stepOneFrameBack:(id)sender {
    if (self.slowMotionActive || self.suppressNextFrameBack) {
        self.suppressNextFrameBack = NO;
        return;
    }
    [self.player pause];
    CMTime previous = CMTimeSubtract(self.player.currentTime, [self videoFrameDuration]);
    if (CMTIME_COMPARE_INLINE(previous, <, kCMTimeZero)) previous = kCMTimeZero;
    [self.player seekToTime:previous toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:nil];
}

- (void)frameStepLongPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.slowMotionActive = YES;
        self.suppressNextFrameStep = NO;
        self.wjSelectedSpeed = 0.5f;
        [self updateSpeedSlider];
        self.player.rate = 0.5f;
        [self.playButton setImage:[UIImage systemImageNamed:@"pause.fill"] forState:UIControlStateNormal];
        [self showSpeedControls];
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) {
        if (!self.slowMotionActive) return;
        self.slowMotionActive = NO;
        self.suppressNextFrameStep = YES;
        [self.player pause];
        [self.playButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal];
        [self showSpeedControls];
    }
}

- (void)frameBackLongPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.slowMotionActive = YES;
        self.suppressNextFrameBack = NO;
        self.wjSelectedSpeed = 0.5f;
        [self updateSpeedSlider];
        // コマ戻しの長押しは逆方向へ0.5倍速で再生する。
        self.player.rate = -0.5f;
        [self.playButton setImage:[UIImage systemImageNamed:@"pause.fill"] forState:UIControlStateNormal];
        [self showSpeedControls];
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) {
        if (!self.slowMotionActive) return;
        self.slowMotionActive = NO;
        self.suppressNextFrameBack = YES;
        [self.player pause];
        [self.playButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal];
        [self showSpeedControls];
    }
}

- (void)applyMirrorToPlayerLayers {
    AVPlayerLayer *videoLayer = [self findPlayerLayerInLayer:self.view.layer];
    videoLayer.affineTransform = self.mirroredPlayback ? CGAffineTransformMakeScale(-1, 1) : CGAffineTransformIdentity;
}

- (AVPlayerLayer *)findPlayerLayerInLayer:(CALayer *)layer {
    if ([layer isKindOfClass:[AVPlayerLayer class]]) return (AVPlayerLayer *)layer;
    for (CALayer *child in layer.sublayers) {
        AVPlayerLayer *found = [self findPlayerLayerInLayer:child];
        if (found) return found;
    }
    return nil;
}

- (void)toggleMirror:(id)sender {
    self.mirroredPlayback = !self.mirroredPlayback;
    [self applyMirrorToPlayerLayers];
    [self refreshFeatureButtons];
}

@end
