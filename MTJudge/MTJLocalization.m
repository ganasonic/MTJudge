#import "MTJLocalization.h"
#import <objc/runtime.h>

NSString *const MTJLanguageDidChangeNotification = @"MTJLanguageDidChange";
static NSDictionary *catalog;
static NSDictionary *bundledCatalog;
static NSMutableDictionary *sourceKeys;
static NSUInteger languageRevision;
static const void *MTJPickerRevision = &MTJPickerRevision;
static const void *MTJLocalizedProperties = &MTJLocalizedProperties;

static NSDictionary *ReadCatalog(NSURL *url, NSError **error) {
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
    if (!data) return nil;
    id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (!value) return nil;
    BOOL valid = [value isKindOfClass:NSDictionary.class];
    if (valid) for (NSString *language in @[@"ja", @"en"]) {
        id strings = value[language];
        if (![strings isKindOfClass:NSDictionary.class]) { valid = NO; break; }
        for (id key in strings) {
            if (![key isKindOfClass:NSString.class] || ![strings[key] isKindOfClass:NSString.class]) { valid = NO; break; }
        }
    }
    if (!valid) {
        if (error) *error = [NSError errorWithDomain:@"MTJLocalization" code:1 userInfo:@{NSLocalizedDescriptionKey:@"JSON requires ja and en objects containing string keys and values."}];
        return nil;
    }
    return value;
}

static NSArray *FormatTokens(NSString *text) {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"%(?:[0-9]+\\$)?[-+ #0]*[0-9]*(?:\\.[0-9]+)?(?:hh|ll|h|l|z|t|j|L)?[@diuoxXfFeEgGaAcCsSpn%]" options:0 error:nil];
    NSMutableArray *tokens = [NSMutableArray array];
    for (NSTextCheckingResult *match in [regex matchesInString:text options:0 range:NSMakeRange(0,text.length)]) [tokens addObject:[text substringWithRange:match.range]];
    return tokens;
}

static BOOL ValidateFormats(NSDictionary *value, NSError **error) {
    for (NSString *language in @[@"ja", @"en"]) for (NSString *key in value[language]) {
        // Format arguments must keep their types and order to remain safe in stringWithFormat:.
        if (![FormatTokens(key) isEqual:FormatTokens(value[language][key])] || [[key componentsSeparatedByString:@"%"] count] != [[value[language][key] componentsSeparatedByString:@"%"] count]) {
            if (error) *error = [NSError errorWithDomain:@"MTJLocalization" code:2 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Format placeholders differ: %@ / %@", language, key]}];
            return NO;
        }
    }
    return YES;
}

// Three-way update: new bundled defaults replace untouched old defaults;
// intentional edits made on the device stay in place.
static NSDictionary *MergeUpdatedCatalog(NSDictionary *bundle, NSDictionary *local, NSDictionary *previousBundle) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *language in @[@"ja", @"en"]) {
        NSMutableDictionary *strings = [bundle[language] mutableCopy];
        for (NSString *key in local[language]) {
            NSString *localValue = local[language][key];
            NSString *oldDefault = previousBundle[language][key];
            BOOL edited = previousBundle && ![localValue isEqual:oldDefault];
            // Older versions had no baseline and copied every default into Documents.
            // Prefer the current bundle for those collisions; keep a complete backup.
            if (edited || !bundle[language][key]) strings[key] = localValue;
        }
        result[language] = strings;
    }
    return result;
}
static BOOL WriteCatalog(NSDictionary *value, NSURL *url) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    return data && [data writeToURL:url options:NSDataWritingAtomic error:nil];
}
static NSDictionary *SynchronizeEditableCatalog(NSDictionary *bundle, NSURL *editable, NSURL *baselineURL) {
    NSDictionary *local = ReadCatalog(editable, nil);
    if (local && !ValidateFormats(local, nil)) local = nil;
    NSDictionary *previous = ReadCatalog(baselineURL, nil);
    if (previous && [previous isEqual:bundle] && local) return local;
    NSData *originalData = [NSData dataWithContentsOfURL:editable];
    if (originalData && ![local isEqual:bundle]) {
        NSString *name = [NSString stringWithFormat:@"MTJLanguages-before-update-%@.json", NSUUID.UUID.UUIDString];
        NSURL *backup = [[editable URLByDeletingLastPathComponent] URLByAppendingPathComponent:name];
        if (![originalData writeToURL:backup options:NSDataWritingAtomic error:nil]) {
            // Never overwrite a user's file if its backup could not be saved.
            return bundle;
        }
    }
    NSDictionary *updated = MergeUpdatedCatalog(bundle, local, previous);
    if (WriteCatalog(updated, editable)) WriteCatalog(bundle, baselineURL);
    return updated;
}

