#import <AppKit/AppKit.h>
#import <Accessibility/Accessibility.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Foundation/Foundation.h>
#import <errno.h>
#import <fcntl.h>
#import <unistd.h>

static const NSInteger MaxTraversalDepth = 40;
static const NSInteger MaxVisitedElements = 30000;
static const NSTimeInterval MenuTimeout = 4.0;
static const NSTimeInterval VerificationTimeout = 2.0;
static const NSTimeInterval BurstHoldThreshold = 0.30;
static const NSTimeInterval BurstDurationLimit = 5.0;
static const NSInteger BurstDefaultRate = 7;
static const NSInteger BurstMaximumRate = 10;
static const NSInteger BurstMaximumAttempts = 50;
static CFStringRef const AXScrollToVisibleAction = CFSTR("AXScrollToVisible");

@interface AXNode : NSObject
@property(nonatomic, strong) id elementObject;
@property(nonatomic) pid_t pid;
@property(nonatomic, copy) NSString *processName;
@property(nonatomic, copy) NSString *windowTitle;
@property(nonatomic, copy) NSString *role;
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *nodeDescription;
@property(nonatomic, copy) NSString *helpText;
@property(nonatomic, copy) NSString *customDescription;
@property(nonatomic, copy) NSString *value;
@property(nonatomic, copy) NSArray<NSString *> *actions;
@property(nonatomic) NSInteger depth;
@property(nonatomic) BOOL focusedWindow;
@property(nonatomic) BOOL selected;
@property(nonatomic) BOOL meetingReactionPicker;
- (AXUIElementRef)element;
- (NSString *)searchableText;
- (NSString *)displayText;
- (BOOL)canPress;
@end

@implementation AXNode
- (AXUIElementRef)element {
    return (__bridge AXUIElementRef)self.elementObject;
}
- (NSString *)searchableText {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *part in @[self.identifier, self.title, self.nodeDescription, self.helpText, self.customDescription ?: @"", self.value]) {
        if (part.length > 0) [parts addObject:part];
    }
    return [[parts componentsJoinedByString:@" | "] lowercaseString];
}
- (NSString *)displayText {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *part in @[self.title, self.nodeDescription, self.helpText, self.customDescription ?: @"", self.value, self.identifier]) {
        if (part.length > 0) [parts addObject:part];
    }
    return parts.count == 0 ? @"<no accessible label>" : [parts componentsJoinedByString:@" | "];
}
- (BOOL)canPress {
    return [self.actions containsObject:(__bridge NSString *)kAXPressAction]
        || [self.actions containsObject:(__bridge NSString *)kAXShowMenuAction];
}
@end

static NSDictionary<NSString *, NSDictionary *> *ReactionDefinitions(void) {
    static NSDictionary *values;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ values = @{
        @"like": @{@"name": @"Like", @"labels": @[@"like", @"thumbs up", @"thumb up", @"vind ik leuk", @"duim omhoog", @"gefällt mir", @"j'aime", @"me gusta"]},
        @"love": @{@"name": @"Love", @"labels": @[@"love", @"heart", @"hart", @"liebe", @"coeur", @"cœur", @"corazón", @"corazon"]},
        @"applause": @{@"name": @"Applause", @"labels": @[@"applause", @"clap", @"clapping", @"applaus", @"applaudissements", @"aplausos"]},
        @"laugh": @{@"name": @"Laugh", @"labels": @[@"laugh", @"laughing", @"lachen", @"rire", @"risa"]},
        @"surprise": @{@"name": @"Surprise", @"labels": @[@"surprise", @"surprised", @"wow", @"verrast", @"überrascht", @"surpris", @"sorpresa"]}
    }; });
    return values;
}

static NSArray<NSString *> *LauncherLabels(void) {
    static NSArray<NSString *> *values;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ values = @[@"react", @"reaction", @"reactions", @"reageren", @"reactie", @"reacties", @"réagir", @"réaction", @"réactions", @"reagieren", @"reaktion", @"reaktionen", @"reaccionar", @"reacción", @"reacciones"]; });
    return values;
}

static NSArray<NSString *> *MuteLabels(void) {
    static NSArray<NSString *> *values;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ values = @[@"mute", @"mute mic", @"mute microphone", @"dempen", @"microfoon dempen", @"stummschalten", @"mikrofon stummschalten", @"désactiver le micro", @"silenciar", @"silenciar micrófono"]; });
    return values;
}

static NSArray<NSString *> *UnmuteLabels(void) {
    static NSArray<NSString *> *values;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ values = @[@"unmute", @"unmute mic", @"unmute microphone", @"dempen opheffen", @"microfoon inschakelen", @"stummschaltung aufheben", @"mikrofon einschalten", @"activer le micro", @"reactivar audio", @"activar micrófono"]; });
    return values;
}

static NSArray<NSString *> *CameraOffLabels(void) {
    static NSArray<NSString *> *values;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ values = @[@"turn camera off", @"stop video", @"camera uitschakelen", @"video stoppen", @"kamera ausschalten", @"désactiver la caméra", @"desactivar la cámara"]; });
    return values;
}

static NSArray<NSString *> *CameraOnLabels(void) {
    static NSArray<NSString *> *values;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ values = @[@"turn camera on", @"start video", @"camera inschakelen", @"video starten", @"kamera einschalten", @"activer la caméra", @"activar la cámara"]; });
    return values;
}

static NSArray<NSString *> *RaiseHandLabels(void) {
    static NSArray<NSString *> *values;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ values = @[@"raise your hand", @"raise hand", @"hand opsteken", @"steek uw hand op", @"hand heben", @"lever la main", @"levantar la mano"]; });
    return values;
}

static NSArray<NSString *> *LowerHandLabels(void) {
    static NSArray<NSString *> *values;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ values = @[@"lower your hand", @"lower hand", @"hand omlaag", @"uw hand omlaag doen", @"hand senken", @"baisser la main", @"bajar la mano"]; });
    return values;
}

static NSArray<NSString *> *LeaveLabels(void) {
    static NSArray<NSString *> *values;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ values = @[@"leave", @"leave call", @"hang up", @"verlaten", @"gesprek verlaten", @"auflegen", @"besprechung verlassen", @"quitter", @"quitter l'appel", @"salir", @"salir de la llamada"]; });
    return values;
}

static NSArray<NSString *> *EffectsLauncherLabels(void) {
    static NSArray<NSString *> *values;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ values = @[@"open video options", @"video effects and settings", @"backgrounds and effects", @"effects and avatars", @"video effects", @"achtergronden en effecten", @"video-effecten", @"hintergründe und effekte", @"effets vidéo", @"arrière-plans et effets", @"fondos y efectos", @"efectos de vídeo"]; });
    return values;
}

static NSArray<NSString *> *BlurLabels(void) {
    static NSArray<NSString *> *values;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ values = @[@"blur", @"standard blur", @"background blur", @"vervagen", @"achtergrond vervagen", @"weichzeichnen", @"hintergrund weichzeichnen", @"flou", @"flouter l’arrière-plan", @"desenfocar", @"desenfocar fondo"]; });
    return values;
}

static NSArray<NSString *> *NoEffectLabels(void) {
    static NSArray<NSString *> *values;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ values = @[@"none", @"no effect", @"no background", @"no background effect", @"geen", @"geen effect", @"zonder achtergrond", @"keine", @"kein effekt", @"aucun", @"aucun effet", @"ninguno", @"sin efecto"]; });
    return values;
}

static NSArray<NSString *> *ApplyLabels(void) {
    static NSArray<NSString *> *values;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ values = @[@"apply", @"apply and turn on video", @"toepassen", @"toepassen en video inschakelen", @"anwenden", @"appliquer", @"aplicar"]; });
    return values;
}

static void PrintUsage(const char *executablePath) {
    NSString *executable = [[NSString stringWithUTF8String:executablePath] lastPathComponent];
    printf("Microsoft Teams meeting controls for Stream Deck\n\n");
    printf("Usage:\n");
    printf("  %s status|serve\n", executable.UTF8String);
    printf("  %s inspect-controls\n", executable.UTF8String);
    printf("  %s mute|unmute|camera-on|camera-off\n", executable.UTF8String);
    printf("  %s blur-on|blur-off|hand-raise|hand-lower|leave\n", executable.UTF8String);
    printf("  %s react like|love|applause|laugh|surprise\n", executable.UTF8String);
    printf("  %s burst like|love|applause|laugh|surprise [rate]\n", executable.UTF8String);
    printf("  %s inspect\n\n", executable.UTF8String);
    printf("Burst rate defaults to %ld and is capped at %ld attempts per second.\n", (long)BurstDefaultRate, (long)BurstMaximumRate);
    printf("inspect and inspect-controls do not press anything.\n");
}

static id CopyAttribute(AXUIElementRef element, CFStringRef attribute) {
    CFTypeRef value = NULL;
    if (AXUIElementCopyAttributeValue(element, attribute, &value) != kAXErrorSuccess || value == NULL) return nil;
    return CFBridgingRelease(value);
}

static NSString *CustomDescription(id content) {
    if ([content isKindOfClass:NSData.class]) {
        @try {
            NSSet *classes = [NSSet setWithArray:@[NSArray.class, AXCustomContent.class, NSAttributedString.class, NSDictionary.class, NSString.class, NSNumber.class]];
            content = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:content error:NULL];
        } @catch (NSException *exception) {
            return @"";
        }
    }
    if (![content isKindOfClass:NSArray.class]) return @"";
    for (id item in content) {
        if (![item isKindOfClass:AXCustomContent.class]) continue;
        AXCustomContent *entry = item;
        if ([entry.label isEqualToString:@"description"] && entry.value.length > 0) return entry.value;
    }
    return @"";
}

// One IPC request per element replaces individual requests for each property.
static NSArray<NSString *> *NodeAttributeNames(void) {
    static NSArray<NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @[(__bridge NSString *)kAXRoleAttribute, (__bridge NSString *)kAXIdentifierAttribute,
            @"AXDOMIdentifier", (__bridge NSString *)kAXTitleAttribute, (__bridge NSString *)kAXDescriptionAttribute,
            (__bridge NSString *)kAXHelpAttribute, @"AXCustomContent", (__bridge NSString *)kAXValueAttribute,
            (__bridge NSString *)kAXSelectedAttribute, (__bridge NSString *)kAXChildrenAttribute];
    });
    return names;
}

static NSDictionary *AttributeDictionary(NSArray<NSString *> *names, NSArray *values) {
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    for (NSUInteger index = 0; index < MIN(names.count, values.count); index += 1) {
        id value = values[index];
        if (value == NSNull.null) continue;
        if (CFGetTypeID((__bridge CFTypeRef)value) == AXValueGetTypeID()
            && AXValueGetType((__bridge AXValueRef)value) == kAXValueAXErrorType) continue;
        attributes[names[index]] = value;
    }
    return attributes;
}

