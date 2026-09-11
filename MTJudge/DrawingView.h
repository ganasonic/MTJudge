
#import <UIKit/UIKit.h>

#define LANE_CHANGE_UNIT    1.6

@interface DrawingView : UIView {
    void *data;
    CGContextRef context;
	id	_delegate;
	CGPoint startPoint;
	CGPoint endPoint;
    NSInteger   course_len_px;
}

- (void)clear;
- (void)toggleColor:(BOOL)isBlack;
- (void)setLineWidth:(CGFloat)width;
- (void)setDelegate:(id)deletage;
- (UIImage *)UIImage;

@end
