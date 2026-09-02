import streamDeck, {
	action,
	type KeyAction,
	type KeyDownEvent,
	type State,
	SingletonAction,
	type WillAppearEvent,
	type WillDisappearEvent,
} from "@elgato/streamdeck";

import {
	HelperExecutionError,
	type TeamsCommand,
	type TeamsState,
} from "../helper-runner";
import { commandCoordinator } from "../teams-services";

type StateField = "microphone" | "camera" | "backgroundBlur" | "hand";
type KnownState = "muted" | "unmuted" | "on" | "off" | "raised" | "lowered";

const UNKNOWN_IMAGE = `<svg xmlns="http://www.w3.org/2000/svg" width="144" height="144" viewBox="0 0 144 144"><rect width="144" height="144" rx="22" fill="#24262b"/><circle cx="72" cy="72" r="41" fill="none" stroke="#f0b429" stroke-width="9"/><text x="72" y="91" text-anchor="middle" font-family="Arial,sans-serif" font-size="58" font-weight="700" fill="#f0b429">?</text></svg>`;
const UNAVAILABLE_IMAGE = `<svg xmlns="http://www.w3.org/2000/svg" width="144" height="144" viewBox="0 0 144 144"><rect width="144" height="144" rx="22" fill="#24262b"/><circle cx="72" cy="72" r="42" fill="none" stroke="#777b84" stroke-width="9"/><path d="M42 102L102 42" stroke="#777b84" stroke-width="10" stroke-linecap="round"/></svg>`;

function keyActionFromEvent(ev: WillAppearEvent | WillDisappearEvent): KeyAction | undefined {
	return "setState" in ev.action ? ev.action as KeyAction : undefined;
}

function stateIndex(field: StateField, value: string): State | undefined {
	const mappings: Record<StateField, readonly [KnownState, KnownState]> = {
		microphone: ["unmuted", "muted"],
		camera: ["on", "off"],
		backgroundBlur: ["off", "on"],
		hand: ["lowered", "raised"],
	};
	if (value === mappings[field][0]) return 0;
	if (value === mappings[field][1]) return 1;
	return undefined;
}

class StateSynchronizer {
	private readonly visible = new Map<StateField, Map<string, KeyAction>>();
	private refreshPromise: Promise<void> | undefined;
	latest: TeamsState | undefined;

	register(context: string, field: StateField, actionInstance: KeyAction): void {
		let actions = this.visible.get(field);
		if (!actions) {
			actions = new Map();
			this.visible.set(field, actions);
		}
		actions.set(context, actionInstance);
		void actionInstance.setImage(UNAVAILABLE_IMAGE);
	}

	unregister(context: string, field: StateField): void {
		this.visible.get(field)?.delete(context);
	}

	async refresh(): Promise<void> {
		if (this.refreshPromise) return this.refreshPromise;
		this.refreshPromise = (async () => {
			try {
				const execution = await commandCoordinator.execute("status");
				if (execution.status === "completed") await this.apply(execution.result);
			} finally {
				this.refreshPromise = undefined;
			}
		})();
		return this.refreshPromise;
	}

	async apply(result: TeamsState): Promise<void> {
		this.latest = result;
		const updates: Promise<unknown>[] = [];
		for (const [field, actions] of this.visible) {
			const value = result[field];
			const index = stateIndex(field, value);
			for (const actionInstance of actions.values()) {
				if (index !== undefined) {
					updates.push(actionInstance.setState(index), actionInstance.setImage());
				} else {
					updates.push(actionInstance.setImage(value === "unavailable" ? UNAVAILABLE_IMAGE : UNKNOWN_IMAGE));
				}
			}
		}
		await Promise.allSettled(updates);
	}
}

export const stateSynchronizer = new StateSynchronizer();

abstract class ToggleCallControlAction extends SingletonAction {
	protected abstract readonly field: StateField;
	protected abstract readonly commands: readonly [TeamsCommand, TeamsCommand];

	override async onWillAppear(ev: WillAppearEvent): Promise<void> {
		const actionInstance = keyActionFromEvent(ev);
		if (!actionInstance) return;
		stateSynchronizer.register(actionInstance.id, this.field, actionInstance);
		try {
			await stateSynchronizer.refresh();
		} catch (error) {
			logHelperError(`${this.field} state refresh`, error);
		}
	}