static NSDictionary *NodeAttributes(AXUIElementRef element) {
    NSArray *names = NodeAttributeNames();
    CFArrayRef values = NULL;
    AXError error = AXUIElementCopyMultipleAttributeValues(element, (__bridge CFArrayRef)names, 0, &values);
    if (error == kAXErrorSuccess && values) return AttributeDictionary(names, CFBridgingRelease(values));
    if (values) CFRelease(values);
    // Older Accessibility providers can lack multiple-attribute support.
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    if (error != kAXErrorNotImplemented && error != kAXErrorAttributeUnsupported) return attributes;
    for (NSString *name in names) {
        id value = CopyAttribute(element, (__bridge CFStringRef)name);
        if (value) attributes[name] = value;
    }
    return attributes;
}

static NSString *AttributeString(id value) {
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) return [value stringValue];
    return @"";
}

static BOOL AttributeBoolean(id value) {
    if ([value isKindOfClass:NSNumber.class]) return [value boolValue];
    if (![value isKindOfClass:NSString.class]) return NO;
    return [@[@"true", @"selected", @"on", @"1"] containsObject:[value lowercaseString]];
}

static void PopulateNode(AXNode *node, NSDictionary *attributes) {
    node.role = AttributeString(attributes[(__bridge NSString *)kAXRoleAttribute]);
    node.identifier = AttributeString(attributes[(__bridge NSString *)kAXIdentifierAttribute]);
    if (node.identifier.length == 0) node.identifier = AttributeString(attributes[@"AXDOMIdentifier"]);
    node.title = AttributeString(attributes[(__bridge NSString *)kAXTitleAttribute]);
    node.nodeDescription = AttributeString(attributes[(__bridge NSString *)kAXDescriptionAttribute]);
    node.helpText = AttributeString(attributes[(__bridge NSString *)kAXHelpAttribute]);
    node.customDescription = CustomDescription(attributes[@"AXCustomContent"]);
    node.value = AttributeString(attributes[(__bridge NSString *)kAXValueAttribute]);
    node.selected = AttributeBoolean(attributes[(__bridge NSString *)kAXSelectedAttribute]);
}

static NSString *StringAttribute(AXUIElementRef element, CFStringRef attribute) {
    id value = CopyAttribute(element, attribute);
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) return [value stringValue];
    return @"";
}

static NSArray *ElementArrayAttribute(AXUIElementRef element, CFStringRef attribute) {
    id value = CopyAttribute(element, attribute);
    return [value isKindOfClass:NSArray.class] ? value : @[];
}

static NSArray<NSString *> *Actions(AXUIElementRef element) {
    CFArrayRef names = NULL;
    if (AXUIElementCopyActionNames(element, &names) != kAXErrorSuccess || names == NULL) return @[];
    return CFBridgingRelease(names);
}

static BOOL SameElement(AXUIElementRef left, AXUIElementRef right) {
    return left != NULL && right != NULL && CFEqual(left, right);
}

static NSArray<NSDictionary *> *CandidateApplications(void) {
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    NSMutableSet<NSNumber *> *seen = [NSMutableSet set];
    for (NSRunningApplication *application in NSWorkspace.sharedWorkspace.runningApplications) {
        NSString *bundleID = application.bundleIdentifier.lowercaseString ?: @"";
        BOOL isTeams = [bundleID isEqualToString:@"com.microsoft.teams2"]
            || [bundleID hasPrefix:@"com.microsoft.teams2."];
        if (!isTeams || application.processIdentifier <= 0) continue;
        NSNumber *pidNumber = @(application.processIdentifier);
        if ([seen containsObject:pidNumber]) continue;
        [seen addObject:pidNumber];
        AXUIElementRef root = AXUIElementCreateApplication(application.processIdentifier);
        [result addObject:@{@"pid": pidNumber, @"name": application.localizedName ?: @"Teams", @"root": CFBridgingRelease(root)}];
    }
    return result;
}

static void EncourageAccessibilityTree(AXUIElementRef application) {
    AXUIElementSetAttributeValue(application, CFSTR("AXManualAccessibility"), kCFBooleanTrue);
    AXUIElementSetAttributeValue(application, CFSTR("AXEnhancedUserInterface"), kCFBooleanTrue);
}

static void MarkMeetingReactionPicker(NSArray<AXNode *> *nodes);

// Keep traversal testable without needing a live Accessibility provider.
static void WalkElements(id root, NSArray *(^visit)(id element, NSInteger depth)) {
    NSMutableArray<NSDictionary *> *stack = [NSMutableArray arrayWithObject:@{@"element": root, @"depth": @0}];
    NSMutableSet *visited = [NSMutableSet set];
    while (stack.count > 0) {
        NSDictionary *entry = stack.lastObject;
        [stack removeLastObject];
        id element = entry[@"element"];
        NSInteger depth = [entry[@"depth"] integerValue];
        if (depth > MaxTraversalDepth || visited.count >= MaxVisitedElements) continue;
        // A hash is only a bucket hint. The set also compares element equality.
        id identity = element;
        if ([visited containsObject:identity]) continue;
        [visited addObject:identity];
        NSArray *children = visit(element, depth);
        for (id child in [children reverseObjectEnumerator]) {
            [stack addObject:@{@"element": child, @"depth": @(depth + 1)}];
        }
    }
}

static NSArray<AXNode *> *CollectElements(AXUIElementRef root, pid_t pid, NSString *processName, NSString *windowTitle, AXUIElementRef focusedWindow) {
    NSMutableArray<AXNode *> *result = [NSMutableArray array];
    WalkElements((__bridge id)root, ^NSArray *(id object, NSInteger depth) {
        AXUIElementRef element = (__bridge AXUIElementRef)object;
        AXNode *node = [AXNode new];
        node.elementObject = object;
        node.pid = pid;
        node.processName = processName;
        node.windowTitle = windowTitle;
        NSDictionary *attributes = NodeAttributes(element);
        PopulateNode(node, attributes);
        node.actions = Actions(element);
        node.depth = depth;
        node.focusedWindow = SameElement(focusedWindow, root);
        [result addObject:node];
        id children = attributes[(__bridge NSString *)kAXChildrenAttribute];
        if (![children isKindOfClass:NSArray.class]) return @[];
        NSMutableArray *elements = [NSMutableArray array];
        for (id child in children) {
            if (CFGetTypeID((__bridge CFTypeRef)child) == AXUIElementGetTypeID()) [elements addObject:child];
        }
        return elements;
    });
    MarkMeetingReactionPicker(result);
    return result;
}

static NSDictionary *ScanTeamsForPID(pid_t selectedPID) {
    NSArray<NSDictionary *> *applications = CandidateApplications();
    NSMutableArray<AXNode *> *allElements = [NSMutableArray array];
    NSInteger scannedApplications = 0;
    for (NSDictionary *application in applications) {
        pid_t pid = [application[@"pid"] intValue];
        if (selectedPID > 0 && pid != selectedPID) continue;
        scannedApplications += 1;
        NSString *name = application[@"name"];
        AXUIElementRef root = (__bridge AXUIElementRef)application[@"root"];
        EncourageAccessibilityTree(root);
        id focusedWindowObject = CopyAttribute(root, kAXFocusedWindowAttribute);
        AXUIElementRef focusedWindow = NULL;
        if (focusedWindowObject && CFGetTypeID((__bridge CFTypeRef)focusedWindowObject) == AXUIElementGetTypeID()) focusedWindow = (__bridge AXUIElementRef)focusedWindowObject;
        NSArray *windows = ElementArrayAttribute(root, kAXWindowsAttribute);
        if (windows.count == 0) {
            [allElements addObjectsFromArray:CollectElements(root, pid, name, @"<application root>", focusedWindow)];
            continue;
        }
        for (id windowObject in windows) {
            AXUIElementRef window = (__bridge AXUIElementRef)windowObject;
            NSString *windowTitle = StringAttribute(window, kAXTitleAttribute);
            [allElements addObjectsFromArray:CollectElements(window, pid, name, windowTitle.length > 0 ? windowTitle : @"<untitled window>", focusedWindow)];
        }
    }
    return @{@"applicationCount": @(selectedPID > 0 ? scannedApplications : applications.count), @"elements": allElements};
}

static NSDictionary *ScanTeams(void) {
    return ScanTeamsForPID(0);
}

