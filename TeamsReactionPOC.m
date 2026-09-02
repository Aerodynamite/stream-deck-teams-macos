#import <AppKit/AppKit.h>
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
static const NSTimeInterval BurstDurationLimit = 3.0;
static const NSInteger BurstDefaultRate = 3;
static const NSInteger BurstMaximumRate = 10;
static const NSInteger BurstMaximumAttempts = 30;
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
@property(nonatomic, copy) NSString *value;
@property(nonatomic, copy) NSArray<NSString *> *actions;
@property(nonatomic) NSInteger depth;
@property(nonatomic) BOOL focusedWindow;
@property(nonatomic) BOOL selected;
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
    for (NSString *part in @[self.identifier, self.title, self.nodeDescription, self.helpText, self.value]) {
        if (part.length > 0) [parts addObject:part];
    }
    return [[parts componentsJoinedByString:@" | "] lowercaseString];
}
- (NSString *)displayText {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *part in @[self.title, self.nodeDescription, self.helpText, self.value, self.identifier]) {
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
    return @{
        @"like": @{@"name": @"Like", @"labels": @[@"like", @"thumbs up", @"thumb up", @"vind ik leuk", @"duim omhoog", @"gefällt mir", @"j'aime", @"me gusta"]},
        @"love": @{@"name": @"Love", @"labels": @[@"love", @"heart", @"hart", @"liebe", @"coeur", @"cœur", @"corazón", @"corazon"]},
        @"applause": @{@"name": @"Applause", @"labels": @[@"applause", @"clap", @"clapping", @"applaus", @"applaudissements", @"aplausos"]},
        @"laugh": @{@"name": @"Laugh", @"labels": @[@"laugh", @"laughing", @"lachen", @"rire", @"risa"]},
        @"surprise": @{@"name": @"Surprise", @"labels": @[@"surprise", @"surprised", @"wow", @"verrast", @"überrascht", @"surpris", @"sorpresa"]}
    };
}

static NSArray<NSString *> *LauncherLabels(void) {
    return @[@"react", @"reaction", @"reactions", @"reageren", @"reactie", @"reacties", @"réagir", @"réaction", @"réactions", @"reagieren", @"reaktion", @"reaktionen", @"reaccionar", @"reacción", @"reacciones"];
}

static NSArray<NSString *> *MuteLabels(void) {
    return @[@"mute", @"mute microphone", @"dempen", @"microfoon dempen", @"stummschalten", @"mikrofon stummschalten", @"désactiver le micro", @"silenciar", @"silenciar micrófono"];
}

static NSArray<NSString *> *UnmuteLabels(void) {
    return @[@"unmute", @"unmute microphone", @"dempen opheffen", @"microfoon inschakelen", @"stummschaltung aufheben", @"mikrofon einschalten", @"activer le micro", @"reactivar audio", @"activar micrófono"];
}

static NSArray<NSString *> *CameraOffLabels(void) {
    return @[@"turn camera off", @"stop video", @"camera uitschakelen", @"video stoppen", @"kamera ausschalten", @"désactiver la caméra", @"desactivar la cámara"];
}

static NSArray<NSString *> *CameraOnLabels(void) {
    return @[@"turn camera on", @"start video", @"camera inschakelen", @"video starten", @"kamera einschalten", @"activer la caméra", @"activar la cámara"];
}

static NSArray<NSString *> *RaiseHandLabels(void) {
    return @[@"raise your hand", @"raise hand", @"hand opsteken", @"steek uw hand op", @"hand heben", @"lever la main", @"levantar la mano"];
}

static NSArray<NSString *> *LowerHandLabels(void) {
    return @[@"lower your hand", @"lower hand", @"hand omlaag", @"uw hand omlaag doen", @"hand senken", @"baisser la main", @"bajar la mano"];
}

static NSArray<NSString *> *LeaveLabels(void) {
    return @[@"leave", @"leave call", @"hang up", @"verlaten", @"gesprek verlaten", @"auflegen", @"besprechung verlassen", @"quitter", @"quitter l'appel", @"salir", @"salir de la llamada"];
}

static NSArray<NSString *> *EffectsLauncherLabels(void) {
    return @[@"video effects and settings", @"backgrounds and effects", @"effects and avatars", @"video effects", @"achtergronden en effecten", @"video-effecten", @"hintergründe und effekte", @"effets vidéo", @"arrière-plans et effets", @"fondos y efectos", @"efectos de vídeo"];
}

