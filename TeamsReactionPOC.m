#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Foundation/Foundation.h>

static const NSInteger MaxTraversalDepth = 40;
static const NSInteger MaxVisitedElements = 30000;
static const NSTimeInterval MenuTimeout = 4.0;

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
    return [self.actions containsObject:(__bridge NSString *)kAXPressAction];
}
@end

static NSDictionary<NSString *, NSDictionary *> *ReactionDefinitions(void) {
    return @{
        @"like": @{
            @"name": @"Like",
            @"labels": @[@"like", @"thumbs up", @"thumb up", @"vind ik leuk", @"duim omhoog", @"gefällt mir", @"j'aime", @"me gusta"]
        },
        @"love": @{
            @"name": @"Love",
            @"labels": @[@"love", @"heart", @"hart", @"liebe", @"coeur", @"cœur", @"corazón", @"corazon"]
        },
        @"applause": @{
            @"name": @"Applause",
            @"labels": @[@"applause", @"clap", @"clapping", @"applaus", @"applaudissements", @"aplausos"]
        },
        @"laugh": @{
            @"name": @"Laugh",
            @"labels": @[@"laugh", @"laughing", @"lachen", @"rire", @"risa"]
        },
        @"surprise": @{
            @"name": @"Surprise",
            @"labels": @[@"surprise", @"surprised", @"wow", @"verrast", @"überrascht", @"surpris", @"sorpresa"]
        }
    };
}

static NSArray<NSString *> *LauncherLabels(void) {
    return @[
        @"react", @"reaction", @"reactions",
        @"reageren", @"reactie", @"reacties",
        @"réagir", @"réaction", @"réactions",
        @"reagieren", @"reaktion", @"reaktionen",
        @"reaccionar", @"reacción", @"reacciones"
    ];
}

static void PrintUsage(const char *executablePath) {
    NSString *executable = [[NSString stringWithUTF8String:executablePath] lastPathComponent];
    printf("Teams reaction accessibility proof of concept\n\n");
    printf("Usage:\n");
    printf("  %s inspect\n", executable.UTF8String);
    printf("  %s like\n", executable.UTF8String);
    printf("  %s love\n", executable.UTF8String);
    printf("  %s applause\n", executable.UTF8String);
    printf("  %s laugh\n", executable.UTF8String);
    printf("  %s surprise\n\n", executable.UTF8String);
    printf("Run inspect while you are in a Teams meeting. It does not click anything.\n");
    printf("Reaction commands open the Teams reaction menu and press one reaction.\n");
}

static id CopyAttribute(AXUIElementRef element, CFStringRef attribute) {
    CFTypeRef value = NULL;
    if (AXUIElementCopyAttributeValue(element, attribute, &value) != kAXErrorSuccess || value == NULL) {
        return nil;
    }
    return CFBridgingRelease(value);
}

static NSString *StringAttribute(AXUIElementRef element, CFStringRef attribute) {
    id value = CopyAttribute(element, attribute);
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) return [value stringValue];
    return @"";
}

static NSArray *ElementArrayAttribute(AXUIElementRef element, CFStringRef attribute) {
    id value = CopyAttribute(element, attribute);
    if ([value isKindOfClass:NSArray.class]) return value;
    return @[];
}

static NSArray<NSString *> *Actions(AXUIElementRef element) {
    CFArrayRef names = NULL;
    if (AXUIElementCopyActionNames(element, &names) != kAXErrorSuccess || names == NULL) {
        return @[];
    }
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
        NSString *name = application.localizedName.lowercaseString ?: @"";
        NSString *executable = application.executableURL.lastPathComponent.lowercaseString ?: @"";

        BOOL isTeams = [bundleID isEqualToString:@"com.microsoft.teams2"]
            || [bundleID containsString:@"msteams"]
            || [bundleID containsString:@"microsoft.teams"]
            || [name isEqualToString:@"microsoft teams"]
            || [name isEqualToString:@"msteams"]
            || [executable isEqualToString:@"msteams"];

        if (!isTeams || application.processIdentifier <= 0) continue;
        NSNumber *pidNumber = @(application.processIdentifier);
        if ([seen containsObject:pidNumber]) continue;
        [seen addObject:pidNumber];

        AXUIElementRef root = AXUIElementCreateApplication(application.processIdentifier);
        id rootObject = CFBridgingRelease(root);
        [result addObject:@{
            @"pid": pidNumber,
            @"name": application.localizedName ?: application.executableURL.lastPathComponent ?: @"Teams",
            @"root": rootObject
        }];
    }
    return result;
}

