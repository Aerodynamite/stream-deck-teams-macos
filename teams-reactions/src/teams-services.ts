import {
	CommandCoordinator,
	OperationLock,
	ReactionBurstCoordinator,
	ReactionCoordinator,
} from "./helper-runner";

export const operationLock = new OperationLock();
export const commandCoordinator = new CommandCoordinator(operationLock);
export const reactionCoordinator = new ReactionCoordinator(operationLock);
export const reactionBurstCoordinator = new ReactionBurstCoordinator(operationLock);
