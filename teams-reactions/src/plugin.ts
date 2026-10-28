import streamDeck from "@elgato/streamdeck";
import { watchPluginConnection } from "./helper-runner";

import {
	ApplauseAction,
	LaughAction,
	LikeAction,
	LoveAction,
	SurpriseAction,
} from "./actions/reactions";
import {
	CameraAction,
	HandAction,
	LeaveAction,
	MuteAction,
	stateSynchronizer,
} from "./actions/call-controls";
import { persistentControls, reactionBurstCoordinator } from "./teams-services";

streamDeck.logger.setLevel("info");

streamDeck.actions.registerAction(new LikeAction());
streamDeck.actions.registerAction(new LoveAction());
streamDeck.actions.registerAction(new ApplauseAction());
streamDeck.actions.registerAction(new LaughAction());
streamDeck.actions.registerAction(new SurpriseAction());
streamDeck.actions.registerAction(new MuteAction());
streamDeck.actions.registerAction(new CameraAction());
streamDeck.actions.registerAction(new HandAction());
streamDeck.actions.registerAction(new LeaveAction());

streamDeck.devices.onDeviceDidDisconnect(ev => {
	reactionBurstCoordinator.stopAll();
	stateSynchronizer.disconnectDevice(ev.device.id);
	if (!stateSynchronizer.hasVisibleControls) persistentControls.stop();
});
streamDeck.system.onApplicationDidTerminate(() => reactionBurstCoordinator.stopAll());
streamDeck.system.onSystemDidWakeUp(() => {
	persistentControls.invalidate();
	if (stateSynchronizer.hasVisibleControls) void stateSynchronizer.refresh().catch(() => streamDeck.logger.warn("Teams state refresh after wake failed."));
});
process.once("beforeExit", () => { reactionBurstCoordinator.stopAll(); persistentControls.stop(); });
for (const signal of ["SIGINT", "SIGTERM"] as const) {
	process.once(signal, () => { reactionBurstCoordinator.stopAll(); persistentControls.stop(); process.exit(0); });
}

streamDeck.connect().then(() => {
	watchPluginConnection(() => streamDeck.settings.getGlobalSettings(), () => {
		reactionBurstCoordinator.stopAll();
		persistentControls.stop();
		process.exit(0);
	});
});
