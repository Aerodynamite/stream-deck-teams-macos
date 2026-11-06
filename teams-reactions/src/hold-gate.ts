/**
 * Requires a key to stay down for a fixed time before a destructive action runs.
 * The action fires from the timer while the key is still held, never on key-up,
 * so a tap or a brushed key cannot trigger it.
 */
export type HoldTimers = {
	set(callback: () => void, ms: number): unknown;
	clear(handle: unknown): void;
};

const SYSTEM_TIMERS: HoldTimers = {
	set: (callback, ms) => setTimeout(callback, ms),
	clear: handle => clearTimeout(handle as ReturnType<typeof setTimeout>),
};

export type HoldRelease = "cancelled" | "idle";

export class HoldGate {
	private readonly holdMs: number;
	private readonly timers: HoldTimers;
	private readonly armed = new Map<string, unknown>();

	constructor(holdMs: number, timers: HoldTimers = SYSTEM_TIMERS) {
		if (!Number.isFinite(holdMs) || holdMs <= 0) throw new RangeError("holdMs must be a positive number.");
		this.holdMs = holdMs;
		this.timers = timers;
	}

	/** Arms the gate for a key. Returns false when that key is already armed. */
	press(context: string, onHeld: () => void): boolean {
		if (this.armed.has(context)) return false;
		const handle = this.timers.set(() => {
			if (!this.armed.has(context)) return;
			this.armed.delete(context);
			onHeld();
		}, this.holdMs);
		this.armed.set(context, handle);
		return true;
	}

	/** Disarms a key. "cancelled" means it was released before the hold completed. */
	release(context: string): HoldRelease {
		const handle = this.armed.get(context);
		if (handle === undefined) return "idle";
		this.timers.clear(handle);
		this.armed.delete(context);
		return "cancelled";
	}

	cancelAll(): void {
		for (const handle of this.armed.values()) this.timers.clear(handle);
		this.armed.clear();
	}

	isArmed(context: string): boolean {
		return this.armed.has(context);
	}
}