static NSArray<NSString *> *BlurLabels(void) {
    return @[@"blur", @"background blur", @"vervagen", @"achtergrond vervagen", @"weichzeichnen", @"hintergrund weichzeichnen", @"flou", @"flouter l’arrière-plan", @"desenfocar", @"desenfocar fondo"];
}

static NSArray<NSString *> *NoEffectLabels(void) {
    return @[@"none", @"no effect", @"no background", @"geen", @"geen effect", @"zonder achtergrond", @"keine", @"kein effekt", @"aucun", @"aucun effet", @"ninguno", @"sin efecto"];
}

static NSArray<NSString *> *ApplyLabels(void) {
    return @[@"apply", @"apply and turn on video", @"toepassen", @"toepassen en video inschakelen", @"anwenden", @"appliquer", @"aplicar"];
}

static void PrintUsage(const char *executablePath) {
    NSString *executable = [[NSString stringWithUTF8String:executablePath] lastPathComponent];
    printf("Microsoft Teams meeting controls for Stream Deck\n\n");
    printf("Usage:\n");
    printf("  %s status\n", executable.UTF8String);
    printf("  %s inspect-controls\n", executable.UTF8String);
    printf("  %s mute|unmute|camera-on|camera-off\n", executable.UTF8String);
    printf("  %s blur-on|blur-off|hand-raise|hand-lower|leave\n", executable.UTF8String);
    printf("  %s react like|love|applause|laugh|surprise\n", executable.UTF8String);
    printf("  %s burst like|love|applause|laugh|surprise [rate]\n", executable.UTF8String);
    printf("  %s inspect\n\n", executable.UTF8String);
    printf("Burst rate defaults to 3 and is capped at 10 attempts per second.\n");
    printf("inspect and inspect-controls do not press anything.\n");
}

static id CopyAttribute(AXUIElementRef element, CFStringRef attribute) {
    CFTypeRef value = NULL;
    if (AXUIElementCopyAttributeValue(element, attribute, &value) != kAXErrorSuccess || value == NULL) return nil;
    return CFBridgingRelease(value);
}

static NSString *StringAttribute(AXUIElementRef element, CFStringRef attribute) {
    id value = CopyAttribute(element, attribute);
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) return [value stringValue];
    return @"";
}

