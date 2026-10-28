import {
	CommandCoordinator,
	OperationLock,
	PersistentControlClient,
	ReactionBurstCoordinator,
	ReactionCoordinator,
	isPersistentCommand,
	runReactionHelper,
	runTeamsCommand,
	startReactionBurst,
} from "./helper-runner";

export const operationLock = new OperationLock();
export const persistentControls = new PersistentControlClient();
export const commandCoordinator = new CommandCoordinator(operationLock, async command => {
	if (isPersistentCommand(command)) return persistentControls.execute(command);
	persistentControls.pause();
	try { return await runTeamsCommand(command); }
	finally { persistentControls.resume(); }
});
export const reactionCoordinator = new ReactionCoordinator(operationLock, async reaction => {
	persistentControls.pause();
	try { return await runReactionHelper(reaction); }
	finally { persistentControls.resume(); }
});
export const reactionBurstCoordinator = new ReactionBurstCoordinator(operationLock, reaction => {
	persistentControls.pause();
	try {
		const session = startReactionBurst(reaction);
		return { stop: () => session.stop(), completion: session.completion.finally(() => persistentControls.resume()) };
	} catch (error) {
		persistentControls.resume();
		throw error;
	}
});
