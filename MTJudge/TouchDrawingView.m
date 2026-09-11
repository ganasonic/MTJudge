//
//  TouchDrawingView.m
//  MTJudge
//
//  Created by 長島 康敬 on 2012/11/07.
//  Copyright (c) 2012年 Yokohama. All rights reserved.
//

#include "math.h"

#import "TouchDrawingView.h"
#import "JudgeViewController.h"

@implementation TouchDrawingView



- (id)initWithFrame:(CGRect)frame
{
    NSLog(@"ログ（%-20s,%-24s:%5d）in\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
    self = [super initWithFrame:frame];
    if (self) {
        [self setup];
    }
    NSLog(@"ログ（%-20s,%-24s:%5dout\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
    return self;
}

- (id)initWithCoder:(NSCoder *)coder {
	NSLog(@"ログ（%-20s,%-24s:%5d）in\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
    self = [super initWithCoder:coder];
    if (self) {
        [self setup];
    }
	NSLog(@"ログ（%-20s,%-24s:%5dout\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
    return self;
}

-(void)setup{
#if true
    int width = self.bounds.size.width;
    int height = self.bounds.size.height;
    data = malloc(width * height * 4);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    context = CGBitmapContextCreate(data, width, height, 8, 4 * width,
                                    colorSpace, kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(colorSpace);
#endif
    [self clear];
    f_reduction = 0.0;
    aryReduction = [[NSMutableArray alloc] init];
    CGContextSetLineWidth(context, 14);
    NSLog(@"ログ（%-20s,%-24s:%5dout\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
}

#if false
- (void)setBackgroundColor:(UIColor *)backgroundColor{
    self.backgroundColor = backgroundColor;
}
#endif

- (void)setDrawType:(int)_type {
	type = _type;
}

- (void)setDelegate:(id)deletage {
	_delegate = deletage;
}

- (void)drawRect:(CGRect)rect {
	NSLog(@"ログ（%-20s,%-24s:%5d）in\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
    // Drawing code
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRef currentContext = UIGraphicsGetCurrentContext();
    CGContextDrawImage(currentContext, rect, image);
    CGImageRelease(image);
	NSLog(@"ログ（%-20s,%-24s:%5dout\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
}

- (void)clear{
	NSLog(@"ログ（%-20s,%-24s:%5d）in\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
    CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, 1.0);
    CGContextFillRect(context, self.bounds);
    
	CGContextSetRGBStrokeColor(context, 0.0, 0.0, 1.0, 0.5);
	CGContextStrokePath(context);
    [self setNeedsDisplay];
    fall_sum = 0.0;
	NSLog(@"ログ（%-20s,%-24s:%5dout\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
}

- (void)toggleColor:(BOOL)isBlack{
	NSLog(@"ログ（%-20s,%-24s:%5d）in\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
    if(isBlack){
        CGContextSetRGBStrokeColor(context, 0.0, 0.0, 0.0, 1.0);
    }else{
        CGContextSetRGBStrokeColor(context, 1.0, 1.0, 1.0, 1.0);
    }
	NSLog(@"ログ（%-20s,%-24s:%5dout\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
}

- (UIImage *)UIImage{
    CGImageRef cgimage = CGBitmapContextCreateImage(context);
    UIImage *image = [UIImage imageWithCGImage:cgimage];
    CGImageRelease(cgimage);
    return image;
}

-(void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    startPoint = [[touches anyObject] locationInView:self];
    intFall = 0;
	[self createLabel:startPoint];
}

-(void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
#if false
    endPoint = [[touches anyObject] locationInView:self];
	int dX = abs(endPoint.x-startPoint.x);
	int dY = abs(endPoint.y-startPoint.y);
    intFall = dX>dY?dX:dY;
    [self createLabel:endPoint];
#endif
//	[_delegate setSideDirection:dX];
//	[_delegate setFallDirection:dY];
//	[_delegate createLabel:endPoint];
//	[self setFallDirection:dY];
    [_delegate recaluculate];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)evnet {
	//NSLog(@"ログ（%-20s,%-24s:%5d）in\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
    CGPoint p = [[touches anyObject] locationInView:self];
    CGPoint q = [[touches anyObject] previousLocationInView:self];
    
    CGContextSetLineCap(context, kCGLineCapRound);
    CGContextBeginPath(context);
    CGContextMoveToPoint(context, q.x, q.y);
    CGContextAddLineToPoint(context, p.x, p.y);
    CGContextStrokePath(context);
    [self setNeedsDisplay];
	//NSLog(@"ログ（%-20s,%-24s:%5dout\n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
    endPoint = [[touches anyObject] locationInView:self];
	int dX = fabs(endPoint.x-startPoint.x);
	int dY = fabs(endPoint.y-startPoint.y);
    intFall = dX>dY?dX:dY;

    float red = -[self getFallReduction:intFall];
	labelFall.text = [NSString stringWithFormat:@"%3.2f", red];
    NSLog(@"x:%5d   y:%5d\n", dX, dY);
}

- (void)clearInner{
//	int count = [aryReduction count];
	for (UILabel *obj in aryReduction) {
		NSLog(@"ログ（%-20s,%-24s:%5d） \n", __FILE__, __PRETTY_FUNCTION__, __LINE__);
		[obj removeFromSuperview];
	}
    [self clear];
}

- (void)dealloc {
	free(data);
	CGContextRelease(context);
    //[super dealloc];
}


- (void)createLabel:(CGPoint)point {
    float red = [self getFallReduction:intFall];
	f_reduction = -red;
	UIFont *myfont = [UIFont fontWithName:@"Courier" size:10];
	//UILabel *labelFall = [[[UILabel alloc] initWithFrame:CGRectMake(point.x, point.y+12, 40, 12)] autorelease];
//	labelFall = [[[UILabel alloc] initWithFrame:CGRectMake(point.x, point.y+12, 40, 12)] autorelease];
	labelFall = [[UILabel alloc] initWithFrame:CGRectMake(point.x, point.y-24, 40, 12)];
	labelFall.font = myfont;
    //labelFall.backgroundColor = UIColor.blueColor;
    labelFall.textColor = UIColor.blackColor;
	labelFall.text = [NSString stringWithFormat:@"%3.2f", f_reduction];
	[self addSubview:labelFall];
	//ページを追加
	[aryReduction addObject:labelFall];
    
	fall_sum += f_reduction;
	
//    sumFallValue.text = [NSString stringWithFormat:@"%3.2f", -(fall_sum)];
	
//	txt_reduction.text = [NSString stringWithFormat:@"%2.1f", f_reduction];
}

- (float)getTotalReduction{
    return fall_sum;
}

- (float) getFallReduction:(int)_value {
    float value = (float)_value;
	float target = 0.0;
    int val = 0;
    switch (type) {
		//完全停止
        case DRAW_TYPE_D15:
            target = 6.0;//完全停止
            break;
		//停止、または中断のない完全転倒。フォールラインを滑り落ちる、明らかなスライディング、またはほぼ完全停止するような斜面の横断
        case DRAW_TYPE_D11:
            target = 4.1+(value/60.0*1.8);//4.1〜5.9=1.8
            if (target>5.9) {
                target = 5.9;
            }
            break;
		//滑走スピードを著しく制御するような停止や中断のないスライディング、激しいタッチダウン、または前方回転。
        case DRAW_TYPE_D08:
            target = 2.9+(value/60.0*1.1);//2.9〜4.0=1.1
            if (target>4.0) {
                target = 4.0;
            }
            break;
		//停止のない中くらいのタッチダウン
        case DRAW_TYPE_D06:
            target = 2.1+(value/60.0*0.7);//2.1〜2.8=0.7
            if (target>2.8) {
                target = 2.8;
            }
            break;
		//滑りが妨げられないような、軽いタッチダウン、小さなつまづき、フォールラインを外れる、スピードチェック、両ポールを同時につく、シューティング。
        case DRAW_TYPE_D01:
            target = 0.1+(value/60.0*1.9);//0.1〜2.0=1.9
            if (target>2.0) {
                target = 2.0;
            }
            break;
		//軽微なミス
        case DRAW_TYPE_REDUCTION:
            val = _value/10;
            switch (val) {
                case 0:
                    target = 0.1;
                    break;
                case 1:
                    target = 0.4;
                    break;
                case 2:
                    target = 0.8;
                    break;
                case 3:
                    target = 1.2;
                    break;
                case 4:
                    target = 1.6;
                    break;
                case 5:
                default:
                    target = 2.0;
                    break;
            }
            //target = 0.1+(value/80.0*0.9);
            break;
		//レーンチェンジ
        case DRAW_TYPE_LANECHANGE:
#if false
            switch (_value/10) {
                case 0:
                    target = 0.2;
                    break;
                case 1:
                    target = 0.4;
                    break;
                case 2:
                    target = 0.8;
                    break;
                case 3:
                default:
                    target = 1.6;
                    break;
            }
#else
            if (value<=20) {
                target = 0.8;//半分
            }else 	if (value>21 && value<=40) {
                target = 1.6;//１ライン
            }else 	if (value>41 && value<=60) {
                target = 2.4;//１．５ライン
            }else{
                target = 3.2;//２ライン
            }
#endif
            break;
        case DRAW_TYPE_NOTURN:
            switch (_value/10) {
                case 0:
                    target = 0.5;
                    break;
                case 1:
                    target = 1.0;
                    break;
                case 2:
                    target = 1.5;
                    break;
                case 3:
                default:
                    target = 2.0;
                    break;
            }
            //target = 0.5*(value/80.0*6.0);
            break;
            
        default:
            break;
    }
    //char tempbuf[8];
    //memcpy(tempbuf, "¥0", 8);
    //sprintf(tempbuf, "%3.2f¥0", target);
    float target2 = [self RoundDown:target Digit:2];
    //target = atof(tempbuf);
	//return target;
    return target2;
}

-(float)RoundDown:(float)value Digit:(int)digit
{
    float temp = pow(10, digit);
    if (0 <= value)
    {
        return floor(value * temp) / temp;
    }
    else
    {
        return ceil(value * temp) / temp;
    }
}

-(IBAction)setFallDirection:(int)value{
    intFall = value;
    intFallValue.text = [NSString stringWithFormat:@"%2.1f", -[self getFallReduction:intFall]];
}

-(IBAction)setReduction:(float)value{
    f_reduction = value;
}

@end
