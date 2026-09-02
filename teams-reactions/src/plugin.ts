import streamDeck from "@elgato/streamdeck";

import {
	ApplauseAction,
	LaughAction,
	LikeAction,
	LoveAction,
	SurpriseAction,
} from "./actions/reactions";
import {
	BlurAction,
	CameraAction,
	HandAction,
	LeaveAction,
	MuteAction,
} from "./actions/call-controls";
import { reactionBurstCoordinator } from "./teams-services";

streamDeck.logger.setLevel("info");

streamDeck.actions.registerAction(new LikeAction());
streamDeck.actions.registerAction(new LoveAction());
streamDeck.actions.registerAction(new ApplauseAction());
streamDeck.actions.registerAction(new LaughAction());
streamDeck.actions.registerAction(new SurpriseAction());
streamDeck.actions.registerAction(new MuteAction());
streamDeck.actions.registerAction(new CameraAction());
streamDeck.actions.registerAction(new BlurAction());
streamDeck.actions.registerAction(new HandAction());
streamDeck.actions.registerAction(new LeaveAction());

streamDeck.devices.onDeviceDidDisconnect(() => reactionBurstCoordinator.stopAll());
streamDeck.system.onApplicationDidTerminate(() => reactionBurstCoordinator.stopAll());

streamDeck.connect();