static NSString *Normalized(NSString *text) {
    return [(text.lowercaseString ?: @"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BOOL EqualsAny(NSString *text, NSArray<NSString *> *labels) {
    NSString *normalized = Normalized(text);
    for (NSString *label in labels) if ([normalized isEqualToString:Normalized(label)]) return YES;
    return NO;
}

static BOOL ActionFieldMatches(NSString *field, NSArray<NSString *> *labels) {
    if (field.length == 0) return NO;
    NSString *normalized = Normalized(field);
    // The shared label tables are already lowercase and trimmed.
    for (NSString *label in labels) {
        if (![normalized hasPrefix:label]) continue;
        if (normalized.length == label.length) return YES;
        NSString *suffix = [normalized substringFromIndex:label.length];
        if ([suffix hasPrefix:@" ("] || [suffix hasPrefix:@", "] || [suffix hasPrefix:@" | "] || [suffix hasPrefix:@". "]) return YES;
    }
    return NO;
}

static BOOL NodeMatchesAction(AXNode *node, NSArray<NSString *> *labels) {
    for (NSString *field in @[node.title, node.nodeDescription, node.helpText, node.customDescription ?: @"", node.value]) {
        if (ActionFieldMatches(field, labels)) return YES;
    }
    return NO;
}

static BOOL HasUnsafeContext(AXNode *node) {
    NSString *text = node.searchableText;
    return [text containsString:@"message"] || [text containsString:@"chat"] || [text containsString:@"notification"] || [text containsString:@"device preview"] || [text containsString:@"pre-join"] || [text containsString:@"prejoin"];
}

static NSInteger BaseControlScore(AXNode *node) {
    if (!node.canPress) return NSIntegerMin;
    NSInteger score = 50;
    if ([node.role isEqualToString:(__bridge NSString *)kAXButtonRole]) score += 30;
    if (node.focusedWindow) score += 12;
    if (HasUnsafeContext(node)) score -= 180;
    return score - node.depth;
}

static NSInteger LauncherScore(AXNode *node) {
    // Recent-item menu titles can contain reaction words without being controls.
    if ([node.role isEqualToString:(__bridge NSString *)kAXMenuItemRole] || HasUnsafeContext(node)) return NSIntegerMin;
    if (!NodeMatchesAction(node, LauncherLabels())) return NSIntegerMin;
    NSInteger score = BaseControlScore(node);
    if (score == NSIntegerMin) return score;
    for (NSString *field in @[node.title, node.nodeDescription, node.helpText, node.customDescription ?: @"", node.value]) {
        if (EqualsAny(field, LauncherLabels())) { score += 80; break; }
    }
    if ([node.identifier.lowercaseString containsString:@"react"]) score += 30;
    return score;
}

static NSInteger ReactionScore(AXNode *node, NSDictionary *reaction) {
    NSArray<NSString *> *labels = reaction[@"labels"];
    // Shared meeting content can expose pressable reaction groups before the
    // picker opens. Wait for its actual buttons rather than accepting content.
    if (!node.meetingReactionPicker || ![node.role isEqualToString:(__bridge NSString *)kAXButtonRole]) return NSIntegerMin;
    if (![node.actions containsObject:(__bridge NSString *)kAXPressAction] || HasUnsafeContext(node)) return NSIntegerMin;
    if (!NodeMatchesAction(node, labels)) return NSIntegerMin;
    NSInteger score = BaseControlScore(node);
    if (score == NSIntegerMin) return score;
    for (NSString *label in labels) if ([node.searchableText isEqualToString:Normalized(label)]) score += 30;
    if ([node.identifier.lowercaseString containsString:[reaction[@"name"] lowercaseString]]) score += 20;
    return score;
}

static NSInteger MicrophoneScore(AXNode *node) {
    if (!node.canPress) return NSIntegerMin;
    if (!NodeMatchesAction(node, MuteLabels()) && !NodeMatchesAction(node, UnmuteLabels())) return NSIntegerMin;
    NSInteger score = BaseControlScore(node);
    if ([node.identifier.lowercaseString containsString:@"microphone"] || [node.identifier.lowercaseString containsString:@"mic-"]) score += 30;
    if ([node.searchableText containsString:@"settings"]) score -= 120;
    return score;
}

static NSInteger CameraScore(AXNode *node) {
    if (!node.canPress) return NSIntegerMin;
    if (!NodeMatchesAction(node, CameraOnLabels()) && !NodeMatchesAction(node, CameraOffLabels())) return NSIntegerMin;
    NSInteger score = BaseControlScore(node);
    if ([node.identifier.lowercaseString containsString:@"camera"] || [node.identifier.lowercaseString containsString:@"video"]) score += 30;
    if ([node.searchableText containsString:@"settings"] || [node.searchableText containsString:@"preview"]) score -= 120;
    return score;
}

// Recognize a meeting picker without relying on window titles or participant text.
static void MarkMeetingReactionPicker(NSArray<AXNode *> *nodes) {
    NSMutableSet<NSString *> *reactions = [NSMutableSet set];
    BOOL hasHand = NO;
    for (AXNode *node in nodes) {
        if (!node.canPress || HasUnsafeContext(node)) continue;
        if (NodeMatchesAction(node, RaiseHandLabels()) || NodeMatchesAction(node, LowerHandLabels())) hasHand = YES;
        for (NSString *key in ReactionDefinitions()) {
            if (NodeMatchesAction(node, ReactionDefinitions()[key][@"labels"])) [reactions addObject:key];
        }
    }
    if (!hasHand || reactions.count < 3) return;
    for (AXNode *node in nodes) node.meetingReactionPicker = YES;
}

static NSInteger HandScore(AXNode *node) {
    if (!node.canPress) return NSIntegerMin;
    if (!NodeMatchesAction(node, RaiseHandLabels()) && !NodeMatchesAction(node, LowerHandLabels())) return NSIntegerMin;
    NSInteger score = BaseControlScore(node);
    if ([node.identifier.lowercaseString containsString:@"hand"]) score += 30;
    return score;
}

static NSInteger LeaveScore(AXNode *node) {
    if (!node.canPress) return NSIntegerMin;
    NSString *text = node.searchableText;
    if ([text containsString:@"end meeting"] || [text containsString:@"for all"] || [text containsString:@"decline"] || [text containsString:@"dismiss"]) return NSIntegerMin;
    if (!NodeMatchesAction(node, LeaveLabels())) return NSIntegerMin;
    NSInteger score = BaseControlScore(node);
    if ([node.identifier.lowercaseString containsString:@"leave"] || [node.identifier.lowercaseString containsString:@"hangup"]) score += 35;
    return score;
}

static NSInteger EffectsLauncherScore(AXNode *node) {
    if (!node.canPress) return NSIntegerMin;
    if (!NodeMatchesAction(node, EffectsLauncherLabels())) return NSIntegerMin;
    NSInteger score = BaseControlScore(node);
    NSString *identifier = node.identifier.lowercaseString;
    if ([identifier containsString:@"effect"] || [identifier containsString:@"background"]) score += 35;
    return score;
}

static NSInteger BlurOptionScore(AXNode *node) {
    if (![node.actions containsObject:(__bridge NSString *)kAXPressAction]) return NSIntegerMin;
    if (!NodeMatchesAction(node, BlurLabels())) return NSIntegerMin;
    NSInteger score = BaseControlScore(node);
    NSString *identifier = node.identifier.lowercaseString;
    if ([identifier containsString:@"blur"] || [identifier containsString:@"effect"] || [identifier containsString:@"background"]) score += 35;
    if (node.selected) score += 15;
    return score;
}

static NSInteger NoEffectOptionScore(AXNode *node) {
    if (![node.actions containsObject:(__bridge NSString *)kAXPressAction]) return NSIntegerMin;
    if (!NodeMatchesAction(node, NoEffectLabels())) return NSIntegerMin;
    NSInteger score = BaseControlScore(node);
    NSString *identifier = node.identifier.lowercaseString;
    if ([identifier containsString:@"effect"] || [identifier containsString:@"background"] || [identifier containsString:@"none"]) score += 35;
    if (node.selected) score += 15;
    return score;
}

static NSInteger ApplyScore(AXNode *node) {
    if (!node.canPress) return NSIntegerMin;
    if (!NodeMatchesAction(node, ApplyLabels())) return NSIntegerMin;
    return BaseControlScore(node) + 20;
}

typedef NSInteger (^NodeScorer)(AXNode *node);

static AXNode *BestNode(NSArray<AXNode *> *nodes, NodeScorer scorer) {
    AXNode *best = nil;
    NSInteger bestScore = 0;
    for (AXNode *node in nodes) {
        NSInteger score = scorer(node);
        if (score > bestScore) { best = node; bestScore = score; }
    }
    return best;
}

static AXNode *BestUniqueNode(NSArray<AXNode *> *nodes, NodeScorer scorer, BOOL *ambiguous) {
    AXNode *best = nil;
    NSInteger bestScore = 0;
    NSInteger secondScore = 0;
    for (AXNode *node in nodes) {
        NSInteger score = scorer(node);
        if (score > bestScore) { secondScore = bestScore; best = node; bestScore = score; }
        else if (score > secondScore) secondScore = score;
    }
    BOOL tied = best != nil && secondScore > 0 && bestScore - secondScore <= 2;
    if (ambiguous) *ambiguous = tied;
    return tied ? nil : best;
}

static AXError ScrollNodeIntoView(AXNode *node) {
    if ([node.actions containsObject:(__bridge NSString *)AXScrollToVisibleAction]) return AXUIElementPerformAction(node.element, AXScrollToVisibleAction);
    return kAXErrorActionUnsupported;
}

static AXError PressNode(AXNode *node) {
    if ([node.actions containsObject:(__bridge NSString *)kAXPressAction]) return AXUIElementPerformAction(node.element, kAXPressAction);
    if ([node.actions containsObject:(__bridge NSString *)kAXShowMenuAction]) return AXUIElementPerformAction(node.element, kAXShowMenuAction);
    return kAXErrorActionUnsupported;
}

static NSString *AXErrorDescription(AXError error) {
    switch (error) {
        case kAXErrorSuccess: return @"success";
        case kAXErrorFailure: return @"generic failure";
        case kAXErrorIllegalArgument: return @"illegal argument";
        case kAXErrorInvalidUIElement: return @"the UI element disappeared";
        case kAXErrorInvalidUIElementObserver: return @"invalid observer";
        case kAXErrorCannotComplete: return @"Teams did not complete the action";
        case kAXErrorAttributeUnsupported: return @"attribute unsupported";
        case kAXErrorActionUnsupported: return @"the element does not support Press or ShowMenu";
        case kAXErrorNotificationUnsupported: return @"notification unsupported";
        case kAXErrorNotImplemented: return @"not implemented";
        case kAXErrorNotificationAlreadyRegistered: return @"notification already registered";
        case kAXErrorNotificationNotRegistered: return @"notification not registered";
        case kAXErrorAPIDisabled: return @"Accessibility API disabled or permission missing";
        case kAXErrorNoValue: return @"no value";
        case kAXErrorParameterizedAttributeUnsupported: return @"parameterized attribute unsupported";
        case kAXErrorNotEnoughPrecision: return @"not enough precision";
        default: return [NSString stringWithFormat:@"AX error %d", error];
    }
}

static BOOL RequireAccessibilityPermission(void) {
    NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
    if (AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options)) return YES;
    fprintf(stderr, "Accessibility permission is required. In System Settings under Privacy & Security > Accessibility, enable teams-reaction or Stream Deck, then restart Stream Deck.\n");
    return NO;
}

static NSString *MicrophoneStateForNode(AXNode *node) {
    if (NodeMatchesAction(node, MuteLabels())) return @"unmuted";
    if (NodeMatchesAction(node, UnmuteLabels())) return @"muted";
    return @"unknown";
}

static NSString *CameraStateForNode(AXNode *node) {
    if (NodeMatchesAction(node, CameraOffLabels())) return @"on";
    if (NodeMatchesAction(node, CameraOnLabels())) return @"off";
    return @"unknown";
}

static NSString *HandStateForNode(AXNode *node) {
    if (NodeMatchesAction(node, RaiseHandLabels())) return @"lowered";
    if (NodeMatchesAction(node, LowerHandLabels())) return @"raised";
    return @"unknown";
}

static NSString *HandStateFromLauncher(AXNode *launcher) {
    if (!launcher) return @"unavailable";
    NSString *description = Normalized(launcher.customDescription);
    if ([description containsString:@"your hand is not raised."]) return @"lowered";
    if ([description containsString:@"your hand is raised."]) return @"raised";
    return @"unavailable";
}

static NSDictionary *StateSnapshot(NSDictionary *scan) {
    NSArray<AXNode *> *elements = scan[@"elements"];
    BOOL micAmbiguous = NO, cameraAmbiguous = NO, handAmbiguous = NO;
    BOOL leaveAmbiguous = NO, launcherAmbiguous = NO, effectsAmbiguous = NO;
    AXNode *microphone = BestUniqueNode(elements, ^NSInteger(AXNode *node) { return MicrophoneScore(node); }, &micAmbiguous);
    AXNode *camera = BestUniqueNode(elements, ^NSInteger(AXNode *node) { return CameraScore(node); }, &cameraAmbiguous);
    AXNode *hand = BestUniqueNode(elements, ^NSInteger(AXNode *node) { return HandScore(node); }, &handAmbiguous);
    AXNode *leave = BestUniqueNode(elements, ^NSInteger(AXNode *node) { return LeaveScore(node); }, &leaveAmbiguous);
    AXNode *launcher = BestUniqueNode(elements, ^NSInteger(AXNode *node) { return LauncherScore(node); }, &launcherAmbiguous);
    AXNode *effects = BestUniqueNode(elements, ^NSInteger(AXNode *node) { return EffectsLauncherScore(node); }, &effectsAmbiguous);
    BOOL meetingActive = microphone || camera || hand || leave || launcher
        || micAmbiguous || cameraAmbiguous || handAmbiguous || leaveAmbiguous || launcherAmbiguous;
    NSString *microphoneState = !meetingActive ? @"unavailable" : (micAmbiguous ? @"unknown" : (microphone ? MicrophoneStateForNode(microphone) : @"unavailable"));
    NSString *cameraState = !meetingActive ? @"unavailable" : (cameraAmbiguous ? @"unknown" : (camera ? CameraStateForNode(camera) : @"unavailable"));
    NSString *handState = !meetingActive ? @"unavailable" : (handAmbiguous ? @"unknown" : (hand ? HandStateForNode(hand) : @"unavailable"));

    if ([handState isEqualToString:@"unavailable"] && !launcherAmbiguous) handState = HandStateFromLauncher(launcher);

    BOOL blurAmbiguous = NO, noneAmbiguous = NO;
    AXNode *blur = BestUniqueNode(elements, ^NSInteger(AXNode *node) { return BlurOptionScore(node); }, &blurAmbiguous);
    AXNode *none = BestUniqueNode(elements, ^NSInteger(AXNode *node) { return NoEffectOptionScore(node); }, &noneAmbiguous);
    NSString *blurState = @"unavailable";
    if (meetingActive && (effects || blur || none || effectsAmbiguous)) blurState = @"unknown";
    if (!blurAmbiguous && blur.selected) blurState = @"on";
    if (!noneAmbiguous && none.selected) blurState = @"off";
    return @{@"meetingActive": @(meetingActive), @"microphone": microphoneState, @"camera": cameraState, @"backgroundBlur": blurState, @"hand": handState};
}

static NSArray<AXNode *> *StateControlNodes(NSDictionary *scan) {
    NSMutableArray *controls = [NSMutableArray array];
    for (AXNode *node in scan[@"elements"]) {
        if (!node.canPress) continue;
        if (MicrophoneScore(node) > 0 || CameraScore(node) > 0 || HandScore(node) > 0
            || LauncherScore(node) > 0 || LeaveScore(node) > 0 || EffectsLauncherScore(node) > 0
            || BlurOptionScore(node) > 0 || NoEffectOptionScore(node) > 0) [controls addObject:node];
    }
    return controls;
}

static AXNode *RefreshNode(AXNode *node) {
    AXNode *fresh = [AXNode new];
    fresh.elementObject = node.elementObject;
    fresh.pid = node.pid;
    fresh.processName = node.processName;
    fresh.windowTitle = node.windowTitle;
    fresh.depth = node.depth;
    fresh.focusedWindow = node.focusedWindow;
    fresh.meetingReactionPicker = node.meetingReactionPicker;
    PopulateNode(fresh, NodeAttributes(node.element));
    fresh.actions = Actions(node.element);
    return fresh;
}

// Refresh every known state control, including ambiguous candidates. Missing or
// replaced elements produce unavailable state and force rediscovery by the caller.
static NSDictionary *RefreshControlScan(NSDictionary *scan, NSArray<AXNode *> *controls, AXNode *(^readNode)(AXNode *)) {
    NSMutableArray *fresh = [NSMutableArray array];
    for (AXNode *node in controls) [fresh addObject:readNode(node)];
    return @{@"applicationCount": scan[@"applicationCount"] ?: @0, @"elements": fresh};
}

static NSMutableDictionary *ResultForScan(NSDictionary *scan, NSString *command, BOOL changed) {
    NSMutableDictionary *result = [StateSnapshot(scan) mutableCopy];
    result[@"command"] = command;
    result[@"changed"] = @(changed);
    return result;
}

static void (^CommandResultSink)(NSDictionary *) = nil;

static void WriteJSON(NSDictionary *object) {
    if (CommandResultSink) { CommandResultSink(object); return; }
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
    if (!data || error) {
        fprintf(stderr, "Could not encode helper result.\n");
        return;
    }
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static BOOL ShortcutFallbackEnabled(NSString *family) {
    NSString *value = NSProcessInfo.processInfo.environment[@"TEAMS_CONTROLS_SHORTCUT_FALLBACK"];
    if (value.length == 0) return NO;
    NSArray<NSString *> *parts = [[value lowercaseString] componentsSeparatedByString:@","];
    return [parts containsObject:@"all"] || [parts containsObject:family.lowercaseString];
}

static BOOL PostTeamsKey(pid_t pid, CGKeyCode keyCode, CGEventFlags flags) {
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStatePrivate);
    if (!source) return NO;
    CGEventRef down = CGEventCreateKeyboardEvent(source, keyCode, true);
    CGEventRef up = CGEventCreateKeyboardEvent(source, keyCode, false);
    CFRelease(source);
    if (!down || !up) {
        if (down) CFRelease(down);
        if (up) CFRelease(up);
        return NO;
    }
    CGEventSetFlags(down, flags);
    CGEventSetFlags(up, flags);
    CGEventPostToPid(pid, down);
    CGEventPostToPid(pid, up);
    CFRelease(down);
    CFRelease(up);
    return YES;
}

static BOOL PostTeamsShortcut(pid_t pid, CGKeyCode keyCode) {
    return PostTeamsKey(pid, keyCode, kCGEventFlagMaskCommand | kCGEventFlagMaskShift);
}

static pid_t OpenMeetingPickerPID = 0;
static AXNode *OpenMeetingPickerTarget = nil;
static NSDictionary *MeetingToolbarScan = nil;

static BOOL PickerTargetStillPresent(AXNode *target) {
    if (!target) return NO;
    AXNode *fresh = RefreshNode(target);
    if (!fresh.canPress || ![fresh.role isEqualToString:target.role]) return NO;
    if (NodeMatchesAction(fresh, RaiseHandLabels()) || NodeMatchesAction(fresh, LowerHandLabels())) return YES;
    for (NSString *key in ReactionDefinitions()) {
        if (NodeMatchesAction(fresh, ReactionDefinitions()[key][@"labels"])) return YES;
    }
    return NO;
}

static void DismissPickerUntilGone(void (^sendEscape)(void), BOOL (^stillPresent)(void)) {
    for (NSInteger attempt = 0; attempt < 3; attempt += 1) {
        sendEscape();
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.12]];
        if (!stillPresent()) break;
    }
}