static void EncourageAccessibilityTree(AXUIElementRef application) {
    AXUIElementSetAttributeValue(application, CFSTR("AXManualAccessibility"), kCFBooleanTrue);
    AXUIElementSetAttributeValue(application, CFSTR("AXEnhancedUserInterface"), kCFBooleanTrue);
}

static NSArray<AXNode *> *CollectElements(
    AXUIElementRef root,
    pid_t pid,
    NSString *processName,
    NSString *windowTitle,
    AXUIElementRef focusedWindow
) {
    NSMutableArray<AXNode *> *result = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *stack = [NSMutableArray arrayWithObject:@{
        @"element": (__bridge id)root,
        @"depth": @0
    }];
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
        [result addObject:node];

        NSArray *children = ElementArrayAttribute(element, kAXChildrenAttribute);
        for (id childObject in children.reverseObjectEnumerator) {
            if (CFGetTypeID((__bridge CFTypeRef)childObject) != AXUIElementGetTypeID()) continue;
            [stack addObject:@{
                @"element": childObject,
                @"depth": @(depth + 1)
            }];
        }
    }
    return result;
}

static NSDictionary *ScanTeams(void) {
    NSArray<NSDictionary *> *applications = CandidateApplications();
    NSMutableArray<AXNode *> *allElements = [NSMutableArray array];

    for (NSDictionary *application in applications) {
        pid_t pid = [application[@"pid"] intValue];
        NSString *name = application[@"name"];
        AXUIElementRef root = (__bridge AXUIElementRef)application[@"root"];
        EncourageAccessibilityTree(root);

        id focusedWindowObject = CopyAttribute(root, kAXFocusedWindowAttribute);
        AXUIElementRef focusedWindow = NULL;
        if (focusedWindowObject && CFGetTypeID((__bridge CFTypeRef)focusedWindowObject) == AXUIElementGetTypeID()) {
            focusedWindow = (__bridge AXUIElementRef)focusedWindowObject;
        }
        NSArray *windows = ElementArrayAttribute(root, kAXWindowsAttribute);
        if (windows.count == 0) {
            [allElements addObjectsFromArray:CollectElements(root, pid, name, @"<application root>", focusedWindow)];
            continue;
        }

        for (id windowObject in windows) {
            AXUIElementRef window = (__bridge AXUIElementRef)windowObject;
            NSString *windowTitle = StringAttribute(window, kAXTitleAttribute);
            if (windowTitle.length == 0) windowTitle = @"<untitled window>";
            [allElements addObjectsFromArray:CollectElements(window, pid, name, windowTitle, focusedWindow)];
        }
    }

    return @{
        @"applicationCount": @(applications.count),
        @"elements": allElements
    };
}

static BOOL ContainsAny(NSString *text, NSArray<NSString *> *labels) {
    for (NSString *label in labels) {
        if ([text containsString:label.lowercaseString]) return YES;
    }
    return NO;
}

static BOOL EqualsAny(NSString *text, NSArray<NSString *> *labels) {
    NSString *normalized = text.lowercaseString;
    for (NSString *label in labels) {
        if ([normalized isEqualToString:label.lowercaseString]) return YES;
    }
    return NO;
}

static NSInteger LauncherScore(AXNode *node) {
    if (!ContainsAny(node.searchableText, LauncherLabels())) return NSIntegerMin;
    NSInteger score = 0;
    if (node.canPress) score += 60;
    if ([node.role isEqualToString:(__bridge NSString *)kAXButtonRole]) score += 30;
    if (node.focusedWindow) score += 15;
    for (NSString *field in @[node.title, node.nodeDescription, node.helpText, node.value]) {
        if (EqualsAny(field, LauncherLabels())) {
            score += 80;
            break;
        }
    }
    if ([node.identifier.lowercaseString containsString:@"react"]) score += 30;
    if ([node.searchableText containsString:@"message"] || [node.searchableText containsString:@"chat"]) score -= 120;
    return score - node.depth;
}