static void EnsureCatalog(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        bundledCatalog = ReadCatalog([NSBundle.mainBundle URLForResource:@"MTJLanguages" withExtension:@"json"], nil) ?: @{@"ja":@{}, @"en":@{}};
        catalog = bundledCatalog;
        sourceKeys = [NSMutableDictionary dictionary];
        for (NSString *language in @[@"ja", @"en"]) for (NSString *key in bundledCatalog[language]) {
            sourceKeys[key] = key;
            sourceKeys[bundledCatalog[language][key]] = key;
        }
        NSURL *support = [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"MTJLocalization" isDirectory:YES];
        [NSFileManager.defaultManager createDirectoryAtURL:support withIntermediateDirectories:YES attributes:nil error:nil];
        NSURL *baseline = [support URLByAppendingPathComponent:@"BundledLanguages.json"];
        catalog = SynchronizeEditableCatalog(bundledCatalog, [MTJLocalization editableURL], baseline);
        for (NSString *language in @[@"ja", @"en"]) for (NSString *key in catalog[language]) {
            sourceKeys[catalog[language][key]] = key;
        }
        // Literal source keys always win over an alias with the same spelling.
        for (NSString *language in @[@"ja", @"en"]) for (NSString *key in catalog[language]) sourceKeys[key] = key;
    });
}

NSString *MTJText(NSString *source) {
    if (!source) return nil;
    EnsureCatalog();
    return catalog[[MTJLocalization language]][source] ?: source;
}