static void DismissMeetingPicker(void) {
    if (OpenMeetingPickerPID <= 0) return;
    pid_t pid = OpenMeetingPickerPID;
    AXNode *target = OpenMeetingPickerTarget;
    OpenMeetingPickerPID = 0;
    OpenMeetingPickerTarget = nil;
    // Retry only while a confirmed picker control still exists in Teams.
    DismissPickerUntilGone(^{ PostTeamsKey(pid, 53, 0); }, ^BOOL { return PickerTargetStillPresent(target); });
}

static NSDictionary *WithMeetingToolbarState(NSDictionary *scan) {
    if (!MeetingToolbarScan) return scan;
    NSMutableArray *hands = [NSMutableArray array];
    for (AXNode *node in scan[@"elements"]) {
        if (node.meetingReactionPicker && HandScore(node) > 0) [hands addObject:node];
    }
    if (hands.count == 0) return scan;
    NSMutableArray *elements = [MeetingToolbarScan[@"elements"] mutableCopy];
    [elements addObjectsFromArray:hands];
    return @{@"applicationCount": scan[@"applicationCount"], @"elements": elements};
}

static NSDictionary *ScanMeetingControlsInScan(NSDictionary *scan, BOOL includeHand) {
    BOOL pickerVisible = NO;
    for (AXNode *node in scan[@"elements"]) {
        if (node.meetingReactionPicker) { OpenMeetingPickerPID = node.pid; pickerVisible = YES; break; }
    }
    if (pickerVisible) {
        OpenMeetingPickerTarget = BestNode(scan[@"elements"], ^NSInteger(AXNode *node) {
            if (!node.meetingReactionPicker || node.pid != OpenMeetingPickerPID) return NSIntegerMin;
            return HandScore(node);
        });
    }
    if (pickerVisible && includeHand && MeetingToolbarScan) return WithMeetingToolbarState(scan);
    if (OpenMeetingPickerPID > 0) {
        DismissMeetingPicker();
        scan = ScanTeams();
    }
    if (!includeHand) return scan;
    BOOL ambiguous = NO;
    AXNode *hand = BestUniqueNode(scan[@"elements"], ^NSInteger(AXNode *node) { return HandScore(node); }, &ambiguous);
    if (hand || ambiguous) return scan;
    AXNode *launcher = BestUniqueNode(scan[@"elements"], ^NSInteger(AXNode *node) { return LauncherScore(node); }, &ambiguous);
    if (!launcher || ambiguous || PressNode(launcher) != kAXErrorSuccess) return scan;
    MeetingToolbarScan = scan;
    OpenMeetingPickerPID = launcher.pid;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:VerificationTimeout];
    NSDictionary *pickerScan;
    do {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.15]];
        pickerScan = ScanTeams();
        BOOL handAmbiguous = NO;
        AXNode *pickerHand = BestUniqueNode(pickerScan[@"elements"], ^NSInteger(AXNode *node) { return HandScore(node); }, &handAmbiguous);
        if (pickerHand || handAmbiguous) {
            OpenMeetingPickerTarget = pickerHand;
            return WithMeetingToolbarState(pickerScan);
        }
    } while (deadline.timeIntervalSinceNow > 0);
    return scan;
}

static NSDictionary *ScanMeetingControls(BOOL includeHand) {
    return ScanMeetingControlsInScan(ScanTeams(), includeHand);
}

static BOOL PersistentMode = NO;
static BOOL PersistentParentClosed = NO;
static pid_t PersistentParentPID = 0;
static BOOL PersistentInvalid = YES;
static BOOL PersistentStateDirty = NO;
static BOOL PersistentPaused = NO;
static long long PersistentGeneration = 0;
static BOOL PersistentForcePublish = NO;
static NSDictionary *PersistentScan = nil;
static NSArray<AXNode *> *PersistentNodes = nil;
static NSArray *PersistentContext = nil;
static void InstallPersistentObservers(void);

// Context contains process and window identities, never their titles.
static NSArray *TeamsContext(void) {
    NSMutableArray *context = [NSMutableArray array];
    for (NSDictionary *application in CandidateApplications()) {
        AXUIElementRef root = (__bridge AXUIElementRef)application[@"root"];
        [context addObject:@{@"pid": application[@"pid"],
            @"windows": ElementArrayAttribute(root, kAXWindowsAttribute),
            @"focused": CopyAttribute(root, kAXFocusedWindowAttribute) ?: NSNull.null}];
    }
    return context;
}