static NSInteger ReactionScore(AXNode *node, NSDictionary *reaction) {
    NSArray<NSString *> *labels = reaction[@"labels"];
    NSString *text = node.searchableText;
    if (!ContainsAny(text, labels)) return NSIntegerMin;
    NSInteger score = 0;
    if (node.canPress) score += 60;
    if ([node.role isEqualToString:(__bridge NSString *)kAXButtonRole]) score += 30;
    for (NSString *label in labels) {
        if ([text isEqualToString:label.lowercaseString]) score += 30;
    }
    if ([node.identifier.lowercaseString containsString:[reaction[@"name"] lowercaseString]]) score += 20;
    return score - node.depth;
}

typedef NSInteger (^NodeScorer)(AXNode *node);

static AXNode *BestNode(NSArray<AXNode *> *nodes, NodeScorer scorer) {
    AXNode *best = nil;
    NSInteger bestScore = 0;
    for (AXNode *node in nodes) {
        NSInteger score = scorer(node);
        if (score > bestScore) {
            best = node;
            bestScore = score;
        }
    }
    return best;
}

static AXError PressNode(AXNode *node) {
    if ([node.actions containsObject:(__bridge NSString *)kAXPressAction]) {
        return AXUIElementPerformAction(node.element, kAXPressAction);
    }
    if ([node.actions containsObject:(__bridge NSString *)kAXShowMenuAction]) {
        return AXUIElementPerformAction(node.element, kAXShowMenuAction);
    }
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

    fprintf(stderr,
        "Accessibility permission is required.\n\n"
        "macOS should have opened System Settings. Under Privacy & Security >\n"
        "Accessibility, enable the new teams-reaction entry or the terminal application\n"
        "running it. Then quit and reopen that terminal before trying again.\n\n"
        "If access still fails, remove the enabled entry, add it again, and rerun the tool.\n");
    return NO;
}

static int Inspect(void) {
    NSDictionary *scan = ScanTeams();
    NSInteger applicationCount = [scan[@"applicationCount"] integerValue];
    NSArray<AXNode *> *elements = scan[@"elements"];
    if (applicationCount == 0) {
        fprintf(stderr, "Microsoft Teams is not running. Start Teams and join a meeting first.\n");
        return 2;
    }

    printf("Found %ld Teams process(es) and inspected %ld accessible elements.\n",
        (long)applicationCount, (long)elements.count);

    NSMutableArray<AXNode *> *relevant = [NSMutableArray array];
    for (AXNode *node in elements) {
        if (!node.canPress) continue;
        BOOL matches = ContainsAny(node.searchableText, LauncherLabels());
        if (!matches) {
            for (NSDictionary *reaction in ReactionDefinitions().allValues) {
                if (ContainsAny(node.searchableText, reaction[@"labels"])) {
                    matches = YES;
                    break;
                }
            }
        }
        if (matches) [relevant addObject:node];
    }

    if (relevant.count == 0) {
        printf("\nNo obvious reaction controls were exposed. Make sure you are inside an active\n");
        printf("meeting and that the meeting controls are visible. The pressable controls below\n");
        printf("may help diagnose localized or changed labels:\n\n");

        NSInteger printed = 0;
        NSInteger pressableCount = 0;
        for (AXNode *node in elements) {
            if (!node.canPress) continue;
            pressableCount += 1;
            if (printed >= 200) continue;
            printf("[%s] [%s] %s\n", node.processName.UTF8String, node.role.UTF8String, node.displayText.UTF8String);
            printed += 1;
        }
        if (pressableCount > 200) printf("... output limited to the first 200 pressable elements\n");
        return 3;
    }

    printf("\nPossible reaction controls:\n");
    for (AXNode *node in relevant) {
        printf("[%s] window=\"%s\" role=%s actions=%s\n",
            node.processName.UTF8String,
            node.windowTitle.UTF8String,
            node.role.UTF8String,
            [node.actions componentsJoinedByString:@","].UTF8String);
        printf("  %s\n", node.displayText.UTF8String);
    }

    AXNode *launcher = BestNode(elements, ^NSInteger(AXNode *node) {
        return LauncherScore(node);
    });
    if (launcher) {
        printf("\nBest reaction-menu candidate:\n  %s\n  Window: %s\n",
            launcher.displayText.UTF8String, launcher.windowTitle.UTF8String);
        printf("\nInspection only: nothing was clicked.\n");
        return 0;
    }

    printf("\nReaction-related controls were found, but none looked pressable enough to use safely.\n");
    return 4;
}