// Remember the source only while the displayed value still matches the last translation.
// Changing a score/status replaces the binding; editable text and user data are never translated.
static NSString *LocalizedProperty(id object, NSString *property, NSString *current) {
    if (!current.length) return current;
    EnsureCatalog();
    if ([current rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location == NSNotFound) return current;
    NSMutableDictionary *properties = objc_getAssociatedObject(object, MTJLocalizedProperties);
    if (!properties) { properties = [NSMutableDictionary dictionary]; objc_setAssociatedObject(object, MTJLocalizedProperties, properties, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    NSArray *previous = properties[property];
    NSString *key = previous && [previous[1] isEqual:current] ? previous[0] : sourceKeys[current];
    if (!key) { [properties removeObjectForKey:property]; return current; }
    NSString *translated = MTJText(key);
    properties[property] = @[key, translated];
    return translated;
}
void MTJLocalizeView(UIView *view) {
    if ([view isKindOfClass:UITextField.class] || [view isKindOfClass:UITextView.class]) return;
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        NSString *text = LocalizedProperty(label, @"text", label.text);
        if (![text isEqual:label.text]) label.text = text;
        if (label.text.length && (sourceKeys[label.text] || objc_getAssociatedObject(label, MTJLocalizedProperties)[@"text"])) {
            label.adjustsFontSizeToFitWidth = YES; label.minimumScaleFactor = 0.55;
        }
    }
    if ([view isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)view;
        if (button.configuration.title.length) {
            NSString *title = LocalizedProperty(button, @"configuration", button.configuration.title);
            if (![title isEqual:button.configuration.title]) { UIButtonConfiguration *config = [button.configuration copy]; config.title = title; button.configuration = config; }
        } else if ([button attributedTitleForState:UIControlStateNormal].length) {
            NSAttributedString *current = [button attributedTitleForState:UIControlStateNormal];
            NSString *title = LocalizedProperty(button, @"attributedTitle", current.string);
            if (![title isEqual:current.string]) {
                NSDictionary *attributes = [current attributesAtIndex:0 effectiveRange:NULL];
                [button setAttributedTitle:[[NSAttributedString alloc] initWithString:title attributes:attributes] forState:UIControlStateNormal];
            }
        } else {
            NSString *title = LocalizedProperty(button, @"title", [button titleForState:UIControlStateNormal]);
            if (title && ![title isEqual:[button titleForState:UIControlStateNormal]]) [button setTitle:title forState:UIControlStateNormal];
        }
        NSString *accessibility = LocalizedProperty(button, @"accessibilityLabel", button.accessibilityLabel);
        if (accessibility && ![accessibility isEqual:button.accessibilityLabel]) button.accessibilityLabel = accessibility;
        return; // UIKit owns the internal title label.
    }
    if ([view isKindOfClass:UIPickerView.class]) {
        NSNumber *revision = objc_getAssociatedObject(view, MTJPickerRevision);
        if (!revision || revision.unsignedIntegerValue != languageRevision) {
            objc_setAssociatedObject(view, MTJPickerRevision, @(languageRevision), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [(UIPickerView *)view reloadAllComponents];
        }
        return;
    }
    if ([view isKindOfClass:UISegmentedControl.class]) {
        UISegmentedControl *segments = (UISegmentedControl *)view;
        for (NSInteger i = 0; i < segments.numberOfSegments; i++) {
            NSString *current = [segments titleForSegmentAtIndex:i];
            NSString *translated = LocalizedProperty(segments, [NSString stringWithFormat:@"segment%ld", (long)i], current);
            if (translated && ![translated isEqual:current]) [segments setTitle:translated forSegmentAtIndex:i];
        }
        return;
    }
    for (UIView *child in view.subviews) MTJLocalizeView(child);
}
void MTJLocalizeController(UIViewController *controller) {
    if (!controller) return;
    NSString *title = LocalizedProperty(controller.tabBarItem, @"title", controller.tabBarItem.title);
    if (title && ![title isEqual:controller.tabBarItem.title]) controller.tabBarItem.title = title;
    if (controller.isViewLoaded) { MTJLocalizeView(controller.view); [controller.view setNeedsLayout]; }
    for (UIViewController *child in controller.childViewControllers) MTJLocalizeController(child);
}

@implementation MTJLocalization
+ (NSString *)language {
    NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:@"MTJLanguage"];
    if ([saved isEqual:@"ja"] || [saved isEqual:@"en"]) return saved;
    return @"en";
}
+ (NSURL *)editableURL {
    return [[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"MTJLanguages.json"];
}
+ (void)refreshScreens {
    languageRevision++;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) if ([scene isKindOfClass:UIWindowScene.class]) for (UIWindow *window in ((UIWindowScene *)scene).windows) MTJLocalizeController(window.rootViewController);
    [NSNotificationCenter.defaultCenter postNotificationName:MTJLanguageDidChangeNotification object:nil];
}
+ (void)setLanguage:(NSString *)language {
    if (![@[@"ja", @"en"] containsObject:language]) return;
    [NSUserDefaults.standardUserDefaults setObject:language forKey:@"MTJLanguage"];
    [self refreshScreens];
}
+ (BOOL)reload:(NSError **)error {
    EnsureCatalog();
    NSDictionary *custom = ReadCatalog(self.editableURL, error);
    if (!custom || !ValidateFormats(custom,error)) return NO;
    NSMutableDictionary *merged = [NSMutableDictionary dictionary];
    for (NSString *language in @[@"ja", @"en"]) { NSMutableDictionary *strings = [bundledCatalog[language] mutableCopy]; [strings addEntriesFromDictionary:custom[language]]; merged[language] = strings; }
    catalog = merged;
    for (NSString *language in @[@"ja", @"en"]) for (NSString *key in custom[language]) { sourceKeys[key] = key; sourceKeys[custom[language][key]] = key; }
    [self refreshScreens];
    return YES;
}
+ (BOOL)importURL:(NSURL *)url error:(NSError **)error {
    EnsureCatalog();
    NSDictionary *custom = ReadCatalog(url,error);
    if (!custom || !ValidateFormats(custom,error)) return NO;
    NSData *data = [NSJSONSerialization dataWithJSONObject:custom options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:error];
    if (!data || ![data writeToURL:self.editableURL options:NSDataWritingAtomic error:error]) return NO;
    return [self reload:error];
}
@end