static BOOL RefreshedControlsMatch(NSArray<AXNode *> *previous, NSArray<AXNode *> *fresh) {
    if (previous.count != fresh.count) return NO;
    for (NSUInteger index = 0; index < previous.count; index += 1) {
        AXNode *old = previous[index], *current = fresh[index];
        if (![old.role isEqualToString:current.role] || ![old.identifier isEqualToString:current.identifier]
            || old.pid != current.pid || !current.canPress) return NO;
        if ((MicrophoneScore(old) > 0 && MicrophoneScore(current) <= 0)
            || (CameraScore(old) > 0 && CameraScore(current) <= 0)
            || (HandScore(old) > 0 && HandScore(current) <= 0)
            || (LauncherScore(old) > 0 && LauncherScore(current) <= 0)
            || (LeaveScore(old) > 0 && LeaveScore(current) <= 0)) return NO;
    }
    return YES;
}

static BOOL PersistentNeedsDiscovery(BOOL foreground, NSDictionary *state, NSUInteger count) {
    return foreground && (count == 0 || [state[@"microphone"] isEqualToString:@"unavailable"]
        || [state[@"camera"] isEqualToString:@"unavailable"]);
}

static NSDictionary *PersistentControlScan(BOOL allowPickerDismissal, BOOL foreground) {
    NSArray *context = TeamsContext();
    BOOL missing = PersistentScan && PersistentNeedsDiscovery(foreground, StateSnapshot(PersistentScan), PersistentNodes.count);
    if (!PersistentInvalid && !missing && PersistentScan && [context isEqualToArray:PersistentContext]) {
        NSDictionary *fresh = RefreshControlScan(PersistentScan, PersistentNodes, ^AXNode *(AXNode *node) { return RefreshNode(node); });
        if (RefreshedControlsMatch(PersistentNodes, fresh[@"elements"])) {
            PersistentScan = fresh;
            PersistentNodes = fresh[@"elements"];
            return fresh;
        }
    }
    NSDictionary *scan = allowPickerDismissal ? ScanMeetingControls(NO) : ScanTeams();
    PersistentNodes = StateControlNodes(scan);
    PersistentScan = @{@"applicationCount": scan[@"applicationCount"], @"elements": PersistentNodes};
    PersistentContext = context;
    PersistentInvalid = NO;
    InstallPersistentObservers();
    return scan;
}

typedef NSString *(^NodeStateReader)(AXNode *node);

static int PerformDesiredControl(NSString *command, NSString *desiredState, NSString *family, CGKeyCode shortcutKey, NodeScorer scorer, NodeStateReader stateReader) {
    NSDictionary *initialScan = PersistentMode ? PersistentControlScan(YES, YES) : ScanMeetingControls(NO);
    if ([family isEqualToString:@"hand"]) {
        if ([StateSnapshot(initialScan)[@"hand"] isEqualToString:desiredState]) {
            WriteJSON(ResultForScan(initialScan, command, NO));
            return 0;
        }
        initialScan = ScanMeetingControlsInScan(initialScan, YES);
    }
    if ([initialScan[@"applicationCount"] integerValue] == 0) {
        WriteJSON(ResultForScan(initialScan, command, NO));
        fprintf(stderr, "Microsoft Teams is not running.\n");
        return 2;
    }
    BOOL ambiguous = NO;
    AXNode *control = BestUniqueNode(initialScan[@"elements"], scorer, &ambiguous);
    if (ambiguous) {
        WriteJSON(ResultForScan(initialScan, command, NO));
        fprintf(stderr, "More than one equally plausible %s control was exposed.\n", family.UTF8String);
        return 11;
    }
    if (!control) {
        WriteJSON(ResultForScan(initialScan, command, NO));
        fprintf(stderr, "No safe %s control was found in the active Teams meeting.\n", family.UTF8String);
        return 10;
    }
    NSString *currentState = stateReader(control);
    if ([currentState isEqualToString:desiredState]) {
        WriteJSON(ResultForScan(initialScan, command, NO));
        return 0;
    }
    if ([currentState isEqualToString:@"unknown"]) {
        WriteJSON(ResultForScan(initialScan, command, NO));
        fprintf(stderr, "The current %s state could not be determined safely.\n", family.UTF8String);
        return 10;
    }
    if (PersistentMode && (PersistentParentClosed || getppid() != PersistentParentPID)) return 12;
    if (!control.meetingReactionPicker) ScrollNodeIntoView(control);
    AXError pressError = PressNode(control);
    BOOL usedShortcut = NO;
    if (pressError != kAXErrorSuccess && ShortcutFallbackEnabled(family)) usedShortcut = PostTeamsShortcut(control.pid, shortcutKey);
    if (pressError != kAXErrorSuccess && !usedShortcut) {
        WriteJSON(ResultForScan(initialScan, command, NO));
        fprintf(stderr, "Could not invoke the %s control: %s.\n", family.UTF8String, AXErrorDescription(pressError).UTF8String);
        return 12;
    }
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:VerificationTimeout];
    BOOL directVerification = [family isEqualToString:@"microphone"] || [family isEqualToString:@"camera"];
    NSArray<AXNode *> *stateControls = directVerification ? StateControlNodes(initialScan) : nil;
    NSDictionary *currentScan;
    do {
        if (directVerification) {
            currentScan = RefreshControlScan(initialScan, stateControls, ^AXNode *(AXNode *node) { return RefreshNode(node); });
        } else {
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.12]];
            currentScan = WithMeetingToolbarState(ScanTeams());
        }
        BOOL currentAmbiguous = NO;
        AXNode *currentControl = BestUniqueNode(currentScan[@"elements"], scorer, &currentAmbiguous);
        if (directVerification && !currentControl && !currentAmbiguous) {
            // Teams replaced the toolbar. Rediscover without pressing a second time.
            currentScan = ScanMeetingControls(NO);
            stateControls = StateControlNodes(currentScan);
            currentControl = BestUniqueNode(currentScan[@"elements"], scorer, &currentAmbiguous);
        }
        BOOL confirmed = !currentAmbiguous && currentControl && [stateReader(currentControl) isEqualToString:desiredState];
        if ([family isEqualToString:@"hand"] && !currentAmbiguous) confirmed = [StateSnapshot(currentScan)[@"hand"] isEqualToString:desiredState];
        if (confirmed) {
            if (PersistentMode) {
                PersistentScan = currentScan;
                PersistentNodes = StateControlNodes(currentScan);
            }
            WriteJSON(ResultForScan(currentScan, command, YES));
            return 0;
        }
        if (directVerification) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    } while (deadline.timeIntervalSinceNow > 0);
    WriteJSON(ResultForScan(currentScan, command, YES));
    fprintf(stderr, "Teams accepted the %s action, but the requested state was not confirmed.\n", family.UTF8String);
    return 13;
}

static int PerformLeave(void) {
    NSDictionary *initialScan = ScanMeetingControls(NO);
    if ([initialScan[@"applicationCount"] integerValue] == 0) {
        WriteJSON(ResultForScan(initialScan, @"leave", NO));
        fprintf(stderr, "Microsoft Teams is not running.\n");
        return 2;
    }
    if (![StateSnapshot(initialScan)[@"meetingActive"] boolValue]) {
        WriteJSON(ResultForScan(initialScan, @"leave", NO));
        fprintf(stderr, "No active Teams meeting was found.\n");
        return 10;
    }
    BOOL ambiguous = NO;
    AXNode *leave = BestUniqueNode(initialScan[@"elements"], ^NSInteger(AXNode *node) { return LeaveScore(node); }, &ambiguous);
    if (ambiguous) {
        WriteJSON(ResultForScan(initialScan, @"leave", NO));
        fprintf(stderr, "More than one equally plausible Leave control was exposed.\n");
        return 11;
    }
    BOOL invoked = NO;
    if (leave) {
        ScrollNodeIntoView(leave);
        invoked = PressNode(leave) == kAXErrorSuccess;
        if (!invoked && ShortcutFallbackEnabled(@"leave")) invoked = PostTeamsShortcut(leave.pid, 4);
    } else if (ShortcutFallbackEnabled(@"leave")) {
        AXNode *anchor = BestNode(initialScan[@"elements"], ^NSInteger(AXNode *node) { return LauncherScore(node); });
        if (!anchor) anchor = BestNode(initialScan[@"elements"], ^NSInteger(AXNode *node) { return MicrophoneScore(node); });
        if (anchor) invoked = PostTeamsShortcut(anchor.pid, 4);
    }
    if (!invoked) {
        WriteJSON(ResultForScan(initialScan, @"leave", NO));
        fprintf(stderr, "No safe Leave control was found. End meeting controls are never selected.\n");
        return 10;
    }
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:VerificationTimeout];
    NSDictionary *currentScan;
    do {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.12]];
        currentScan = ScanTeams();
        if (![StateSnapshot(currentScan)[@"meetingActive"] boolValue]) {
            WriteJSON(ResultForScan(currentScan, @"leave", YES));
            return 0;
        }
    } while (deadline.timeIntervalSinceNow > 0);
    WriteJSON(ResultForScan(currentScan, @"leave", YES));
    fprintf(stderr, "Teams accepted Leave, but meeting controls were still present.\n");
    return 13;
}

static AXNode *FindEffectOption(NSArray<AXNode *> *elements, BOOL enable, NSSet *initialIdentities, BOOL *ambiguous) {
    NodeScorer baseScorer = enable
        ? ^NSInteger(AXNode *node) { return BlurOptionScore(node); }
        : ^NSInteger(AXNode *node) { return NoEffectOptionScore(node); };
    return BestUniqueNode(elements, ^NSInteger(AXNode *node) {
        NSInteger score = baseScorer(node);
        if (score == NSIntegerMin) return score;
        BOOL isNew = ![initialIdentities containsObject:node.elementObject];
        NSString *identifier = node.identifier.lowercaseString;
        BOOL effectIdentifier = [identifier containsString:@"effect"] || [identifier containsString:@"background"] || [identifier containsString:@"blur"];
        if (isNew) score += 80;
        if (!isNew && !effectIdentifier) return NSIntegerMin;
        return score;
    }, ambiguous);
}