static int SendReaction(NSDictionary *reaction) {
    NSDictionary *initialScan = ScanTeams();
    NSInteger applicationCount = [initialScan[@"applicationCount"] integerValue];
    NSArray<AXNode *> *elements = initialScan[@"elements"];
    if (applicationCount == 0) {
        fprintf(stderr, "Microsoft Teams is not running. Start Teams and join a meeting first.\n");
        return 2;
    }

    AXNode *launcher = BestNode(elements, ^NSInteger(AXNode *node) {
        return LauncherScore(node);
    });
    if (!launcher) {
        fprintf(stderr,
            "Could not find a pressable Teams reaction-menu button.\n"
            "Run `teams-reaction inspect` while meeting controls are visible.\n");
        return 3;
    }

    printf("Opening reaction menu using: %s\n", launcher.displayText.UTF8String);
    NSMutableSet<NSNumber *> *initialElementIdentities = [NSMutableSet set];
    for (AXNode *node in elements) {
        [initialElementIdentities addObject:@(CFHash(node.element))];
    }
    AXError launcherError = PressNode(launcher);
    if (launcherError != kAXErrorSuccess) {
        fprintf(stderr, "Could not open reaction menu: %s.\n", AXErrorDescription(launcherError).UTF8String);
        return 4;
    }

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:MenuTimeout];
    __block AXNode *target = nil;
    do {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.12]];
        NSArray<AXNode *> *currentElements = ScanTeams()[@"elements"];
        target = BestNode(currentElements, ^NSInteger(AXNode *node) {
            NSInteger score = ReactionScore(node, reaction);
            if (score == NSIntegerMin) return score;
            if (node.pid == launcher.pid) score += 20;
            if (![initialElementIdentities containsObject:@(CFHash(node.element))]) score += 80;
            return score;
        });
    } while (!target && deadline.timeIntervalSinceNow > 0);

    NSString *reactionName = reaction[@"name"];
    if (!target) {
        fprintf(stderr,
            "The reaction menu opened, but %s was not found within %ld seconds.\n"
            "Close the menu if it is still open, then run `teams-reaction inspect` and review its labels.\n",
            reactionName.UTF8String, (long)MenuTimeout);
        return 5;
    }

    printf("Pressing reaction using: %s\n", target.displayText.UTF8String);
    AXError reactionError = PressNode(target);
    if (reactionError != kAXErrorSuccess) {
        fprintf(stderr, "Could not press %s: %s.\n",
            reactionName.UTF8String, AXErrorDescription(reactionError).UTF8String);
        return 6;
    }

    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.35]];
    printf("Accessibility accepted both actions for %s.\n", reactionName.UTF8String);
    printf("Verify that the reaction appeared in Teams or was seen by another participant.\n");
    return 0;
}

#ifndef TEAMS_REACTION_TESTING
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) {
            PrintUsage(argv[0]);
            return 64;
        }

        NSString *command = [[NSString stringWithUTF8String:argv[1]] lowercaseString];
        if ([command isEqualToString:@"help"] || [command isEqualToString:@"--help"] || [command isEqualToString:@"-h"]) {
            PrintUsage(argv[0]);
            return 0;
        }

        if (!RequireAccessibilityPermission()) return 1;
        if ([command isEqualToString:@"inspect"]) return Inspect();

        NSDictionary *reaction = ReactionDefinitions()[command];
        if (!reaction) {
            fprintf(stderr, "Unknown reaction: %s\n\n", command.UTF8String);
            PrintUsage(argv[0]);
            return 64;
        }
        return SendReaction(reaction);
    }
}
#endif