static BOOL BooleanAttribute(AXUIElementRef element, CFStringRef attribute) {
    id value = CopyAttribute(element, attribute);
    if ([value isKindOfClass:NSNumber.class]) return [value boolValue];
    if ([value isKindOfClass:NSString.class]) {
        NSString *normalized = [value lowercaseString];
        return [normalized isEqualToString:@"true"] || [normalized isEqualToString:@"selected"] || [normalized isEqualToString:@"on"] || [normalized isEqualToString:@"1"];
    }
    return NO;
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

static NSArray<AXNode *> *CollectElements(AXUIElementRef root, pid_t pid, NSString *processName, NSString *windowTitle, AXUIElementRef focusedWindow) {
    NSMutableArray<AXNode *> *result = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *stack = [NSMutableArray arrayWithObject:@{@"element": (__bridge id)root, @"depth": @0}];
    NSMutableSet<NSNumber *> *visited = [NSMutableSet set];
    while (stack.count > 0) {
        NSDictionary *entry = stack.lastObject;
        [stack removeLastObject];
        AXUIElementRef element = (__bridge AXUIElementRef)entry[@"element"];
        NSInteger depth = [entry[@"depth"] integerValue];
        if (depth > MaxTraversalDepth || result.count >= MaxVisitedElements) continue;
        NSNumber *identity = @(CFHash(element));
        if ([visited containsObject:identity]) continue;
        [visited addObject:identity];
        AXNode *node = [AXNode new];
        node.elementObject = CFBridgingRelease(CFRetain(element));
        node.pid = pid;
        node.processName = processName;
        node.windowTitle = windowTitle;
        node.role = StringAttribute(element, kAXRoleAttribute);
        node.identifier = StringAttribute(element, kAXIdentifierAttribute);
        node.title = StringAttribute(element, kAXTitleAttribute);
        node.nodeDescription = StringAttribute(element, kAXDescriptionAttribute);
        node.helpText = StringAttribute(element, kAXHelpAttribute);
        node.value = StringAttribute(element, kAXValueAttribute);
        node.actions = Actions(element);
        node.depth = depth;
        node.focusedWindow = SameElement(focusedWindow, root);
        node.selected = BooleanAttribute(element, kAXSelectedAttribute);
        [result addObject:node];
        for (id childObject in [ElementArrayAttribute(element, kAXChildrenAttribute) reverseObjectEnumerator]) {
            if (CFGetTypeID((__bridge CFTypeRef)childObject) != AXUIElementGetTypeID()) continue;
            [stack addObject:@{@"element": childObject, @"depth": @(depth + 1)}];
        }
    }
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

static BOOL ContainsAny(NSString *text, NSArray<NSString *> *labels) {
    NSString *normalized = Normalized(text);
    for (NSString *label in labels) if ([normalized containsString:Normalized(label)]) return YES;
    return NO;
}

static BOOL EqualsAny(NSString *text, NSArray<NSString *> *labels) {
    NSString *normalized = Normalized(text);
    for (NSString *label in labels) if ([normalized isEqualToString:Normalized(label)]) return YES;
    return NO;
}

static BOOL ActionFieldMatches(NSString *field, NSArray<NSString *> *labels) {
    NSString *normalized = Normalized(field);
    for (NSString *labelValue in labels) {
        NSString *label = Normalized(labelValue);
        if ([normalized isEqualToString:label]) return YES;
        for (NSString *separator in @[@" (", @", ", @" | "]) {
            if ([normalized hasPrefix:[label stringByAppendingString:separator]]) return YES;
        }
    }
    return NO;
}

static BOOL NodeMatchesAction(AXNode *node, NSArray<NSString *> *labels) {
    for (NSString *field in @[node.title, node.nodeDescription, node.helpText, node.value]) {
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
    if (!ContainsAny(node.searchableText, LauncherLabels())) return NSIntegerMin;
    NSInteger score = BaseControlScore(node);
    if (score == NSIntegerMin) return score;
    for (NSString *field in @[node.title, node.nodeDescription, node.helpText, node.value]) {
        if (EqualsAny(field, LauncherLabels())) { score += 80; break; }
    }
    if ([node.identifier.lowercaseString containsString:@"react"]) score += 30;
    return score;
}

static NSInteger ReactionScore(AXNode *node, NSDictionary *reaction) {
    NSArray<NSString *> *labels = reaction[@"labels"];
    if (!ContainsAny(node.searchableText, labels)) return NSIntegerMin;
    NSInteger score = BaseControlScore(node);
    if (score == NSIntegerMin) return score;
    for (NSString *label in labels) if ([node.searchableText isEqualToString:Normalized(label)]) score += 30;
    if ([node.identifier.lowercaseString containsString:[reaction[@"name"] lowercaseString]]) score += 20;
    return score;
}

static NSInteger MicrophoneScore(AXNode *node) {
    if (!NodeMatchesAction(node, MuteLabels()) && !NodeMatchesAction(node, UnmuteLabels())) return NSIntegerMin;
    NSInteger score = BaseControlScore(node);
    if ([node.identifier.lowercaseString containsString:@"microphone"] || [node.identifier.lowercaseString containsString:@"mic-"]) score += 30;
    if ([node.searchableText containsString:@"settings"]) score -= 120;
    return score;
}

static NSInteger CameraScore(AXNode *node) {
    if (!NodeMatchesAction(node, CameraOnLabels()) && !NodeMatchesAction(node, CameraOffLabels())) return NSIntegerMin;
    NSInteger score = BaseControlScore(node);
    if ([node.identifier.lowercaseString containsString:@"camera"] || [node.identifier.lowercaseString containsString:@"video"]) score += 30;
    if ([node.searchableText containsString:@"settings"] || [node.searchableText containsString:@"preview"]) score -= 120;
    return score;
}

static NSInteger HandScore(AXNode *node) {
    if (!NodeMatchesAction(node, RaiseHandLabels()) && !NodeMatchesAction(node, LowerHandLabels())) return NSIntegerMin;
    NSInteger score = BaseControlScore(node);
    if ([node.identifier.lowercaseString containsString:@"hand"]) score += 30;
    return score;
}

static NSInteger LeaveScore(AXNode *node) {
    NSString *text = node.searchableText;
    if ([text containsString:@"end meeting"] || [text containsString:@"for all"] || [text containsString:@"decline"] || [text containsString:@"dismiss"]) return NSIntegerMin;
    if (!NodeMatchesAction(node, LeaveLabels())) return NSIntegerMin;
    NSInteger score = BaseControlScore(node);
    if ([node.identifier.lowercaseString containsString:@"leave"] || [node.identifier.lowercaseString containsString:@"hangup"]) score += 35;
    return score;
}

static NSInteger EffectsLauncherScore(AXNode *node) {
    if (!NodeMatchesAction(node, EffectsLauncherLabels())) return NSIntegerMin;
    NSInteger score = BaseControlScore(node);
    NSString *identifier = node.identifier.lowercaseString;
    if ([identifier containsString:@"effect"] || [identifier containsString:@"background"]) score += 35;
    return score;
}

static NSInteger BlurOptionScore(AXNode *node) {
    if (!NodeMatchesAction(node, BlurLabels())) return NSIntegerMin;
    NSInteger score = BaseControlScore(node);
    NSString *identifier = node.identifier.lowercaseString;
    if ([identifier containsString:@"blur"] || [identifier containsString:@"effect"] || [identifier containsString:@"background"]) score += 35;
    if (node.selected) score += 15;
    return score;
}

static NSInteger NoEffectOptionScore(AXNode *node) {
    if (!NodeMatchesAction(node, NoEffectLabels())) return NSIntegerMin;
    NSInteger score = BaseControlScore(node);
    NSString *identifier = node.identifier.lowercaseString;
    if ([identifier containsString:@"effect"] || [identifier containsString:@"background"] || [identifier containsString:@"none"]) score += 35;
    if (node.selected) score += 15;
    return score;
}

static NSInteger ApplyScore(AXNode *node) {
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

    BOOL blurAmbiguous = NO, noneAmbiguous = NO;
    AXNode *blur = BestUniqueNode(elements, ^NSInteger(AXNode *node) { return BlurOptionScore(node); }, &blurAmbiguous);
    AXNode *none = BestUniqueNode(elements, ^NSInteger(AXNode *node) { return NoEffectOptionScore(node); }, &noneAmbiguous);
    NSString *blurState = @"unavailable";
    if (meetingActive && (effects || blur || none || effectsAmbiguous)) blurState = @"unknown";
    if (!blurAmbiguous && blur.selected) blurState = @"on";
    if (!noneAmbiguous && none.selected) blurState = @"off";
    return @{@"meetingActive": @(meetingActive), @"microphone": microphoneState, @"camera": cameraState, @"backgroundBlur": blurState, @"hand": handState};
}

static NSMutableDictionary *ResultForScan(NSDictionary *scan, NSString *command, BOOL changed) {
    NSMutableDictionary *result = [StateSnapshot(scan) mutableCopy];
    result[@"command"] = command;
    result[@"changed"] = @(changed);
    return result;
}

static void WriteJSON(NSDictionary *object) {
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

static BOOL PostTeamsShortcut(pid_t pid, CGKeyCode keyCode) {
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
    CGEventFlags flags = kCGEventFlagMaskCommand | kCGEventFlagMaskShift;
    CGEventSetFlags(down, flags);
    CGEventSetFlags(up, flags);
    CGEventPostToPid(pid, down);
    CGEventPostToPid(pid, up);
    CFRelease(down);
    CFRelease(up);
    return YES;
}

typedef NSString *(^NodeStateReader)(AXNode *node);

static int PerformDesiredControl(NSString *command, NSString *desiredState, NSString *family, CGKeyCode shortcutKey, NodeScorer scorer, NodeStateReader stateReader) {
    NSDictionary *initialScan = ScanTeams();
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
    ScrollNodeIntoView(control);
    AXError pressError = PressNode(control);
    BOOL usedShortcut = NO;
    if (pressError != kAXErrorSuccess && ShortcutFallbackEnabled(family)) usedShortcut = PostTeamsShortcut(control.pid, shortcutKey);
    if (pressError != kAXErrorSuccess && !usedShortcut) {
        WriteJSON(ResultForScan(initialScan, command, NO));
        fprintf(stderr, "Could not invoke the %s control: %s.\n", family.UTF8String, AXErrorDescription(pressError).UTF8String);
        return 12;
    }
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:VerificationTimeout];
    NSDictionary *currentScan;
    do {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.12]];
        currentScan = ScanTeams();
        BOOL currentAmbiguous = NO;
        AXNode *currentControl = BestUniqueNode(currentScan[@"elements"], scorer, &currentAmbiguous);
        if (!currentAmbiguous && currentControl && [[stateReader(currentControl) lowercaseString] isEqualToString:desiredState]) {
            WriteJSON(ResultForScan(currentScan, command, YES));
            return 0;
        }
    } while (deadline.timeIntervalSinceNow > 0);
    WriteJSON(ResultForScan(currentScan, command, YES));
    fprintf(stderr, "Teams accepted the %s action, but the requested state was not confirmed.\n", family.UTF8String);
    return 13;
}

static int PerformLeave(void) {
    NSDictionary *initialScan = ScanTeams();
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

static AXNode *FindEffectOption(NSArray<AXNode *> *elements, BOOL enable, NSSet<NSNumber *> *initialIdentities, BOOL *ambiguous) {
    NodeScorer baseScorer = enable
        ? ^NSInteger(AXNode *node) { return BlurOptionScore(node); }
        : ^NSInteger(AXNode *node) { return NoEffectOptionScore(node); };
    return BestUniqueNode(elements, ^NSInteger(AXNode *node) {
        NSInteger score = baseScorer(node);
        if (score == NSIntegerMin) return score;
        BOOL isNew = ![initialIdentities containsObject:@(CFHash(node.element))];
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
    BOOL ambiguous = NO;
    AXNode *launcher = BestUniqueNode(initialScan[@"elements"], ^NSInteger(AXNode *node) { return EffectsLauncherScore(node); }, &ambiguous);
    if (ambiguous) {
        WriteJSON(ResultForScan(initialScan, command, NO));
        fprintf(stderr, "More than one equally plausible video-effects control was exposed.\n");
        return 11;
    }
    if (!launcher) {
        WriteJSON(ResultForScan(initialScan, command, NO));
        fprintf(stderr, "Video effects are unavailable or the effects control is not exposed.\n");
        return 14;
    }
    NSMutableSet<NSNumber *> *initialIdentities = [NSMutableSet set];
    for (AXNode *node in initialScan[@"elements"]) [initialIdentities addObject:@(CFHash(node.element))];
    ScrollNodeIntoView(launcher);
    AXError launcherError = PressNode(launcher);
    if (launcherError != kAXErrorSuccess) {
        WriteJSON(ResultForScan(initialScan, command, NO));
        fprintf(stderr, "Could not open video effects: %s.\n", AXErrorDescription(launcherError).UTF8String);
        return 12;
    }
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:MenuTimeout];
    NSDictionary *currentScan;
    AXNode *target = nil;
    do {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.12]];
        currentScan = ScanTeams();
        BOOL targetAmbiguous = NO;
        target = FindEffectOption(currentScan[@"elements"], enable, initialIdentities, &targetAmbiguous);
        if (targetAmbiguous) {
            WriteJSON(ResultForScan(currentScan, command, NO));
            fprintf(stderr, "The requested video effect was ambiguous.\n");
            return 11;
        }
    } while (!target && deadline.timeIntervalSinceNow > 0);
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
        BOOL isNew = ![initialIdentities containsObject:@(CFHash(node.element))];
        NSString *identifier = node.identifier.lowercaseString;
        BOOL effectIdentifier = [identifier containsString:@"effect"] || [identifier containsString:@"background"];
        if (!isNew && !effectIdentifier) return NSIntegerMin;
        if (isNew) score += 60;
        return score;
    }, &applyAmbiguous);
    if (apply && !applyAmbiguous) PressNode(apply);
    deadline = [NSDate dateWithTimeIntervalSinceNow:1.2];
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

