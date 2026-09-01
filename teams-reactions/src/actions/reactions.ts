import streamDeck, { action, type KeyDownEvent, SingletonAction } from "@elgato/streamdeck";

import {
	HelperExecutionError,
	ReactionCoordinator,
	type Reaction,
} from "../helper-runner";

const coordinator = new ReactionCoordinator();

abstract class ReactionAction extends SingletonAction {
	private readonly reaction: Reaction;

	protected constructor(reaction: Reaction) {
		super();
		this.reaction = reaction;
	}

	override async onKeyDown(ev: KeyDownEvent): Promise<void> {
		try {
			const result = await coordinator.execute(this.reaction);
			if (result === "busy") {
				streamDeck.logger.warn(`Ignored ${this.reaction} because another Teams reaction is running.`);
				await ev.action.showAlert();
				return;
			}

			streamDeck.logger.info(`Sent Teams reaction command: ${this.reaction}.`);
			await ev.action.showOk();
		} catch (error) {
			if (error instanceof HelperExecutionError) {
				const exitCode = error.exitCode === null ? "unavailable" : String(error.exitCode);
				streamDeck.logger.error(
					`Teams reaction ${this.reaction} failed (exit code ${exitCode}): ${error.diagnostic}`,
				);
			} else {
				streamDeck.logger.error(`Teams reaction ${this.reaction} failed with an unexpected plugin error.`);
			}
			await ev.action.showAlert();
		}
	}
}

@action({ UUID: "com.laurens-bolle.teams-reactions.like" })
export class LikeAction extends ReactionAction {
	constructor() {
		super("like");
	}
}

@action({ UUID: "com.laurens-bolle.teams-reactions.love" })
export class LoveAction extends ReactionAction {
	constructor() {
		super("love");
	}
}

@action({ UUID: "com.laurens-bolle.teams-reactions.applause" })
export class ApplauseAction extends ReactionAction {
	constructor() {
		super("applause");
	}
}

@action({ UUID: "com.laurens-bolle.teams-reactions.laugh" })
export class LaughAction extends ReactionAction {
	constructor() {
		super("laugh");
	}
}

@action({ UUID: "com.laurens-bolle.teams-reactions.surprise" })
export class SurpriseAction extends ReactionAction {
	constructor() {
		super("surprise");
	}
}
