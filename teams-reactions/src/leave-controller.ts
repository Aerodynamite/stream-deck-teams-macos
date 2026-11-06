/**
 * Leave Call key behavior, free of the Stream Deck SDK so tests can load it directly.
 * The held key is the user's intent: a failed image update is logged and never
 * cancels or blocks the Leave.
 */
import type { HoldGate } from "./hold-gate";

/** Leave runs only after the key has been held this long. A tap never leaves. */
export const LEAVE_HOLD_MS = 1_500;
export const LEAVE_ARMED_IMAGE = `<svg xmlns="http://www.w3.org/2000/svg" width="144" height="144" viewBox="0 0 144 144"><rect width="144" height="144" rx="22" fill="#b3261e"/><text x="72" y="66" text-anchor="middle" font-family="Arial,sans-serif" font-size="30" font-weight="700" fill="#ffffff">HOLD</text><text x="72" y="104" text-anchor="middle" font-family="Arial,sans-serif" font-size="26" font-weight="700" fill="#ffffff">TO LEAVE</text></svg>`;

export type LeaveKey = {
	readonly id: string;
	setImage(image?: string): Promise<void>;
	showAlert(): Promise<void>;
	showOk(): Promise<void>;
};

export type LeaveExecute = () => Promise<{ status: "completed" | "busy" }>;

export type LeaveLogger = {
	info(message: string): void;
	warn(message: string): void;
	reportError(operation: string, error: unknown): void;
};

export class LeaveController {
	private readonly execute: LeaveExecute;
	private readonly logger: LeaveLogger;
	private readonly gate: HoldGate;
	private readonly armedKeys = new Map<string, LeaveKey>();

	constructor(execute: LeaveExecute, logger: LeaveLogger, gate: HoldGate) {
		this.execute = execute;
		this.logger = logger;
		this.gate = gate;
	}

	async keyDown(key: LeaveKey, isInMultiAction: boolean): Promise<void> {
		if (isInMultiAction) {
			this.logger.warn("Ignored leave inside a multi-action because Leave requires a held key.");
			await this.alert(key);
			return;
		}
		const armed = this.gate.press(key.id, () => {
			this.armedKeys.delete(key.id);
			void this.leave(key);
		});
		if (!armed) return;
		this.armedKeys.set(key.id, key);
		await this.safe(() => key.setImage(LEAVE_ARMED_IMAGE), "show the armed Leave image");
	}

	async keyUp(key: LeaveKey): Promise<void> {
		if (!this.disarm(key.id)) return;
		this.logger.info(`Leave cancelled: the key was released before ${LEAVE_HOLD_MS} ms.`);
		await this.alert(key);
	}

	/** Clears a stale armed image left by a reload or a missed key-up. */
	async appear(key: LeaveKey): Promise<void> {
		await this.safe(() => key.setImage(), "clear the Leave key image");
	}

	disappear(id: string): void {
		this.disarm(id);
	}

	/** Disarms every pending Leave and restores its key image, for device disconnect and system wake. */
	cancelAll(): void {
		for (const id of [...this.armedKeys.keys()]) this.disarm(id);
		this.gate.cancelAll();
	}

	private disarm(id: string): boolean {
		const key = this.armedKeys.get(id);
		this.armedKeys.delete(id);
		const cancelled = this.gate.release(id) === "cancelled";
		if (key) void this.safe(() => key.setImage(), "restore the Leave key image after disarming");
		return cancelled;
	}

	private async leave(key: LeaveKey): Promise<void> {
		await this.safe(() => key.setImage(), "restore the Leave key image");
		let status: "completed" | "busy";
		try {
			({ status } = await this.execute());
		} catch (error) {
			this.logger.reportError("Teams command leave", error);
			await this.alert(key);
			return;
		}
		if (status === "busy") {
			this.logger.warn("Ignored leave because another Teams operation is running.");
			await this.alert(key);
			return;
		}
		this.logger.info("Teams meeting leave completed.");
		await this.safe(() => key.showOk(), "show the Leave confirmation");
	}

	private alert(key: LeaveKey): Promise<void> {
		return this.safe(() => key.showAlert(), "show the Leave alert");
	}

	/** Runs a key update, logs a failure and never rejects. */
	private async safe(update: () => Promise<unknown>, context: string): Promise<void> {
		try {
			await update();
		} catch {
			this.logger.warn(`Could not ${context}.`);
		}
	}
}