static int PerformBlur(BOOL enable) {
    NSString *command = enable ? @"blur-on" : @"blur-off";
    NSString *desired = enable ? @"on" : @"off";
    NSDictionary *initialScan = ScanTeams();
    if ([initialScan[@"applicationCount"] integerValue] == 0) {
        WriteJSON(ResultForScan(initialScan, command, NO));
        fprintf(stderr, "Microsoft Teams is not running.\n");
        return 2;
    }
    if ([StateSnapshot(initialScan)[@"backgroundBlur"] isEqualToString:desired]) {
        WriteJSON(ResultForScan(initialScan, command, NO));
        return 0;
    }
    NSMutableSet *initialIdentities = [NSMutableSet set];
    for (AXNode *node in initialScan[@"elements"]) [initialIdentities addObject:node.elementObject];
    NodeScorer targetScorer = enable
        ? ^NSInteger(AXNode *node) { return BlurOptionScore(node); }
        : ^NSInteger(AXNode *node) { return NoEffectOptionScore(node); };
    BOOL targetAmbiguous = NO;
    AXNode *target = BestUniqueNode(initialScan[@"elements"], targetScorer, &targetAmbiguous);
    if (targetAmbiguous) {
        WriteJSON(ResultForScan(initialScan, command, NO));
        fprintf(stderr, "The requested video effect was ambiguous.\n");
        return 11;
    }
    NSDictionary *currentScan = initialScan;
    if (!target) {
        AXError lastLauncherError = kAXErrorSuccess;
        for (NSInteger attempt = 0; attempt < 2 && !target; attempt += 1) {
            BOOL launcherAmbiguous = NO;
            AXNode *launcher = BestUniqueNode(currentScan[@"elements"], ^NSInteger(AXNode *node) { return EffectsLauncherScore(node); }, &launcherAmbiguous);
            if (launcherAmbiguous) {
                WriteJSON(ResultForScan(currentScan, command, NO));
                fprintf(stderr, "More than one equally plausible video-effects control was exposed.\n");
                return 11;
            }
            if (!launcher) break;
            ScrollNodeIntoView(launcher);
            lastLauncherError = PressNode(launcher);
            if (lastLauncherError != kAXErrorSuccess) continue;
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:MenuTimeout];
            do {
                [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.12]];
                currentScan = ScanTeams();
                targetAmbiguous = NO;
                target = FindEffectOption(currentScan[@"elements"], enable, initialIdentities, &targetAmbiguous);
                if (targetAmbiguous) break;
            } while (!target && deadline.timeIntervalSinceNow > 0);
            if (targetAmbiguous) {
                WriteJSON(ResultForScan(currentScan, command, NO));
                fprintf(stderr, "The requested video effect was ambiguous.\n");
                return 11;
            }
        }
        if (!target && lastLauncherError != kAXErrorSuccess) {
            WriteJSON(ResultForScan(currentScan, command, NO));
            fprintf(stderr, "Could not open video effects: %s.\n", AXErrorDescription(lastLauncherError).UTF8String);
            return 12;
        }
    }
    if (!target) {
        WriteJSON(ResultForScan(currentScan, command, NO));
        fprintf(stderr, "The requested video effect was not available.\n");
        return 14;
    }
    ScrollNodeIntoView(target);
    AXError targetError = PressNode(target);
    if (targetError != kAXErrorSuccess) {
        WriteJSON(ResultForScan(currentScan, command, NO));
        fprintf(stderr, "Could not select the requested video effect: %s.\n", AXErrorDescription(targetError).UTF8String);
        return 12;
    }
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.15]];
    currentScan = ScanTeams();
    BOOL applyAmbiguous = NO;
    AXNode *apply = BestUniqueNode(currentScan[@"elements"], ^NSInteger(AXNode *node) {
        NSInteger score = ApplyScore(node);
        if (score == NSIntegerMin) return score;
        BOOL isNew = ![initialIdentities containsObject:node.elementObject];
        NSString *identifier = node.identifier.lowercaseString;
        BOOL effectIdentifier = [identifier containsString:@"effect"] || [identifier containsString:@"background"];
        if (!isNew && !effectIdentifier) return NSIntegerMin;
        if (isNew) score += 60;
        return score;
    }, &applyAmbiguous);
    if (apply && !applyAmbiguous) PressNode(apply);
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1.2];
    do {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.12]];
        currentScan = ScanTeams();
        if ([StateSnapshot(currentScan)[@"backgroundBlur"] isEqualToString:desired]) {
            WriteJSON(ResultForScan(currentScan, command, YES));
            return 0;
        }
    } while (deadline.timeIntervalSinceNow > 0);
    NSMutableDictionary *result = ResultForScan(currentScan, command, YES);
    result[@"backgroundBlur"] = @"unknown";
    WriteJSON(result);
    return 0;
}

static int InspectControls(void) {
    NSDictionary *scan = ScanTeams();
    if ([scan[@"applicationCount"] integerValue] == 0) {
        fprintf(stderr, "Microsoft Teams is not running.\n");
        return 2;
    }
    NSMutableArray<NSDictionary *> *controls = [NSMutableArray array];
    for (AXNode *node in scan[@"elements"]) {
        NSString *control = nil;
        NSString *state = @"unknown";
        if (MicrophoneScore(node) != NSIntegerMin) {
            control = @"microphone";
            state = MicrophoneStateForNode(node);
        } else if (CameraScore(node) != NSIntegerMin) {
            control = @"camera";
            state = CameraStateForNode(node);
        } else if (HandScore(node) != NSIntegerMin) {
            control = @"hand";
            state = HandStateForNode(node);
        } else if (LeaveScore(node) != NSIntegerMin) {
            control = @"leave";
        } else if (EffectsLauncherScore(node) != NSIntegerMin) {
            control = @"effects-launcher";
        } else if (BlurOptionScore(node) != NSIntegerMin) {
            control = @"blur";
            state = node.selected ? @"selected" : @"not-selected";
        } else if (NoEffectOptionScore(node) != NSIntegerMin) {
            control = @"no-effect";
            state = node.selected ? @"selected" : @"not-selected";
        } else if (LauncherScore(node) != NSIntegerMin) {
            control = @"reactions";
        }
        if (!control) continue;
        [controls addObject:@{@"control": control, @"state": state, @"role": node.role ?: @"", @"identifier": node.identifier ?: @"", @"label": node.displayText}];
    }
    WriteJSON(@{@"command": @"inspect-controls", @"state": StateSnapshot(scan), @"controls": controls});
    return 0;
}

static int Inspect(void) {
    NSDictionary *scan = ScanTeams();
    NSInteger applicationCount = [scan[@"applicationCount"] integerValue];
    NSArray<AXNode *> *elements = scan[@"elements"];
    if (applicationCount == 0) {
        fprintf(stderr, "Microsoft Teams is not running. Start Teams and join a meeting first.\n");
        return 2;
    }
    printf("Found %ld Teams process(es) and inspected %ld accessible elements.\n", (long)applicationCount, (long)elements.count);
    printf("\nKnown pressable meeting controls:\n");
    NSInteger printed = 0;
    for (AXNode *node in elements) {
        BOOL relevant = LauncherScore(node) != NSIntegerMin
            || MicrophoneScore(node) != NSIntegerMin
            || CameraScore(node) != NSIntegerMin
            || HandScore(node) != NSIntegerMin
            || LeaveScore(node) != NSIntegerMin
            || EffectsLauncherScore(node) != NSIntegerMin;
        if (!relevant) continue;
        printf("[%s] role=%s actions=%s\n  %s\n", node.processName.UTF8String, node.role.UTF8String, [node.actions componentsJoinedByString:@","].UTF8String, node.displayText.UTF8String);
        printed += 1;
    }
    if (printed == 0) printf("No known controls were exposed. Keep the meeting toolbar visible and try again.\n");
    printf("\nInspection only: nothing was clicked.\n");
    return printed > 0 ? 0 : 3;
}

@interface ReactionSession : NSObject
@property(nonatomic, strong) AXNode *launcher;
@property(nonatomic, strong) AXNode *target;
@property(nonatomic, strong) NSDictionary *reaction;
@end

@implementation ReactionSession
@end

static AXNode *FindReactionTarget(NSDictionary *reaction, AXNode *launcher, NSSet *initialIdentities, NSTimeInterval timeout, BOOL fullScan) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    AXNode *target = nil;
    do {
        NSArray<AXNode *> *currentElements = (fullScan ? ScanTeams() : ScanTeamsForPID(launcher.pid))[@"elements"];
        target = BestNode(currentElements, ^NSInteger(AXNode *node) {
            NSInteger score = ReactionScore(node, reaction);
            if (score == NSIntegerMin) return score;
            if (node.pid == launcher.pid) score += 20;
            if (initialIdentities && ![initialIdentities containsObject:node.elementObject]) score += 80;
            return score;
        });
        if (!target && deadline.timeIntervalSinceNow > 0) {
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:MIN(0.02, deadline.timeIntervalSinceNow)]];
        }
    } while (!target && deadline.timeIntervalSinceNow > 0);
    if (target) OpenMeetingPickerTarget = target;
    return target;
}

static int PrepareReactionSession(NSDictionary *reaction, ReactionSession **sessionOut) {
    NSDictionary *initialScan = ScanMeetingControls(NO);
    if ([initialScan[@"applicationCount"] integerValue] == 0) return 2;
    BOOL ambiguous = NO;
    AXNode *launcher = BestUniqueNode(initialScan[@"elements"], ^NSInteger(AXNode *node) { return LauncherScore(node); }, &ambiguous);
    if (ambiguous || !launcher) return ambiguous ? 11 : 3;
    NSMutableSet *initialIdentities = [NSMutableSet set];
    for (AXNode *node in initialScan[@"elements"]) [initialIdentities addObject:node.elementObject];
    if (PressNode(launcher) != kAXErrorSuccess) return 4;
    OpenMeetingPickerPID = launcher.pid;
    AXNode *target = FindReactionTarget(reaction, launcher, initialIdentities, MenuTimeout, YES);
    if (!target) return 5;
    ReactionSession *session = [ReactionSession new];
    session.launcher = launcher;
    session.target = target;
    session.reaction = reaction;
    *sessionOut = session;
    return 0;
}

static AXError ReacquireReactionTarget(ReactionSession *session) {
    // Teams can replace the button while leaving its picker open. Reuse that
    // picker before trying the launcher, which would otherwise toggle it shut.
    AXNode *existing = FindReactionTarget(session.reaction, session.launcher, nil, 0, YES);
    if (existing) {
        session.target = existing;
        return kAXErrorSuccess;
    }
    AXError launcherError = PressNode(session.launcher);
    if (launcherError == kAXErrorInvalidUIElement || launcherError == kAXErrorCannotComplete) {
        NSDictionary *scan = ScanTeams();
        BOOL ambiguous = NO;
        AXNode *launcher = BestUniqueNode(scan[@"elements"], ^NSInteger(AXNode *node) { return LauncherScore(node); }, &ambiguous);
        if (!launcher || ambiguous) return kAXErrorInvalidUIElement;
        session.launcher = launcher;
        launcherError = PressNode(launcher);
    }
    if (launcherError != kAXErrorSuccess) return launcherError;
    AXNode *target = FindReactionTarget(session.reaction, session.launcher, nil, 0.5, NO);
    if (!target) target = FindReactionTarget(session.reaction, session.launcher, nil, 0.6, YES);
    if (!target) return kAXErrorCannotComplete;
    session.target = target;
    return kAXErrorSuccess;
}