static AXNode *FindReactionTarget(NSDictionary *reaction, AXNode *launcher, NSSet<NSNumber *> *initialIdentities, NSTimeInterval timeout, BOOL fullScan) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    AXNode *target = nil;
    do {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.08]];
        NSArray<AXNode *> *currentElements = (fullScan ? ScanTeams() : ScanTeamsForPID(launcher.pid))[@"elements"];
        target = BestNode(currentElements, ^NSInteger(AXNode *node) {
            NSInteger score = ReactionScore(node, reaction);
            if (score == NSIntegerMin) return score;
            if (node.pid == launcher.pid) score += 20;
            if (initialIdentities && ![initialIdentities containsObject:@(CFHash(node.element))]) score += 80;
            return score;
        });
    } while (!target && deadline.timeIntervalSinceNow > 0);
    return target;
}

static int PrepareReactionSession(NSDictionary *reaction, ReactionSession **sessionOut) {
    NSDictionary *initialScan = ScanTeams();
    if ([initialScan[@"applicationCount"] integerValue] == 0) return 2;
    BOOL ambiguous = NO;
    AXNode *launcher = BestUniqueNode(initialScan[@"elements"], ^NSInteger(AXNode *node) { return LauncherScore(node); }, &ambiguous);
    if (ambiguous || !launcher) return ambiguous ? 11 : 3;
    NSMutableSet<NSNumber *> *initialIdentities = [NSMutableSet set];
    for (AXNode *node in initialScan[@"elements"]) [initialIdentities addObject:@(CFHash(node.element))];
    ScrollNodeIntoView(launcher);
    if (PressNode(launcher) != kAXErrorSuccess) return 4;
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

static int SendReaction(NSDictionary *reaction, NSString *commandName) {
    ReactionSession *session = nil;
    int prepareStatus = PrepareReactionSession(reaction, &session);
    if (prepareStatus != 0) {
        fprintf(stderr, "Could not prepare the requested Teams reaction.\n");
        return prepareStatus;
    }
    AXError reactionError = PressNode(session.target);
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
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return !BurstStopRequested();
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
        AXError firstError = PressNode(session.target);
        if (firstError == kAXErrorSuccess) {
            accepted = 1;
            if (!WaitForBurstTime(start, BurstHoldThreshold)) {
                stopReason = @"key-up";
            } else {
                NSTimeInterval interval = 1.0 / (NSTimeInterval)rate;
                NSTimeInterval nextAttempt = BurstHoldThreshold;
                while (YES) {
                    NSTimeInterval elapsed = -start.timeIntervalSinceNow;
                    if (elapsed >= BurstDurationLimit) { stopReason = @"duration-limit"; break; }
                    if (attempted >= BurstMaximumAttempts) { stopReason = @"count-limit"; break; }
                    if (!WaitForBurstTime(start, nextAttempt)) { stopReason = @"key-up"; break; }
                    attempted += 1;
                    AXError reactionError = PressNode(session.target);
                    if (reactionError != kAXErrorSuccess) {
                        AXError reacquireError = ReacquireReactionTarget(session);
                        if (reacquireError == kAXErrorSuccess) reactionError = PressNode(session.target);
                    }
                    if (reactionError != kAXErrorSuccess) {
                        stopReason = @"selection-error";
                        exitStatus = 6;
                        break;
                    }
                    accepted += 1;
                    nextAttempt += interval;
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
        NSSet<NSString *> *singleArgumentCommands = [NSSet setWithArray:@[@"status", @"inspect", @"inspect-controls", @"mute", @"unmute", @"camera-on", @"camera-off", @"blur-on", @"blur-off", @"hand-raise", @"hand-lower", @"leave"]];
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
        if ([command isEqualToString:@"inspect"]) return Inspect();
        if ([command isEqualToString:@"inspect-controls"]) return InspectControls();
        if ([command isEqualToString:@"status"]) {
            NSDictionary *scan = ScanTeams();
            if ([scan[@"applicationCount"] integerValue] == 0) {
                WriteJSON(ResultForScan(scan, command, NO));
                fprintf(stderr, "Microsoft Teams is not running.\n");
                return 2;
            }
            WriteJSON(ResultForScan(scan, command, NO));
            return 0;
        }
        if ([command isEqualToString:@"mute"]) return PerformDesiredControl(command, @"muted", @"microphone", 46, ^NSInteger(AXNode *node) { return MicrophoneScore(node); }, ^NSString *(AXNode *node) { return MicrophoneStateForNode(node); });
        if ([command isEqualToString:@"unmute"]) return PerformDesiredControl(command, @"unmuted", @"microphone", 46, ^NSInteger(AXNode *node) { return MicrophoneScore(node); }, ^NSString *(AXNode *node) { return MicrophoneStateForNode(node); });
        if ([command isEqualToString:@"camera-on"]) return PerformDesiredControl(command, @"on", @"camera", 31, ^NSInteger(AXNode *node) { return CameraScore(node); }, ^NSString *(AXNode *node) { return CameraStateForNode(node); });
        if ([command isEqualToString:@"camera-off"]) return PerformDesiredControl(command, @"off", @"camera", 31, ^NSInteger(AXNode *node) { return CameraScore(node); }, ^NSString *(AXNode *node) { return CameraStateForNode(node); });
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
    }
}
#endif
