#define TEAMS_REACTION_TESTING 1
#import "../TeamsReactionPOC.m"

static AXNode *Button(NSString *title, NSString *identifier, NSInteger depth) {
    AXNode *node = [AXNode new];
    node.identifier = identifier;
    node.title = title;
    node.nodeDescription = @"";
    node.helpText = @"";
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

        AXNode *leave = Button(@"Leave", @"leave-button", 10);
        AXNode *endForAll = Button(@"Leave | End meeting for all", @"end-meeting-button", 9);
        Expect(LeaveScore(leave) > 0, @"exact Leave control must be eligible", &failures);
        Expect(LeaveScore(endForAll) == NSIntegerMin, @"End meeting for all must never be eligible", &failures);

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