static AXError PressReactionWithRecovery(AXError (^press)(void), AXError (^reacquire)(void), BOOL (^canContinue)(void)) {
    if (!canContinue()) return kAXErrorCannotComplete;
    AXError error = press();
    // CannotComplete is an uncertain result: Teams may have received the press.
    // Only retry errors that establish the original action was not performed.
    if (error != kAXErrorInvalidUIElement && error != kAXErrorActionUnsupported) return error;
    if (!canContinue()) return error;
    AXError recovery = reacquire();
    if (recovery != kAXErrorSuccess) return recovery;
    if (!canContinue()) return kAXErrorCannotComplete;
    return press();
}

static int SendReaction(NSDictionary *reaction, NSString *commandName) {
    ReactionSession *session = nil;
    int prepareStatus = PrepareReactionSession(reaction, &session);
    if (prepareStatus != 0) {
        fprintf(stderr, "Could not prepare the requested Teams reaction.\n");
        return prepareStatus;
    }
    AXError reactionError = PressReactionWithRecovery(^AXError { return PressNode(session.target); },
        ^AXError { return ReacquireReactionTarget(session); }, ^BOOL { return YES; });
    if (reactionError != kAXErrorSuccess) {
        fprintf(stderr, "Could not press the requested reaction: %s.\n", AXErrorDescription(reactionError).UTF8String);
        return 6;
    }
    WriteJSON(@{@"command": commandName, @"reaction": [reaction[@"name"] lowercaseString], @"changed": @YES, @"accessibilityAccepted": @1});
    return 0;
}

static BOOL BurstStopRequested(void) {
    char buffer[64];
    ssize_t count = read(STDIN_FILENO, buffer, sizeof(buffer));
    if (count == 0 || count > 0) return YES;
    return errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR;
}

static BOOL WaitForBurstTime(NSDate *start, NSTimeInterval targetElapsed) {
    while (-start.timeIntervalSinceNow < targetElapsed) {
        if (BurstStopRequested()) return NO;
        NSTimeInterval remaining = targetElapsed + start.timeIntervalSinceNow;
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:MIN(0.01, remaining)]];
    }
    return !BurstStopRequested();
}

static NSTimeInterval NextBurstAttemptTime(NSTimeInterval previousPressTime, NSInteger rate) {
    return MAX(BurstHoldThreshold, previousPressTime + 1.0 / (NSTimeInterval)rate);
}

static int BurstReaction(NSDictionary *reaction, NSInteger requestedRate) {
    NSInteger rate = MAX(1, MIN(BurstMaximumRate, requestedRate));
    int currentFlags = fcntl(STDIN_FILENO, F_GETFL);
    if (currentFlags >= 0) fcntl(STDIN_FILENO, F_SETFL, currentFlags | O_NONBLOCK);
    NSDate *start = [NSDate date];
    NSInteger attempted = 0;
    NSInteger accepted = 0;
    NSString *stopReason = @"error";
    int exitStatus = 0;
    ReactionSession *session = nil;
    int prepareStatus = PrepareReactionSession(reaction, &session);
    if (prepareStatus != 0) {
        exitStatus = prepareStatus;
    } else {
        attempted = 1;
        NSTimeInterval firstPressTime = -start.timeIntervalSinceNow;
        AXError firstError = PressReactionWithRecovery(^AXError { return PressNode(session.target); },
            ^AXError { return ReacquireReactionTarget(session); },
            ^BOOL { return -start.timeIntervalSinceNow < BurstDurationLimit; });
        firstPressTime = -start.timeIntervalSinceNow;
        if (firstError == kAXErrorSuccess) {
            accepted = 1;
            if (!WaitForBurstTime(start, BurstHoldThreshold)) {
                stopReason = @"key-up";
            } else {
                NSTimeInterval nextAttempt = NextBurstAttemptTime(firstPressTime, rate);
                while (YES) {
                    NSTimeInterval elapsed = -start.timeIntervalSinceNow;
                    if (elapsed >= BurstDurationLimit) { stopReason = @"duration-limit"; break; }
                    if (attempted >= BurstMaximumAttempts) { stopReason = @"count-limit"; break; }
                    if (!WaitForBurstTime(start, MIN(nextAttempt, BurstDurationLimit))) { stopReason = @"key-up"; break; }
                    if (-start.timeIntervalSinceNow >= BurstDurationLimit) { stopReason = @"duration-limit"; break; }
                    NSTimeInterval pressTime = -start.timeIntervalSinceNow;
                    attempted += 1;
                    AXError reactionError = PressReactionWithRecovery(^AXError { return PressNode(session.target); },
                        ^AXError { return ReacquireReactionTarget(session); },
                        ^BOOL { return !BurstStopRequested() && -start.timeIntervalSinceNow < BurstDurationLimit; });
                    pressTime = -start.timeIntervalSinceNow;
                    if (reactionError != kAXErrorSuccess) {
                        if (BurstStopRequested()) { stopReason = @"key-up"; break; }
                        if (-start.timeIntervalSinceNow >= BurstDurationLimit) { stopReason = @"duration-limit"; break; }
                        stopReason = @"selection-error";
                        exitStatus = 6;
                        break;
                    }
                    accepted += 1;
                    nextAttempt = NextBurstAttemptTime(pressTime, rate);
                }
            }
        } else {
            exitStatus = 6;
        }
    }
    NSInteger elapsedMs = (NSInteger)llround((-start.timeIntervalSinceNow) * 1000.0);
    NSString *reactionName = [reaction[@"name"] lowercaseString] ?: @"unknown";
    NSString *finalStopReason = stopReason ?: @"error";
    WriteJSON(@{@"command": @"burst", @"reaction": reactionName, @"attempted": @(attempted), @"accessibilityAccepted": @(accepted), @"elapsedMs": @(elapsedMs), @"stopReason": finalStopReason});
    if (exitStatus != 0) fprintf(stderr, "The reaction burst stopped because Teams did not accept a reaction control.\n");
    return exitStatus;
}

static NSMutableArray *PersistentObservers;

static void PersistentAXChanged(AXObserverRef observer, AXUIElementRef element, CFStringRef notification, void *context) {
    (void)observer; (void)element; (void)context;
    PersistentStateDirty = YES;
    if (!CFEqual(notification, kAXValueChangedNotification) && !CFEqual(notification, kAXTitleChangedNotification)
        && !CFEqual(notification, CFSTR("AXDescriptionChanged"))) PersistentInvalid = YES;
}

static void RemovePersistentObservers(void) {
    for (id object in PersistentObservers) {
        AXObserverRef observer = (__bridge AXObserverRef)object;
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), kCFRunLoopDefaultMode);
    }
    PersistentObservers = nil;
}

static void InstallPersistentObservers(void) {
    if (!PersistentMode) return;
    RemovePersistentObservers();
    PersistentObservers = [NSMutableArray array];
    for (NSDictionary *application in CandidateApplications()) {
        pid_t pid = [application[@"pid"] intValue];
        AXObserverRef observer = NULL;
        if (AXObserverCreate(pid, PersistentAXChanged, &observer) != kAXErrorSuccess || !observer) continue;
        [PersistentObservers addObject:CFBridgingRelease(observer)];
        AXUIElementRef root = (__bridge AXUIElementRef)application[@"root"];
        for (NSString *notification in @[(__bridge NSString *)kAXFocusedWindowChangedNotification, (__bridge NSString *)kAXWindowCreatedNotification]) {
            AXObserverAddNotification(observer, root, (__bridge CFStringRef)notification, NULL);
        }
        for (id window in ElementArrayAttribute(root, kAXWindowsAttribute)) {
            for (NSString *notification in @[(__bridge NSString *)kAXUIElementDestroyedNotification,
                    (__bridge NSString *)kAXLayoutChangedNotification, (__bridge NSString *)kAXWindowMiniaturizedNotification,
                    (__bridge NSString *)kAXWindowDeminiaturizedNotification]) {
                AXObserverAddNotification(observer, (__bridge AXUIElementRef)window, (__bridge CFStringRef)notification, NULL);
            }
        }
        for (AXNode *node in PersistentNodes) {
            if (node.pid != pid) continue;
            for (NSString *notification in @[(__bridge NSString *)kAXValueChangedNotification, (__bridge NSString *)kAXTitleChangedNotification,
                    (__bridge NSString *)kAXUIElementDestroyedNotification, @"AXDescriptionChanged"]) {
                AXObserverAddNotification(observer, node.element, (__bridge CFStringRef)notification, NULL);
            }
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), kCFRunLoopDefaultMode);
    }
}

static BOOL IsPersistentCommand(NSString *command) {
    return [@[@"status", @"mute", @"unmute", @"camera-on", @"camera-off"] containsObject:command];
}

static BOOL ValidPersistentGeneration(id generation) {
    if (!generation) return YES;
    if (![generation isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)generation) == CFBooleanGetTypeID()) return NO;
    double value = [generation doubleValue];
    return value >= 0 && value <= 9007199254740991.0 && floor(value) == value;
}

static BOOL ValidPersistentRequest(NSDictionary *request) {
    id identifier = request[@"id"];
    if (![identifier isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)identifier) == CFBooleanGetTypeID()) return NO;
    double value = [identifier doubleValue];
    if (value < 1 || value > 9007199254740991.0 || floor(value) != value) return NO;
    if (![request[@"command"] isKindOfClass:NSString.class] || !IsPersistentCommand(request[@"command"])) return NO;
    id generation = request[@"generation"];
    if (!ValidPersistentGeneration(generation)) return NO;
    id fresh = request[@"forceFresh"];
    return !fresh || ([fresh isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)fresh) == CFBooleanGetTypeID());
}

@interface PersistentInput : NSObject
@property(nonatomic, strong) NSMutableData *buffer;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *requests;
@property(nonatomic) BOOL malformed;
@end
@implementation PersistentInput
@end

