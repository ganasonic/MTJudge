#include <TargetConditionals.h>
#if !TARGET_OS_SIMULATOR
// Keep OpenCV ahead of Objective-C headers (Apple's NO macro collides with C++ enums).
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/features2d.hpp>
#include <opencv2/calib3d.hpp>
#include <opencv2/video/tracking.hpp>
#endif
#import "OverlayRegistration.h"

NSArray<NSNumber *> *MTJOverlayMatrixArray(simd_double3x3 m) {
    NSMutableArray *a = [NSMutableArray array];
    for (int r=0;r<3;r++) for (int c=0;c<3;c++) [a addObject:@(m.columns[c][r])];
    return a;
}
simd_double3x3 MTJOverlayMatrix(NSArray *a) {
    simd_double3x3 m = matrix_identity_double3x3;
    if (![a isKindOfClass:NSArray.class] || a.count != 9) return m;
    for (int r=0;r<3;r++) for (int c=0;c<3;c++) {
        if (![a[r*3+c] isKindOfClass:NSNumber.class]) return matrix_identity_double3x3;
        m.columns[c][r] = [a[r*3+c] doubleValue];
    }
    return MTJOverlayMatrixIsValid(m) ? m : matrix_identity_double3x3;
}
BOOL MTJOverlayMatrixIsValid(simd_double3x3 m) {
    for (int c=0;c<3;c++) for (int r=0;r<3;r++) if (!isfinite(m.columns[c][r])) return NO;
    return fabs(simd_determinant(m)) > 1e-10;
}
CGPoint MTJOverlayProject(simd_double3x3 m, CGPoint p) {
    simd_double3 q = simd_mul(m, (simd_double3){p.x,p.y,1});
    return fabs(q.z)>1e-9 ? CGPointMake(q.x/q.z,q.y/q.z) : CGPointMake(NAN,NAN);
}
#if !TARGET_OS_SIMULATOR
static cv::Mat Gray(CGImageRef image) {
    cv::Mat rgba((int)CGImageGetHeight(image),(int)CGImageGetWidth(image),CV_8UC4);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(rgba.data,rgba.cols,rgba.rows,8,rgba.step,space,kCGImageAlphaNoneSkipLast|kCGBitmapByteOrder32Big);
    if (!context) { CGColorSpaceRelease(space); return {}; }
    CGContextDrawImage(context,CGRectMake(0,0,rgba.cols,rgba.rows),image);
    CGContextRelease(context); CGColorSpaceRelease(space);
    cv::Mat gray; cv::cvtColor(rgba,gray,cv::COLOR_RGBA2GRAY); return gray;
}
static cv::Mat Background(CGImageRef mask, cv::Size size) {
    cv::Mat bg(size,CV_8U,cv::Scalar(255));
    if (mask) {
        cv::Mat gray=Gray(mask); if (!gray.empty()) {
            cv::resize(gray,gray,size); cv::threshold(gray,gray,24,255,cv::THRESH_BINARY);
            cv::dilate(gray,gray,cv::getStructuringElement(cv::MORPH_ELLIPSE,{19,19}));
            cv::bitwise_not(gray,bg);
        }
    }
    // Avoid compression borders and black margins dominating matches.
    cv::rectangle(bg,{0,0,size.width,size.height},cv::Scalar(0),6);
    return bg;
}
static NSDictionary *Failure(NSString *reason) { return @{@"valid":@NO,@"reason":reason}; }
static NSDictionary *Fit(const std::vector<cv::Point2f>& from,const std::vector<cv::Point2f>& to,cv::Size ss,cv::Size ms,NSString *method) {
    if (from.size()<12) return Failure(@"背景の対応点が不足しています");
    cv::Mat inliers, h=cv::findHomography(from,to,cv::RANSAC,3.0,inliers,2000,.995);
    if (h.empty() || !cv::checkRange(h)) return Failure(@"変換を推定できません");
    int count=cv::countNonZero(inliers); double ratio=(double)count/from.size();
    std::vector<cv::Point2f> sf, mf, predicted; cv::perspectiveTransform(from,predicted,h);
    double error=0; for (size_t i=0;i<from.size();i++) if (inliers.at<uchar>((int)i)) {
        sf.push_back(from[i]); mf.push_back(to[i]); error+=cv::norm(predicted[i]-to[i]);
    }
    if (count<12 || ratio<.4) return Failure(@"背景の対応が不確かです");
    error/=count;
    std::vector<cv::Point2f> hull; cv::convexHull(mf,hull);
    double coverage=cv::contourArea(hull)/ms.area();
    cv::convexHull(sf,hull); double subCoverage=cv::contourArea(hull)/ss.area();
    if (coverage<.035 || subCoverage<.035 || error>3.0) return Failure(@"対応点が狭い領域に偏っています");
    std::vector<cv::Point2f> corners={{0,0},{(float)ss.width,0},{(float)ss.width,(float)ss.height},{0,(float)ss.height}}, projected;
    cv::perspectiveTransform(corners,projected,h);
    if (!cv::isContourConvex(projected)) return Failure(@"射影が不安定です");
    double area=cv::contourArea(projected)/(double)ms.area();
    if (area<.08 || area>12) return Failure(@"画角または倍率の差が大きすぎます");
    std::vector<cv::Point2f> bounds={{0,0},{(float)ms.width,0},{(float)ms.width,(float)ms.height},{0,(float)ms.height}}, overlap;
    if (cv::intersectConvexConvex(projected,bounds,overlap)/ms.area()<.12) return Failure(@"背景の重なりが不足しています");
    cv::Mat sn=(cv::Mat_<double>(3,3)<<ss.width,0,0,0,ss.height,0,0,0,1);
    cv::Mat mn=(cv::Mat_<double>(3,3)<<1.0/ms.width,0,0,0,1.0/ms.height,0,0,0,1);
    cv::Mat n=mn*h*sn; n/=n.at<double>(2,2);
    simd_double3x3 m; for(int r=0;r<3;r++) for(int c=0;c<3;c++) m.columns[c][r]=n.at<double>(r,c);
    if (!MTJOverlayMatrixIsValid(m)) return Failure(@"変換行列が不正です");
    return @{@"valid":@YES,@"matrix":MTJOverlayMatrixArray(m),@"inliers":@(count),@"ratio":@(ratio),@"errorPixels":@(error),@"coverage":@(coverage),@"method":method};
}
#endif
@implementation OverlayRegistration
- (NSDictionary *)registerMain:(CGImageRef)main sub:(CGImageRef)sub mainMask:(CGImageRef)mainMask subMask:(CGImageRef)subMask {
#if TARGET_OS_SIMULATOR
    return @{@"valid":@NO,@"reason":@"自動背景合わせは実機で利用できます"};
#else
    try {
        cv::Mat a=Gray(main), b=Gray(sub); if(a.empty()||b.empty()) return Failure(@"画像を読めません");
        cv::Mat am=Background(mainMask,a.size()), bm=Background(subMask,b.size());
        for (int pass=0;pass<2;pass++) {
            cv::Ptr<cv::Feature2D> detector;
            if(pass==0) detector=cv::ORB::create(2400); else detector=cv::SIFT::create(1600);
            std::vector<cv::KeyPoint> ak,bk; cv::Mat ad,bd;
            detector->detectAndCompute(a,am,ak,ad); detector->detectAndCompute(b,bm,bk,bd);
            if(ad.empty()||bd.empty()||ad.rows<2||bd.rows<2) continue;
            cv::BFMatcher matcher(pass==0?cv::NORM_HAMMING:cv::NORM_L2);
            std::vector<std::vector<cv::DMatch>> forward, reverse;
            matcher.knnMatch(bd,ad,forward,2); matcher.knnMatch(ad,bd,reverse,2);
            std::vector<cv::Point2f> from,to;
            for(auto &v:forward) if(v.size()==2 && v[0].distance<.72*v[1].distance) {
                auto &back=reverse[v[0].trainIdx];
                if(back.size()==2 && back[0].trainIdx==v[0].queryIdx && back[0].distance<.72*back[1].distance) {
                    from.push_back(bk[v[0].queryIdx].pt); to.push_back(ak[v[0].trainIdx].pt);
                }
            }
            NSDictionary *result=Fit(from,to,b.size(),a.size(),pass==0?@"ORB/RANSAC":@"SIFT/RANSAC");
            if([result[@"valid"] boolValue]) return result;
        }
        return Failure(@"背景を自動で合わせられません。手動補正を使ってください");
    } catch (const cv::Exception &) { return Failure(@"背景解析に失敗しました"); }
#endif
}
- (NSDictionary *)trackFrom:(CGImageRef)previous to:(CGImageRef)current previousMask:(CGImageRef)previousMask currentMask:(CGImageRef)currentMask {
#if TARGET_OS_SIMULATOR
    return @{@"valid":@NO,@"reason":@"自動追跡は実機で利用できます"};
#else
    try {
        cv::Mat a=Gray(previous), b=Gray(current); if(a.empty()||b.empty()||a.size()!=b.size()) return Failure(@"追跡画像のサイズが不一致です");
        cv::Mat am=Background(previousMask,a.size()), bm=Background(currentMask,b.size());
        std::vector<cv::Point2f> points,next,back; cv::goodFeaturesToTrack(a,points,600,.01,8,am);
        if(points.size()<12) return Failure(@"追跡点が不足しています");
        std::vector<uchar> status,rs; std::vector<float> errors,re;
        cv::calcOpticalFlowPyrLK(a,b,points,next,status,errors);
        cv::calcOpticalFlowPyrLK(b,a,next,back,rs,re);
        std::vector<cv::Point2f> from,to;
        for(size_t i=0;i<points.size();i++) {
            cv::Point2f p=next[i];
            if(status[i]&&rs[i]&&errors[i]<24&&cv::norm(points[i]-back[i])<1.0&&p.x>=0&&p.y>=0&&p.x<b.cols&&p.y<b.rows&&bm.at<uchar>((int)p.y,(int)p.x)) { from.push_back(points[i]); to.push_back(p); }
        }
        return Fit(from,to,a.size(),b.size(),@"LK/RANSAC");
    } catch(const cv::Exception &) { return Failure(@"背景追跡が途切れました"); }
#endif
}
+ (NSArray<NSNumber *> *)matrixFromPoints:(NSArray<NSValue *> *)subPoints toPoints:(NSArray<NSValue *> *)mainPoints {
    if(subPoints.count!=4||mainPoints.count!=4) return nil;
    // Solve the eight DLT equations with partial pivoting. Also available on Simulator.
    double a[8][9]={0};
    for(int i=0;i<4;i++) {
        CGPoint s=subPoints[i].CGPointValue,m=mainPoints[i].CGPointValue;
        if(!isfinite(s.x)||!isfinite(s.y)||!isfinite(m.x)||!isfinite(m.y)) return nil;
        double x=s.x,y=s.y,u=m.x,v=m.y;
        double r0[]={x,y,1,0,0,0,-u*x,-u*y,u},r1[]={0,0,0,x,y,1,-v*x,-v*y,v};
        for(int j=0;j<9;j++) { a[i*2][j]=r0[j]; a[i*2+1][j]=r1[j]; }
    }
    for(int c=0;c<8;c++) {
        int pivot=c; for(int r=c+1;r<8;r++) if(fabs(a[r][c])>fabs(a[pivot][c])) pivot=r;
        if(fabs(a[pivot][c])<1e-7) return nil;
        for(int j=c;j<9;j++) { double tmp=a[c][j]; a[c][j]=a[pivot][j]; a[pivot][j]=tmp; }
        double d=a[c][c]; for(int j=c;j<9;j++) a[c][j]/=d;
        for(int r=0;r<8;r++) if(r!=c) { double f=a[r][c]; for(int j=c;j<9;j++) a[r][j]-=f*a[c][j]; }
    }
    simd_double3x3 m=matrix_identity_double3x3;
    for(int i=0;i<8;i++) m.columns[i%3][i/3]=a[i][8];
    if(!MTJOverlayMatrixIsValid(m)) return nil;
    CGPoint projected[4]; double sign=0,area=0;
    CGPoint corners[]={{0,0},{1,0},{1,1},{0,1}};
    for(int i=0;i<4;i++) { projected[i]=MTJOverlayProject(m,corners[i]); if(!isfinite(projected[i].x)||!isfinite(projected[i].y)||fabs(projected[i].x)>20||fabs(projected[i].y)>20) return nil; }
    for(int i=0;i<4;i++) {
        CGPoint p=projected[i],q=projected[(i+1)%4],r=projected[(i+2)%4];
        double cross=(q.x-p.x)*(r.y-q.y)-(q.y-p.y)*(r.x-q.x);
        if(fabs(cross)<1e-7||(sign&&cross*sign<0)) return nil; sign=cross; area+=p.x*q.y-q.x*p.y;
    }
    if(fabs(area)<.02) return nil;
    return MTJOverlayMatrixArray(m);
}
@end