	override onWillDisappear(ev: WillDisappearEvent): void {
		stateSynchronizer.unregister(ev.action.id, this.field);
	}

	override async onKeyDown(ev: KeyDownEvent): Promise<void> {
		let desiredIndex: State;
		if (ev.payload.isInMultiAction) {
			desiredIndex = ev.payload.userDesiredState;
		} else {
			let currentIndex = stateSynchronizer.latest ? stateIndex(this.field, stateSynchronizer.latest[this.field]) : undefined;
			if (currentIndex === undefined && this.field !== "backgroundBlur") {
				try {
					await stateSynchronizer.refresh();
				} catch (error) {
					logHelperError(`${this.field} state refresh`, error);
				}
				currentIndex = stateSynchronizer.latest ? stateIndex(this.field, stateSynchronizer.latest[this.field]) : undefined;
			}
			if (currentIndex === undefined && this.field !== "backgroundBlur") {
				await ev.action.showAlert();
				return;
			}
			const displayedIndex = currentIndex ?? ev.payload.state ?? 0;
			desiredIndex = displayedIndex === 0 ? 1 : 0;
		}

		const command = this.commands[desiredIndex];
		try {
			const execution = await commandCoordinator.execute(command);
			if (execution.status === "busy") {
				streamDeck.logger.warn(`Ignored ${command} because another Teams operation is running.`);
				await ev.action.showAlert();
				return;
			}
			const result = execution.result;
			const confirmedIndex = stateIndex(this.field, result[this.field]);
			if (confirmedIndex === undefined && this.field === "backgroundBlur") await ev.action.setState(desiredIndex);
			await stateSynchronizer.apply(result);
			if (confirmedIndex === desiredIndex) {
				streamDeck.logger.info(`Teams command completed: ${command}; changed=${result.changed}.`);
				await ev.action.showOk();
			} else {
				streamDeck.logger.warn(`Teams command ${command} was accepted without confirmed state.`);
				await ev.action.showAlert();
			}
		} catch (error) {
			logHelperError(`Teams command ${command}`, error);
			await ev.action.showAlert();
		}
	}
}

function logHelperError(operation: string, error: unknown): void {
	if (error instanceof HelperExecutionError) {
		const exitCode = error.exitCode === null ? "unavailable" : String(error.exitCode);
		streamDeck.logger.error(`${operation} failed (exit code ${exitCode}): ${error.diagnostic}`);
	} else {
		streamDeck.logger.error(`${operation} failed with an unexpected plugin error.`);
	}
}

@action({ UUID: "com.laurens-bolle.teams-reactions.mute" })
export class MuteAction extends ToggleCallControlAction {
	protected readonly field = "microphone" as const;
	protected readonly commands = ["unmute", "mute"] as const;
}

@action({ UUID: "com.laurens-bolle.teams-reactions.camera" })
export class CameraAction extends ToggleCallControlAction {
	protected readonly field = "camera" as const;
	protected readonly commands = ["camera-on", "camera-off"] as const;
}

@action({ UUID: "com.laurens-bolle.teams-reactions.blur" })
export class BlurAction extends ToggleCallControlAction {
	protected readonly field = "backgroundBlur" as const;
	protected readonly commands = ["blur-off", "blur-on"] as const;
}

@action({ UUID: "com.laurens-bolle.teams-reactions.hand" })
export class HandAction extends ToggleCallControlAction {
	protected readonly field = "hand" as const;
	protected readonly commands = ["hand-lower", "hand-raise"] as const;
}

@action({ UUID: "com.laurens-bolle.teams-reactions.leave" })
export class LeaveAction extends SingletonAction {
	override async onKeyDown(ev: KeyDownEvent): Promise<void> {
		try {
			const execution = await commandCoordinator.execute("leave");
			if (execution.status === "busy") {
				streamDeck.logger.warn("Ignored leave because another Teams operation is running.");
				await ev.action.showAlert();
				return;
			}
			await stateSynchronizer.apply(execution.result);
			streamDeck.logger.info("Teams meeting leave completed.");
			await ev.action.showOk();
		} catch (error) {
			logHelperError("Teams command leave", error);
			await ev.action.showAlert();
		}
	}
}