static void ReadPersistentInput(CFFileDescriptorRef descriptor, CFOptionFlags flags, void *context) {
    (void)flags;
    PersistentInput *input = (__bridge PersistentInput *)context;
    char bytes[4096];
    ssize_t count;
    while ((count = read(STDIN_FILENO, bytes, sizeof(bytes))) > 0) {
        [input.buffer appendBytes:bytes length:(NSUInteger)count];
        if (input.buffer.length > 8192) { input.malformed = YES; break; }
        while (input.buffer.length > 0) {
            const char *data = input.buffer.bytes;
            const char *newline = memchr(data, '\n', input.buffer.length);
            if (!newline) break;
            NSUInteger length = (NSUInteger)(newline - data);
            NSData *line = [input.buffer subdataWithRange:NSMakeRange(0, length)];
            [input.buffer replaceBytesInRange:NSMakeRange(0, length + 1) withBytes:NULL length:0];
            id message = [NSJSONSerialization JSONObjectWithData:line options:0 error:NULL];
            if (![message isKindOfClass:NSDictionary.class]) { input.malformed = YES; break; }
            if (!ValidPersistentGeneration(message[@"generation"])) { input.malformed = YES; break; }
            if ([message[@"kind"] isEqual:@"pause"]) {
                PersistentGeneration = [message[@"generation"] longLongValue];
                PersistentPaused = YES;
            } else if ([message[@"kind"] isEqual:@"resume"]) {
                PersistentGeneration = [message[@"generation"] longLongValue];
                PersistentPaused = NO;
                PersistentForcePublish = YES;
                PersistentInvalid = YES;
                PersistentStateDirty = YES;
            } else if (ValidPersistentRequest(message) && input.requests.count < 4) {
                [input.requests addObject:message];
            } else {
                input.malformed = YES;
                break;
            }
        }
        if (input.malformed) break;
    }
    if (count == 0 || (count < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR)) PersistentParentClosed = YES;
    if (!PersistentParentClosed && !input.malformed) CFFileDescriptorEnableCallBacks(descriptor, kCFFileDescriptorReadCallBack);
}

static int ExecutePersistentCommand(NSString *command) {
    if ([command isEqualToString:@"status"]) {
        NSDictionary *scan = PersistentMode ? PersistentControlScan(YES, YES) : ScanMeetingControls(NO);
        WriteJSON(ResultForScan(scan, command, NO));
        return [scan[@"applicationCount"] integerValue] == 0 ? 2 : 0;
    }
    if ([command isEqualToString:@"mute"]) return PerformDesiredControl(command, @"muted", @"microphone", 46, ^NSInteger(AXNode *node) { return MicrophoneScore(node); }, ^NSString *(AXNode *node) { return MicrophoneStateForNode(node); });
    if ([command isEqualToString:@"unmute"]) return PerformDesiredControl(command, @"unmuted", @"microphone", 46, ^NSInteger(AXNode *node) { return MicrophoneScore(node); }, ^NSString *(AXNode *node) { return MicrophoneStateForNode(node); });
    if ([command isEqualToString:@"camera-on"]) return PerformDesiredControl(command, @"on", @"camera", 31, ^NSInteger(AXNode *node) { return CameraScore(node); }, ^NSString *(AXNode *node) { return CameraStateForNode(node); });
    if ([command isEqualToString:@"camera-off"]) return PerformDesiredControl(command, @"off", @"camera", 31, ^NSInteger(AXNode *node) { return CameraScore(node); }, ^NSString *(AXNode *node) { return CameraStateForNode(node); });
    return 64;
}

static int ServeControls(void) {
    PersistentMode = YES;
    PersistentParentPID = getppid();
    PersistentParentClosed = NO;
    int originalFlags = fcntl(STDIN_FILENO, F_GETFL);
    if (originalFlags < 0 || fcntl(STDIN_FILENO, F_SETFL, originalFlags | O_NONBLOCK) < 0) return 64;
    PersistentInput *input = [PersistentInput new];
    input.buffer = [NSMutableData data];
    input.requests = [NSMutableArray array];
    CFFileDescriptorContext descriptorContext = {0, (__bridge void *)input, NULL, NULL, NULL};
    CFFileDescriptorRef descriptor = CFFileDescriptorCreate(NULL, STDIN_FILENO, false, ReadPersistentInput, &descriptorContext);
    if (!descriptor) return 64;
    CFRunLoopSourceRef source = CFFileDescriptorCreateRunLoopSource(NULL, descriptor, 0);
    if (!source) { CFRelease(descriptor); return 64; }
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
    CFFileDescriptorEnableCallBacks(descriptor, kCFFileDescriptorReadCallBack);
    NSMutableArray *workspaceTokens = [NSMutableArray array];
    NSNotificationCenter *center = NSWorkspace.sharedWorkspace.notificationCenter;
    for (NSString *name in @[NSWorkspaceDidWakeNotification, NSWorkspaceDidLaunchApplicationNotification, NSWorkspaceDidTerminateApplicationNotification]) {
        id token = [center addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *notification) {
            NSRunningApplication *app = notification.userInfo[NSWorkspaceApplicationKey];
            if (![notification.name isEqualToString:NSWorkspaceDidWakeNotification]
                && ![app.bundleIdentifier.lowercaseString hasPrefix:@"com.microsoft.teams2"]) return;
            PersistentInvalid = YES;
            PersistentStateDirty = YES;
        }];
        [workspaceTokens addObject:token];
    }
    NSDictionary *lastState = nil;
    NSTimeInterval nextFallback = NSProcessInfo.processInfo.systemUptime + 2.0;
    NSTimeInterval nextNotificationRefresh = 0;
    while (!PersistentParentClosed && !input.malformed && getppid() == PersistentParentPID) {
        @autoreleasepool {
            if (input.requests.count > 0) {
                NSDictionary *request = input.requests.firstObject;
                [input.requests removeObjectAtIndex:0];
                PersistentGeneration = [request[@"generation"] longLongValue];
                if ([request[@"forceFresh"] boolValue]) PersistentInvalid = YES;
                __block NSDictionary *result = nil;
                int exitCode = 64;
                CommandResultSink = ^(NSDictionary *object) { result = object; };
                @try { exitCode = ExecutePersistentCommand(request[@"command"]); }
                @finally { CommandResultSink = nil; DismissMeetingPicker(); }
                WriteJSON(@{@"id": request[@"id"], @"generation": request[@"generation"] ?: @0, @"exitCode": @(exitCode), @"result": result ?: @{} });
                if (result) lastState = StateSnapshot(PersistentScan);
                nextFallback = NSProcessInfo.processInfo.systemUptime + 2.0;
                continue;
            }
            NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
            if (!PersistentPaused && PersistentScan
                && ((PersistentStateDirty && now >= nextNotificationRefresh) || now >= nextFallback)) {
                PersistentStateDirty = NO;
                NSDictionary *scan = PersistentControlScan(NO, NO);
                NSDictionary *state = StateSnapshot(scan);
                if (PersistentForcePublish || ![state isEqualToDictionary:lastState]) {
                    PersistentForcePublish = NO;
                    WriteJSON(@{@"event": @"state", @"generation": @(PersistentGeneration), @"result": ResultForScan(scan, @"status", NO)});
                    lastState = state;
                }
                nextNotificationRefresh = NSProcessInfo.processInfo.systemUptime + 0.25;
                nextFallback = NSProcessInfo.processInfo.systemUptime + 2.0;
            }
            NSTimeInterval delay = PersistentPaused || !PersistentScan ? 30.0 : MAX(0.001, nextFallback - NSProcessInfo.processInfo.systemUptime);
            if (PersistentStateDirty && !PersistentPaused) delay = MIN(delay, MAX(0.001, nextNotificationRefresh - NSProcessInfo.processInfo.systemUptime));
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, delay, true);
        }
    }
    for (id token in workspaceTokens) [center removeObserver:token];
    RemovePersistentObservers();
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
    CFFileDescriptorInvalidate(descriptor);
    CFRelease(source);
    CFRelease(descriptor);
    fcntl(STDIN_FILENO, F_SETFL, originalFlags);
    PersistentScan = nil; PersistentNodes = nil; PersistentContext = nil;
    PersistentMode = NO;
    if (input.malformed) fprintf(stderr, "Invalid persistent control protocol.\n");
    return input.malformed ? 64 : 0;
}

#ifndef TEAMS_REACTION_TESTING
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            PrintUsage(argv[0]);
            return 64;
        }
        NSString *command = [[NSString stringWithUTF8String:argv[1]] lowercaseString];
        if ([command isEqualToString:@"help"] || [command isEqualToString:@"--help"] || [command isEqualToString:@"-h"]) {
            PrintUsage(argv[0]);
            return 0;
        }
        NSSet<NSString *> *singleArgumentCommands = [NSSet setWithArray:@[@"serve", @"status", @"inspect", @"inspect-controls", @"mute", @"unmute", @"camera-on", @"camera-off", @"blur-on", @"blur-off", @"hand-raise", @"hand-lower", @"leave"]];
        BOOL directReaction = ReactionDefinitions()[command] != nil;
        BOOL validArity = (argc == 2 && ([singleArgumentCommands containsObject:command] || directReaction))
            || (argc == 3 && ([command isEqualToString:@"react"] || [command isEqualToString:@"burst"]))
            || (argc == 4 && [command isEqualToString:@"burst"]);
        if (!validArity) {
            fprintf(stderr, "Invalid command arguments.\n\n");
            PrintUsage(argv[0]);
            return 64;
        }
        NSDictionary *reaction = nil;
        if ([command isEqualToString:@"react"] || [command isEqualToString:@"burst"]) {
            NSString *reactionName = [[NSString stringWithUTF8String:argv[2]] lowercaseString];
            reaction = ReactionDefinitions()[reactionName];
            if (!reaction) {
                fprintf(stderr, "Unknown reaction.\n");
                return 64;
            }
        }
        if (!RequireAccessibilityPermission()) return 1;
        @try {
            if ([command isEqualToString:@"inspect"]) return Inspect();
            if ([command isEqualToString:@"inspect-controls"]) return InspectControls();
            if ([command isEqualToString:@"serve"]) return ServeControls();
            if (IsPersistentCommand(command)) return ExecutePersistentCommand(command);
            if ([command isEqualToString:@"hand-raise"]) return PerformDesiredControl(command, @"raised", @"hand", 40, ^NSInteger(AXNode *node) { return HandScore(node); }, ^NSString *(AXNode *node) { return HandStateForNode(node); });
            if ([command isEqualToString:@"hand-lower"]) return PerformDesiredControl(command, @"lowered", @"hand", 40, ^NSInteger(AXNode *node) { return HandScore(node); }, ^NSString *(AXNode *node) { return HandStateForNode(node); });
            if ([command isEqualToString:@"leave"]) return PerformLeave();
            if ([command isEqualToString:@"blur-on"]) return PerformBlur(YES);
            if ([command isEqualToString:@"blur-off"]) return PerformBlur(NO);
            if ([command isEqualToString:@"react"]) return SendReaction(reaction, @"react");
            if ([command isEqualToString:@"burst"]) {
                NSInteger rate = argc == 4 ? [[NSString stringWithUTF8String:argv[3]] integerValue] : BurstDefaultRate;
                if (rate < 1 || rate > BurstMaximumRate) {
                    fprintf(stderr, "Burst rate must be between 1 and 10.\n");
                    return 64;
                }
                return BurstReaction(reaction, rate);
            }
            if (directReaction) return SendReaction(ReactionDefinitions()[command], @"react");
            fprintf(stderr, "Unknown command.\n");
            return 64;
        } @finally {
            DismissMeetingPicker();
        }
    }
}
#endif
