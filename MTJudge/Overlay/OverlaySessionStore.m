#import "OverlaySessionStore.h"
#import <CommonCrypto/CommonDigest.h>
#import "OverlayRegistration.h"

static BOOL OverlayFiniteNumber(id n) { return [n isKindOfClass:NSNumber.class] && isfinite([n doubleValue]); }
static BOOL OverlayValidMatrix(id values) {
    if(![values isKindOfClass:NSArray.class] || [values count]!=9) return NO;
    simd_double3x3 m=matrix_identity_double3x3;
    for(int i=0;i<9;i++) { if(!OverlayFiniteNumber(values[i])) return NO; m.columns[i%3][i/3]=[values[i] doubleValue]; }
    return MTJOverlayMatrixIsValid(m);
}
static BOOL OverlayValidPoints(id points) {
    if(![points isKindOfClass:NSArray.class]) return NO;
    for(id p in points) if(![p isKindOfClass:NSArray.class]||[p count]!=2||!OverlayFiniteNumber(p[0])||!OverlayFiniteNumber(p[1])) return NO;
    return YES;
}

static NSString *OverlayDigest(NSData *data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
    NSMutableString *s=[NSMutableString string]; for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++) [s appendFormat:@"%02x",digest[i]]; return s;
}
static NSString *OverlayFileDigest(NSURL *url, NSError **error) {
    NSInputStream *stream=[NSInputStream inputStreamWithURL:url]; [stream open];
    CC_SHA256_CTX ctx; CC_SHA256_Init(&ctx); uint8_t bytes[65536]; NSInteger n;
    while((n=[stream read:bytes maxLength:sizeof(bytes)])>0) CC_SHA256_Update(&ctx,bytes,(CC_LONG)n);
    NSError *failure=stream.streamError; [stream close];
    if(n<0) { if(error) *error=failure; return nil; }
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256_Final(digest,&ctx);
    NSMutableString *s=[NSMutableString string]; for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++) [s appendFormat:@"%02x",digest[i]]; return s;
}
@implementation OverlaySessionStore
- (instancetype)initWithMainURL:(NSURL *)mainURL subURL:(NSURL *)subURL error:(NSError **)error {
    if((self=[super init])) {
        NSString *m=OverlayFileDigest(mainURL,error), *s=m?OverlayFileDigest(subURL,error):nil; if(!m||!s) return nil;
        NSString *key=OverlayDigest([[NSString stringWithFormat:@"%@/%@",m,s] dataUsingEncoding:NSUTF8StringEncoding]);
        _sources=@{@"main":@{@"sha256":m,@"filename":mainURL.lastPathComponent},@"sub":@{@"sha256":s,@"filename":subURL.lastPathComponent}};
        NSFileManager *fm=NSFileManager.defaultManager;
        _directory=[[[fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"OverlaySessions"] URLByAppendingPathComponent:key];
        _cacheDirectory=[[[fm URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"MTJOverlay"] URLByAppendingPathComponent:key];
        if(![fm createDirectoryAtURL:_directory withIntermediateDirectories:YES attributes:nil error:error] || ![fm createDirectoryAtURL:_cacheDirectory withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    } return self;
}
- (NSDictionary *)load {
    NSData *d=[NSData dataWithContentsOfURL:[self.directory URLByAppendingPathComponent:@"session.json"]];
    id value=d?[NSJSONSerialization JSONObjectWithData:d options:0 error:nil]:nil;
    if(![value isKindOfClass:NSDictionary.class] || [value[@"schemaVersion"] integerValue]!=1) return nil;
    if(![value[@"sources"] isKindOfClass:NSDictionary.class]||![value[@"sources"][@"main"] isKindOfClass:NSDictionary.class]||![value[@"sources"][@"sub"] isKindOfClass:NSDictionary.class]) return nil;
    for(NSString *key in @[@"mainAnchor",@"subAnchor",@"mainTime",@"opacity",@"speed"]) if(!OverlayFiniteNumber(value[key])) return nil;
    if(!OverlayValidMatrix(value[@"manualMatrix"])) return nil;
    if(!OverlayValidPoints(@[value[@"mainSubject"]?:@[],value[@"subSubject"]?:@[]])) return nil;
    if(![value[@"comparisonDrawings"] isKindOfClass:NSArray.class]||![value[@"frames"] isKindOfClass:NSArray.class]) return nil;
    for(id drawing in value[@"comparisonDrawings"]) if(![drawing isKindOfClass:NSDictionary.class]||!OverlayValidPoints(drawing[@"points"])||!OverlayFiniteNumber(drawing[@"start"])) return nil;
    if(value[@"courseAnchors"]) {
        if(![value[@"courseAnchors"] isKindOfClass:NSArray.class]) return nil;
        double pm=-1,ps=-1;
        for(id anchor in value[@"courseAnchors"]) {
            if(![anchor isKindOfClass:NSDictionary.class]||!OverlayFiniteNumber(anchor[@"mainTime"])||!OverlayFiniteNumber(anchor[@"subTime"])) return nil;
            double m=[anchor[@"mainTime"] doubleValue],s=[anchor[@"subTime"] doubleValue];
            if(m<0||s<0||m<=pm||s<=ps) return nil; pm=m; ps=s;
        }
    }
    double previous=-DBL_MAX;
    for(id frame in value[@"frames"]) {
        if(![frame isKindOfClass:NSDictionary.class]||!OverlayFiniteNumber(frame[@"mainTime"])||!OverlayFiniteNumber(frame[@"subTime"])) return nil;
        if([frame[@"mainTime"] doubleValue]<previous) return nil; previous=[frame[@"mainTime"] doubleValue];
        if([frame[@"valid"] boolValue]&&!OverlayValidMatrix(frame[@"matrix"])) return nil;
        for(NSString *key in @[@"mainMask",@"subMask"]) if(frame[key] && (![frame[key] isKindOfClass:NSString.class]||[frame[key] isAbsolutePath]||[[frame[key] pathComponents] containsObject:@".."])) return nil;
        for(NSString *key in @[@"mainJoints",@"subJoints"]) if(frame[key]&&![frame[key] isKindOfClass:NSDictionary.class]) return nil;
    }
    if(![value[@"sources"][@"main"][@"sha256"] isEqual:self.sources[@"main"][@"sha256"]] || ![value[@"sources"][@"sub"][@"sha256"] isEqual:self.sources[@"sub"][@"sha256"]]) return nil;
    return value;
}
- (BOOL)save:(NSDictionary *)state error:(NSError **)error {
    NSMutableDictionary *value=[state mutableCopy]; value[@"schemaVersion"]=@1; value[@"sources"]=self.sources;
    value[@"engine"]=@"OpenCV-4.12.0-ORB-SIFT-LK-Vision-v3";
    value[@"coordinateSystem"]=@"oriented normalized top-left; row-major SUB->MAIN; final=manual*auto";
    value[@"updatedAt"]=[[NSISO8601DateFormatter new] stringFromDate:NSDate.date];
    NSData *d=[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted error:error];
    return d && [d writeToURL:[self.directory URLByAppendingPathComponent:@"session.json"] options:NSDataWritingAtomic error:error];
}
@end
