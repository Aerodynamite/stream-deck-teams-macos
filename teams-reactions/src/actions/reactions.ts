import streamDeck, {
	action,
	type KeyAction,
	type KeyDownEvent,
	type KeyUpEvent,
	SingletonAction,
	type WillDisappearEvent,
} from "@elgato/streamdeck";

import { HelperExecutionError, type BurstResult, type Reaction } from "../helper-runner";
import { reactionBurstCoordinator, reactionCoordinator } from "../teams-services";

abstract class ReactionAction extends SingletonAction {
	private readonly reaction: Reaction;

	protected constructor(reaction: Reaction) {
		super();
		this.reaction = reaction;
	}

	override async onKeyDown(ev: KeyDownEvent): Promise<void> {
		if (ev.payload.isInMultiAction) {
			await this.sendSingleReaction(ev);
			return;
		}

		try {
			const started = reactionBurstCoordinator.start(ev.action.id, this.reaction);
			if (started.status === "busy") {
				streamDeck.logger.warn(`Ignored ${this.reaction} because another Teams operation is running.`);
				await ev.action.showAlert();
				return;
			}
			void this.reportBurst(started.completion, ev.action);
		} catch (error) {
			this.logFailure(`Teams reaction burst ${this.reaction}`, error);
			await ev.action.showAlert();
		}
	}

	override onKeyUp(ev: KeyUpEvent): void {
		reactionBurstCoordinator.stop(ev.action.id);
	}

	override onWillDisappear(ev: WillDisappearEvent): void {
		reactionBurstCoordinator.stop(ev.action.id);
	}

	private async sendSingleReaction(ev: KeyDownEvent): Promise<void> {
		try {
			const execution = await reactionCoordinator.execute(this.reaction);
			if (execution.status === "busy") {
				streamDeck.logger.warn(`Ignored ${this.reaction} because another Teams operation is running.`);
				await ev.action.showAlert();
				return;
			}
			streamDeck.logger.info(`Sent one Teams reaction command: ${this.reaction}.`);
			await ev.action.showOk();
		} catch (error) {
			this.logFailure(`Teams reaction ${this.reaction}`, error);
			await ev.action.showAlert();
		}
	}

	private async reportBurst(completion: Promise<BurstResult>, actionInstance: KeyAction): Promise<void> {
		try {
			const result = await completion;
			streamDeck.logger.info(
				`Teams reaction burst ${result.reaction}: attempted=${result.attempted}, accepted=${result.accessibilityAccepted}, elapsedMs=${result.elapsedMs}, stop=${result.stopReason}.`,
			);
			if (result.accessibilityAccepted > 0) await actionInstance.showOk();
			else await actionInstance.showAlert();
		} catch (error) {
			this.logFailure(`Teams reaction burst ${this.reaction}`, error);
			await actionInstance.showAlert();
		}
	}

	private logFailure(operation: string, error: unknown): void {
		if (error instanceof HelperExecutionError) {
			const exitCode = error.exitCode === null ? "unavailable" : String(error.exitCode);
			streamDeck.logger.error(`${operation} failed (exit code ${exitCode}): ${error.diagnostic}`);
		} else {
			streamDeck.logger.error(`${operation} failed with an unexpected plugin error.`);
		}
	}
}

@action({ UUID: "com.laurens-bolle.teams-reactions.like" })
export class LikeAction extends ReactionAction {
	constructor() { super("like"); }
}

@action({ UUID: "com.laurens-bolle.teams-reactions.love" })
export class LoveAction extends ReactionAction {
	constructor() { super("love"); }
}

@action({ UUID: "com.laurens-bolle.teams-reactions.applause" })
export class ApplauseAction extends ReactionAction {
	constructor() { super("applause"); }
}

@action({ UUID: "com.laurens-bolle.teams-reactions.laugh" })
export class LaughAction extends ReactionAction {
	constructor() { super("laugh"); }
}

@action({ UUID: "com.laurens-bolle.teams-reactions.surprise" })
export class SurpriseAction extends ReactionAction {
	constructor() { super("surprise"); }
}
