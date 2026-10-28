#define TEAMS_REACTION_TESTING 1
#import "../TeamsReactionPOC.m"

// Distinct provider elements may share a hash, including a toolbar ancestor.
@interface CollidingElement : NSObject
@property(nonatomic, strong) NSArray *children;
@property(nonatomic, strong) AXNode *control;
@end
@implementation CollidingElement
- (NSUInteger)hash { return 7; }
@end

static AXNode *Button(NSString *title, NSString *identifier, NSInteger depth) {
    AXNode *node = [AXNode new];
    node.identifier = identifier;
    node.title = title;
    node.nodeDescription = @"";
    node.helpText = @"";
    node.customDescription = @"";
    node.value = @"";
    node.role = (__bridge NSString *)kAXButtonRole;
    node.actions = @[(__bridge NSString *)kAXPressAction];
    node.depth = depth;
    node.focusedWindow = YES;
    node.processName = @"Microsoft Teams";
    node.windowTitle = @"Echo | Microsoft Teams";
    return node;
}

static void Expect(BOOL condition, NSString *message, int *failures) {
    if (condition) return;
    fprintf(stderr, "FAIL: %s\n", message.UTF8String);
    *failures += 1;
}

int main(void) {
    @autoreleasepool {
        int failures = 0;

        __block NSInteger dismissals = 0;
        DismissPickerUntilGone(^{ dismissals += 1; }, ^BOOL { return dismissals < 2; });
        Expect(dismissals == 2, @"picker cleanup must retry an ignored Escape and stop once dismissed", &failures);
        dismissals = 0;
        DismissPickerUntilGone(^{ dismissals += 1; }, ^BOOL { return YES; });
        Expect(dismissals == 3, @"picker cleanup retries must remain bounded", &failures);
        dismissals = 0;
        DismissPickerUntilGone(^{ dismissals += 1; }, ^BOOL { return NO; });
        Expect(dismissals == 1, @"confirmed picker dismissal must not send another Escape", &failures);

        CollidingElement *root = [CollidingElement new];
        CollidingElement *content = [CollidingElement new];
        CollidingElement *toolbar = [CollidingElement new];
        CollidingElement *micElement = [CollidingElement new];
        CollidingElement *cameraElement = [CollidingElement new];
        CollidingElement *reactElement = [CollidingElement new];
        root.children = @[content, toolbar];
        toolbar.children = @[micElement, cameraElement, reactElement, root];
        micElement.control = Button(@"Unmute mic", @"microphone-button", 3);
        cameraElement.control = Button(@"Turn camera off", @"camera-button", 3);
        reactElement.control = Button(@"React", @"reaction-menu-button", 3);
        NSMutableArray *discovered = [NSMutableArray array];
        __block NSInteger visits = 0;
        WalkElements(root, ^NSArray *(id element, NSInteger depth) {
            (void)depth;
            visits += 1;
            CollidingElement *item = element;
            if (item.control) [discovered addObject:item.control];
            return item.children ?: @[];
        });
        Expect(visits == 6, @"traversal must visit distinct colliding elements once and stop real cycles", &failures);
        NSDictionary *collisionState = StateSnapshot(@{@"elements": discovered});
        Expect([collisionState[@"microphone"] isEqualToString:@"muted"] && [collisionState[@"camera"] isEqualToString:@"on"], @"hash collisions must not hide meeting controls behind a toolbar branch", &failures);
        Expect(BestNode(discovered, ^NSInteger(AXNode *node) { return LauncherScore(node); }) == reactElement.control, @"React must remain discoverable after colliding content elements", &failures);
        toolbar.children = @[];

        NSMutableArray<AXNode *> *busyWindow = [NSMutableArray array];
        for (NSInteger index = 0; index < 1000; index += 1) {
            AXNode *node = Button(@"Unrelated meeting content", @"unrelated-content", 12);
            if (index % 5 != 0) node.actions = @[];
            [busyWindow addObject:node];
        }
        [busyWindow addObject:Button(@"Unmute mic", @"microphone-button", 10)];
        [busyWindow addObject:Button(@"Turn camera off", @"camera-button", 10)];
        NSTimeInterval snapshotStart = NSProcessInfo.processInfo.systemUptime;
        MarkMeetingReactionPicker(busyWindow);
        NSDictionary *busyState = StateSnapshot(@{@"elements": busyWindow});
        NSTimeInterval snapshotElapsed = NSProcessInfo.processInfo.systemUptime - snapshotStart;
        Expect([busyState[@"microphone"] isEqualToString:@"muted"] && [busyState[@"camera"] isEqualToString:@"on"], @"large meeting scans must preserve exact control state", &failures);
        Expect(snapshotElapsed < 0.25, [NSString stringWithFormat:@"parsing a 1000-node meeting must stay below 250ms (was %.0fms)", snapshotElapsed * 1000], &failures);

        AXError missingAttribute = kAXErrorAttributeUnsupported;
        id missingValue = CFBridgingRelease(AXValueCreate(kAXValueAXErrorType, &missingAttribute));
        NSDictionary *attributes = AttributeDictionary(@[@"AXRole", @"AXIdentifier", @"AXDOMIdentifier", @"AXHelp", @"AXSelected"],
            @[@"AXButton", missingValue, @"microphone-button", NSNull.null, @YES]);
        AXNode *batchedNode = Button(@"", @"", 10);
        PopulateNode(batchedNode, attributes);
        Expect([batchedNode.identifier isEqualToString:@"microphone-button"], @"batched unsupported identifier must use the DOM identifier", &failures);
        Expect(batchedNode.selected && batchedNode.helpText.length == 0, @"batched errors and missing attributes must preserve safe defaults", &failures);

        AXNode *originalMic = Button(@"Unmute mic", @"microphone-button", 10);
        AXNode *originalCamera = Button(@"Turn camera off", @"camera-button", 10);
        NSDictionary *originalScan = @{@"applicationCount": @1, @"elements": @[originalMic, originalCamera, busyWindow[1]]};
        NSArray *stateControls = StateControlNodes(originalScan);
        __block NSInteger refreshedCount = 0;
        NSDictionary *refreshed = RefreshControlScan(originalScan, stateControls, ^AXNode *(AXNode *node) {
            refreshedCount += 1;
            return Button(node == originalMic ? @"Mute mic" : @"Turn camera off", node.identifier, node.depth);
        });
        Expect(refreshedCount == 2, @"verification must read state controls without walking unrelated meeting content", &failures);
        Expect([StateSnapshot(refreshed)[@"microphone"] isEqualToString:@"unmuted"], @"verification must use fresh microphone labels", &failures);
        Expect([StateSnapshot(refreshed)[@"camera"] isEqualToString:@"on"], @"verification must also refresh other state controls", &failures);
        Expect([StateSnapshot(originalScan)[@"microphone"] isEqualToString:@"muted"], @"verification must not overwrite the original snapshot", &failures);
        NSDictionary *disappeared = RefreshControlScan(originalScan, stateControls, ^AXNode *(AXNode *node) {
            return Button(@"", @"", node.depth);
        });
        Expect([StateSnapshot(disappeared)[@"microphone"] isEqualToString:@"unavailable"], @"replaced controls must not confirm cached state", &failures);
        NSDictionary *ambiguousScan = @{@"applicationCount": @1, @"elements": @[originalMic, Button(@"Unmute mic", @"other-microphone-button", 10)]};
        NSDictionary *ambiguousRefresh = RefreshControlScan(ambiguousScan, StateControlNodes(ambiguousScan), ^AXNode *(AXNode *node) {
            return Button(@"Mute mic", node.identifier, node.depth);
        });
        Expect([StateSnapshot(ambiguousRefresh)[@"microphone"] isEqualToString:@"unknown"], @"verification must retain every ambiguous candidate", &failures);

        Expect(ValidPersistentRequest(@{@"id": @1, @"command": @"mute", @"generation": @0, @"forceFresh": @YES}), @"persistent explicit mute request must validate", &failures);
        for (NSString *blocked in @[@"leave", @"hand-raise", @"burst", @"react", @"inspect", @"toggle", @"MUTE"]) {
            Expect(!ValidPersistentRequest(@{@"id": @1, @"command": blocked}), @"persistent protocol must reject commands outside its allow-list", &failures);
        }
        for (id badID in @[@YES, @0, @(-1), @1.5, @"1", NSNull.null]) {
            Expect(!ValidPersistentRequest(@{@"id": badID, @"command": @"status"}), @"persistent correlation IDs must be positive safe integers", &failures);
        }
        Expect(!ValidPersistentRequest(@{@"id": @1, @"command": @"mute", @"forceFresh": @"true"}), @"cache invalidation must require a boolean", &failures);
        Expect(!ValidPersistentGeneration(@{@"unexpected": @1}) && !ValidPersistentGeneration(@YES), @"generation tokens must reject non-integers and booleans", &failures);
        NSDictionary *unavailableState = @{@"microphone": @"unavailable", @"camera": @"unavailable"};
        Expect(PersistentNeedsDiscovery(YES, unavailableState, 0), @"a foreground request must rediscover an empty cache", &failures);
        Expect(!PersistentNeedsDiscovery(NO, unavailableState, 0), @"idle fallback must not repeatedly scan an empty meeting tree", &failures);
        Expect(!PersistentNeedsDiscovery(YES, @{@"microphone": @"muted", @"camera": @"on"}, 2), @"available warm controls must avoid full discovery", &failures);
        AXNode *cachedMic = Button(@"Unmute mic", @"microphone-button", 10);
        AXNode *freshMic = Button(@"Mute mic", @"microphone-button", 10);
        Expect(RefreshedControlsMatch(@[cachedMic], @[freshMic]), @"cached controls must accept a fresh state change", &failures);
        freshMic.identifier = @"replacement-button";
        Expect(!RefreshedControlsMatch(@[cachedMic], @[freshMic]), @"changed control identities must trigger rediscovery", &failures);
        freshMic.identifier = cachedMic.identifier; freshMic.title = @"Unrelated";
        Expect(!RefreshedControlsMatch(@[cachedMic], @[freshMic]), @"changed control meaning must trigger rediscovery", &failures);
        freshMic.title = @"Mute mic"; freshMic.actions = @[];
        Expect(!RefreshedControlsMatch(@[cachedMic], @[freshMic]), @"disappeared actions must trigger rediscovery", &failures);
        Expect(!RefreshedControlsMatch(@[cachedMic], @[]), @"missing cached controls must trigger rediscovery", &failures);

        Expect(BurstDurationLimit == 5.0, @"reaction hold guard must allow five seconds", &failures);
        Expect(BurstMaximumAttempts >= (NSInteger)ceil(BurstDurationLimit * BurstMaximumRate), @"attempt cap must allow the configured duration at the maximum supported rate", &failures);
        NSTimeInterval interval = 1.0 / 7.0;
        Expect(fabs(NextBurstAttemptTime(1.8, 7) - (1.8 + interval)) < 0.000001, @"slow picker setup must not create overdue reaction presses", &failures);
        Expect(fabs(NextBurstAttemptTime(0.01, 7) - BurstHoldThreshold) < 0.000001, @"fast setup must preserve the tap hold threshold", &failures);
        NSTimeInterval pressTime = BurstHoldThreshold;
        for (NSInteger repeat = 0; repeat < 7; repeat += 1) pressTime = NextBurstAttemptTime(pressTime, 7);
        Expect(fabs(pressTime - (BurstHoldThreshold + 1.0)) < 0.000001, @"seven repeat intervals must span one second", &failures);
        Expect(NextBurstAttemptTime(2.2, 7) > 2.34, @"a slow press or target recovery must not trigger catch-up presses", &failures);

        AXNode *raiseHand = Button(@"Raise your hand", @"", 10);
        AXNode *react = Button(@"React", @"", 10);
        AXNode *selected = BestNode(@[raiseHand, react], ^NSInteger(AXNode *node) {
            return LauncherScore(node);
        });

        if (selected != react) {
            fprintf(stderr,
                "FAIL: expected React, selected %s (Raise=%ld, React=%ld)\n",
                selected.displayText.UTF8String,
                (long)LauncherScore(raiseHand),
                (long)LauncherScore(react));
            failures += 1;
        }

        AXNode *recentItem = Button(@"Notes about reactions", @"_recentItemRequested:", 7);
        recentItem.role = (__bridge NSString *)kAXMenuItemRole;
        AXNode *anotherRecentItem = Button(@"Reaction planning", @"_recentItemRequested:", 7);
        anotherRecentItem.role = (__bridge NSString *)kAXMenuItemRole;
        Expect(LauncherScore(recentItem) == NSIntegerMin && LauncherScore(anotherRecentItem) == NSIntegerMin, @"recent-item menu entries must never be meeting React launchers", &failures);
        NSDictionary *recentOnly = @{@"applicationCount": @1, @"elements": @[recentItem, anotherRecentItem]};
        Expect(![StateSnapshot(recentOnly)[@"meetingActive"] boolValue], @"recent-item text must not invent an active meeting", &failures);
        AXNode *exactMenuItem = Button(@"React", @"_recentItemRequested:", 7);
        exactMenuItem.role = (__bridge NSString *)kAXMenuItemRole;
        Expect(LauncherScore(exactMenuItem) == NSIntegerMin, @"a menu entry named React is still not a meeting toolbar control", &failures);

        AXNode *chatReact = Button(@"React to this message", @"", 7);
        selected = BestNode(@[chatReact, react], ^NSInteger(AXNode *node) {
            return LauncherScore(node);
        });
        if (selected != react) {
            fprintf(stderr,
                "FAIL: expected meeting React, selected %s (Chat=%ld, Meeting=%ld)\n",
                selected.displayText.UTF8String,
                (long)LauncherScore(chatReact),
                (long)LauncherScore(react));
            failures += 1;
        }

        AXNode *mute = Button(@"Mute", @"microphone-button", 10);
        AXNode *chatMute = Button(@"Mute", @"chat-microphone-button", 7);
        selected = BestNode(@[chatMute, mute], ^NSInteger(AXNode *node) { return MicrophoneScore(node); });
        Expect(selected == mute, @"microphone scorer must reject a chat control", &failures);
        Expect([MicrophoneStateForNode(mute) isEqualToString:@"unmuted"], @"Mute action must mean the microphone is currently unmuted", &failures);

        AXNode *unmute = Button(@"Unmute", @"microphone-button", 10);
        Expect([MicrophoneStateForNode(unmute) isEqualToString:@"muted"], @"Unmute action must mean the microphone is currently muted", &failures);
        AXNode *muteMic = Button(@"Mute mic", @"", 20);
        AXNode *unmuteMic = Button(@"Unmute mic", @"", 20);
        Expect(MicrophoneScore(muteMic) > 0, @"live Mute mic label must be recognized", &failures);
        Expect([MicrophoneStateForNode(muteMic) isEqualToString:@"unmuted"], @"Mute mic must mean the microphone is currently unmuted", &failures);
        Expect(MicrophoneScore(unmuteMic) > 0, @"live Unmute mic label must be recognized", &failures);
        Expect([MicrophoneStateForNode(unmuteMic) isEqualToString:@"muted"], @"Unmute mic must mean the microphone is currently muted", &failures);
        AXNode *notificationMute = Button(@"Mute notification sounds", @"notification-mute", 8);
        Expect(MicrophoneScore(notificationMute) == NSIntegerMin, @"microphone scorer must require an exact action label", &failures);

        AXNode *cameraOn = Button(@"Turn camera on", @"camera-button", 10);
        AXNode *cameraOff = Button(@"Turn camera off", @"camera-button", 10);
        Expect([CameraStateForNode(cameraOn) isEqualToString:@"off"], @"Turn camera on must mean the camera is currently off", &failures);
        Expect([CameraStateForNode(cameraOff) isEqualToString:@"on"], @"Turn camera off must mean the camera is currently on", &failures);

        Expect([HandStateForNode(raiseHand) isEqualToString:@"lowered"], @"Raise hand must mean the hand is currently lowered", &failures);
        AXNode *lowerHand = Button(@"Lower your hand", @"hand-button", 10);
        Expect([HandStateForNode(lowerHand) isEqualToString:@"raised"], @"Lower hand must mean the hand is currently raised", &failures);

        AXNode *pickerRaise = Button(@"Raise", @"", 8);
        pickerRaise.customDescription = @"Raise your hand. Has context menu";
        AXCustomContent *description = [AXCustomContent customContentWithLabel:@"description" value:pickerRaise.customDescription];
        NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:@[description] requiringSecureCoding:YES error:NULL];
        Expect([CustomDescription(archive) isEqualToString:pickerRaise.customDescription], @"Chromium custom description archive must decode securely", &failures);
        Expect([CustomDescription(@[description]) isEqualToString:pickerRaise.customDescription], @"native custom description array must decode", &failures);
        Expect(CustomDescription([@"invalid archive" dataUsingEncoding:NSUTF8StringEncoding]).length == 0, @"invalid custom content must be ignored", &failures);
        Expect(CustomDescription(@[@"unexpected"]).length == 0, @"unexpected custom content must be ignored", &failures);
        AXNode *pickerLike = Button(@"Like", @"", 8);
        AXNode *pickerLove = Button(@"Love", @"", 8);
        AXNode *pickerLaugh = Button(@"Laugh", @"", 8);
        NSArray *picker = @[pickerRaise, pickerLike, pickerLove, pickerLaugh];
        MarkMeetingReactionPicker(picker);
        Expect(HandScore(pickerRaise) > 0, @"new meeting picker Raise must be selectable", &failures);
        Expect([HandStateForNode(pickerRaise) isEqualToString:@"lowered"], @"picker Raise means hand lowered", &failures);
        Expect([StateSnapshot(@{@"applicationCount": @1, @"elements": picker})[@"meetingActive"] boolValue], @"open meeting picker must preserve meeting detection", &failures);
        // The visible title stays Raise even when the hand is raised.
        pickerRaise.customDescription = @"Lower your hand. Has context menu";
        Expect([HandStateForNode(pickerRaise) isEqualToString:@"raised"], @"custom Lower description must override the unchanged Raise title", &failures);
        AXNode *unknownRaise = Button(@"Raise", @"raisehands-button", 8);
        unknownRaise.meetingReactionPicker = YES;
        Expect([HandStateForNode(unknownRaise) isEqualToString:@"unknown"], @"short Raise alone must not invent a hand state", &failures);
        AXNode *unscopedRaise = Button(@"Raise", @"", 8);
        MarkMeetingReactionPicker(@[unscopedRaise]);
        Expect(HandScore(unscopedRaise) == NSIntegerMin, @"short Raise outside a meeting picker must be rejected", &failures);
        AXNode *chatRaise = Button(@"Raise", @"chat-raise", 8);
        MarkMeetingReactionPicker(@[chatRaise, pickerLike, pickerLove, pickerLaugh]);
        Expect(HandScore(chatRaise) == NSIntegerMin, @"chat Raise must be rejected", &failures);

        AXNode *stateLauncher = Button(@"React", @"reaction-menu-button", 8);
        stateLauncher.customDescription = @"React or raise your hand. Your hand is not raised. Has context menu";
        NSDictionary *launcherScan = @{@"applicationCount": @1, @"elements": @[stateLauncher]};
        Expect([StateSnapshot(launcherScan)[@"hand"] isEqualToString:@"lowered"], @"closed picker must expose lowered state from React description", &failures);
        stateLauncher.customDescription = @"React or raise your hand. Your hand is raised. Has context menu";
        Expect([StateSnapshot(launcherScan)[@"hand"] isEqualToString:@"raised"], @"closed picker must expose raised state from React description", &failures);
        stateLauncher.customDescription = @"React or raise your hand. Has context menu";
        Expect([HandStateFromLauncher(stateLauncher) isEqualToString:@"unavailable"], @"generic React description must not invent hand state", &failures);

        MeetingToolbarScan = @{@"applicationCount": @1, @"elements": @[mute, cameraOn]};
        NSDictionary *pickerState = StateSnapshot(WithMeetingToolbarState(@{@"applicationCount": @1, @"elements": picker}));
        Expect([pickerState[@"hand"] isEqualToString:@"raised"] && [pickerState[@"microphone"] isEqualToString:@"unmuted"] && [pickerState[@"camera"] isEqualToString:@"off"], @"modal picker snapshot must preserve toolbar states and use the current hand state", &failures);
        NSDictionary *closedScan = @{@"applicationCount": @1, @"elements": @[unmute]};
        Expect(WithMeetingToolbarState(closedScan) == closedScan, @"closed picker must use fresh toolbar state", &failures);
        MeetingToolbarScan = nil;

        AXNode *leave = Button(@"Leave", @"leave-button", 10);
        AXNode *endForAll = Button(@"Leave | End meeting for all", @"end-meeting-button", 9);
        Expect(LeaveScore(leave) > 0, @"exact Leave control must be eligible", &failures);
        Expect(LeaveScore(endForAll) == NSIntegerMin, @"End meeting for all must never be eligible", &failures);

        AXNode *customEndForAll = Button(@"Leave", @"leave-button", 10);
        customEndForAll.customDescription = @"End meeting for all";
        Expect(LeaveScore(customEndForAll) == NSIntegerMin, @"destructive custom description must veto a Leave title", &failures);
        AXNode *newMic = Button(@"Mic", @"microphone-button", 10);
        newMic.customDescription = @"Unmute mic. Has context menu";
        newMic.role = (__bridge NSString *)kAXCheckBoxRole;
        Expect(MicrophoneScore(newMic) > 0 && [MicrophoneStateForNode(newMic) isEqualToString:@"muted"], @"generic Mic title must use custom action state", &failures);
        AXNode *newCamera = Button(@"Camera", @"video-button", 10);
        newCamera.customDescription = @"Turn camera off. Has context menu";
        Expect(CameraScore(newCamera) > 0 && [CameraStateForNode(newCamera) isEqualToString:@"on"], @"generic Camera title must use custom action state", &failures);

        BOOL ambiguous = NO;
        AXNode *secondLeave = Button(@"Leave", @"leave-button", 10);
        AXNode *unique = BestUniqueNode(@[leave, secondLeave], ^NSInteger(AXNode *node) { return LeaveScore(node); }, &ambiguous);
        Expect(unique == nil && ambiguous, @"equally plausible destructive controls must fail as ambiguous", &failures);

        AXNode *effects = Button(@"Video effects and settings", @"video-effects-button", 10);
        AXNode *blur = Button(@"Blur", @"background-effect-blur", 12);
        AXNode *none = Button(@"None", @"background-effect-none", 12);
        AXNode *videoOptions = Button(@"Open video options", @"", 20);
        AXNode *standardBlur = Button(@"Standard blur", @"", 17);
        AXNode *noBackground = Button(@"No background effect", @"", 16);
        blur.selected = YES;
        Expect(EffectsLauncherScore(effects) > 0, @"video effects launcher must be recognized", &failures);
        Expect(BlurOptionScore(blur) > 0 && NoEffectOptionScore(none) > 0, @"blur and no-effect choices need separate scorers", &failures);
        Expect(EffectsLauncherScore(videoOptions) > 0, @"live Open video options launcher must be recognized", &failures);
        Expect(BlurOptionScore(standardBlur) > 0, @"live Standard blur option must be recognized", &failures);
        Expect(NoEffectOptionScore(noBackground) > 0, @"live No background effect option must be recognized", &failures);

        AXNode *standardBlurMenuItem = Button(@"Standard blur", @"", 17);
        standardBlurMenuItem.role = (__bridge NSString *)kAXMenuItemRole;
        AXNode *standardBlurText = Button(@"Standard blur", @"", 18);
        standardBlurText.role = (__bridge NSString *)kAXStaticTextRole;
        standardBlurText.actions = @[(__bridge NSString *)kAXShowMenuAction];
        BOOL blurAmbiguous = NO;
        AXNode *uniqueBlur = BestUniqueNode(@[standardBlurMenuItem, standardBlurText], ^NSInteger(AXNode *node) { return BlurOptionScore(node); }, &blurAmbiguous);
        Expect(uniqueBlur == standardBlurMenuItem && !blurAmbiguous, @"blur scorer must select the pressable menu item over its text child", &failures);

        NSDictionary *snapshot = StateSnapshot(@{@"applicationCount": @1, @"elements": @[unmute, cameraOn, lowerHand, leave, react, effects, blur, none]});
        Expect([snapshot[@"meetingActive"] boolValue], @"known meeting controls must mark the meeting active", &failures);
        Expect([snapshot[@"microphone"] isEqualToString:@"muted"], @"snapshot must report microphone state", &failures);
        Expect([snapshot[@"camera"] isEqualToString:@"off"], @"snapshot must report camera state", &failures);
        Expect([snapshot[@"hand"] isEqualToString:@"raised"], @"snapshot must report hand state", &failures);
        Expect([snapshot[@"backgroundBlur"] isEqualToString:@"on"], @"selected blur option must report blur on", &failures);

        if (failures > 0) return 1;
        printf("PASS: selected safe meeting controls and derived their states\n");
        return 0;
    }
}
