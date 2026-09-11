//
//  TouchDrawingView.h
//  MTJudge
//
//  Created by 長島 康敬 on 2012/11/07.
//  Copyright (c) 2012年 Yokohama. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface TouchDrawingView : UIView{
    void *data;
    CGContextRef context;
	id	_delegate;
	CGPoint startPoint;
	CGPoint endPoint;
	NSMutableArray	*aryReduction;

	float		f_reduction;
	float		fall_sum;
	UILabel		*intFallValue;
	UILabel		*sumFallValue;
	UILabel		*labelFall;
	int			intFall;
    int         type;
    enum DRAW_TYPE {
        DRAW_TYPE_D15,
        DRAW_TYPE_D11,
        DRAW_TYPE_D08,
        DRAW_TYPE_D06,
        DRAW_TYPE_D01,
        DRAW_TYPE_REDUCTION,
        DRAW_TYPE_LANECHANGE,
        DRAW_TYPE_NOTURN
    };
}
- (void)setDrawType:(int)_type;
- (void)setDelegate:(id)deletage;
//- (void)setBackgroundColor:(UIColor *)backgroundColor;
- (float) getTotalReduction;
- (float) getFallReduction:(int)value;
- (void)clear;
- (void)clearInner;
- (float) RoundDown:(float)value Digit:(int)digit;
@end
