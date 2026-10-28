import { execFile, spawn } from "node:child_process";
import { chmodSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";

export const REACTIONS = ["like", "love", "applause", "laugh", "surprise"] as const;
export const TEAMS_COMMANDS = [
	"status",
	"mute",
	"unmute",
	"camera-on",
	"camera-off",
	"blur-on",
	"blur-off",
	"hand-raise",
	"hand-lower",
	"leave",
] as const;

export type Reaction = (typeof REACTIONS)[number];
export type TeamsCommand = (typeof TEAMS_COMMANDS)[number];
export type AvailabilityState = "unknown" | "unavailable";
export type MicrophoneState = "muted" | "unmuted" | AvailabilityState;
export type CameraState = "on" | "off" | AvailabilityState;
export type BlurState = "on" | "off" | AvailabilityState;
export type HandState = "raised" | "lowered" | AvailabilityState;

export type TeamsState = {
	meetingActive: boolean;
	microphone: MicrophoneState;
	camera: CameraState;
	backgroundBlur: BlurState;
	hand: HandState;
};

export type TeamsCommandResult = TeamsState & {
	command: TeamsCommand;
	changed: boolean;
};

export type ReactionCommandResult = {
	command: "react";
	reaction: Reaction;
	changed: boolean;
	accessibilityAccepted: number;
};

export type BurstResult = {
	command: "burst";
	reaction: Reaction;
	attempted: number;
	accessibilityAccepted: number;
	elapsedMs: number;
	stopReason: "key-up" | "duration-limit" | "count-limit" | "selection-error" | "error";
};

const REACTION_SET: ReadonlySet<string> = new Set(REACTIONS);
const COMMAND_SET: ReadonlySet<string> = new Set(TEAMS_COMMANDS);
const DEFAULT_HELPER_PATH = fileURLToPath(new URL("./teams-reaction", import.meta.url));
const DEFAULT_TIMEOUT_MS = 8_000;
const HAND_COMMAND_TIMEOUT_MS = 15_000;
const DEFAULT_BURST_TIMEOUT_MS = 6_500;
const MAX_OUTPUT_BYTES = 64 * 1024;

type ExecFileCallback = (error: NodeJS.ErrnoException | null, stdout: string, stderr: string) => void;
type ExecFileLike = (
	file: string,
	args: readonly string[],
	options: { encoding: "utf8"; maxBuffer: number; timeout: number },
	callback: ExecFileCallback,
) => unknown;

export type HelperRunnerOptions = {
	helperPath?: string;
	timeoutMs?: number;
	execFileImpl?: ExecFileLike;
};

export class HelperExecutionError extends Error {
	readonly exitCode: number | null;
	readonly timedOut: boolean;
	readonly diagnostic: string;

	constructor(exitCode: number | null, timedOut: boolean, diagnostic: string) {
		super(diagnostic);
		this.name = "HelperExecutionError";
		this.exitCode = exitCode;
		this.timedOut = timedOut;
		this.diagnostic = diagnostic;
	}
}

export function isReaction(value: string): value is Reaction {
	return REACTION_SET.has(value);
}

export function isTeamsCommand(value: string): value is TeamsCommand {
	return COMMAND_SET.has(value);
}

const EXECUTE_BITS = 0o111;
const HELPER_MODE = 0o755;

/**
 * The Stream Deck packer stores every archive entry as 0644, so the native helper
 * loses its execute bit when the plugin is installed from a .streamDeckPlugin file.
 * Restore it before spawning so a packaged install works without manual repair.
 */
function ensureExecutable(helperPath: string): void {
	try {
		const { mode } = statSync(helperPath);
		if ((mode & EXECUTE_BITS) === EXECUTE_BITS) return;
		chmodSync(helperPath, HELPER_MODE);
	} catch {
		// Leave the real failure to the process launcher, which reports a spawn error code.
	}
}

function safeDiagnostic(exitCode: number | null, spawnCode: string | null, timedOut: boolean, stderr: string): string {
	if (timedOut) return "The Teams helper timed out.";
	if (spawnCode !== null) return `The helper could not be started (${spawnCode}).`;
	const diagnostics: Record<number, string> = {
		1: "Accessibility permission is required.",
		2: "Microsoft Teams is not running.",
		3: "No safe meeting reaction control was found.",
		4: "The meeting reaction control could not be opened.",
		5: "The requested reaction was not found before the timeout.",
		6: "The requested reaction could not be pressed.",
		10: "No safe meeting control was found or its state is unknown.",
		11: "Teams exposed more than one plausible control, so no control was pressed.",
		12: "The selected Teams control could not be invoked.",
		13: "Teams accepted the action, but the requested state was not confirmed.",
		14: "The requested Teams video effect is unavailable.",
		64: "The helper rejected its command arguments.",
	};
	if (exitCode !== null && diagnostics[exitCode]) return diagnostics[exitCode];
	if (stderr.trim().length > 0) return "The helper reported an unrecognized error; details were suppressed for privacy.";
	return "The helper exited unexpectedly without a diagnostic.";
}

function parseObject(stdout: string): Record<string, unknown> {
	const lines = stdout.split("\n").map((line) => line.trim()).filter(Boolean);
	if (lines.length === 0) throw new HelperExecutionError(null, false, "The Teams helper returned no JSON result.");
	try {
		const value: unknown = JSON.parse(lines.at(-1) ?? "");
		if (typeof value !== "object" || value === null || Array.isArray(value)) throw new Error("not an object");
		return value as Record<string, unknown>;
	} catch (error) {
		if (error instanceof HelperExecutionError) throw error;
		throw new HelperExecutionError(null, false, "The Teams helper returned an invalid JSON result.");
	}
}

function isState(value: unknown, known: readonly string[]): value is string {
	return typeof value === "string" && (known.includes(value) || value === "unknown" || value === "unavailable");
}

export function parseTeamsResult(stdout: string): TeamsCommandResult {
	const value = parseObject(stdout);
	if (
		typeof value.meetingActive !== "boolean"
		|| !isState(value.microphone, ["muted", "unmuted"])
		|| !isState(value.camera, ["on", "off"])
		|| !isState(value.backgroundBlur, ["on", "off"])
		|| !isState(value.hand, ["raised", "lowered"])
		|| typeof value.command !== "string"
		|| !isTeamsCommand(value.command)
		|| typeof value.changed !== "boolean"
	) {
		throw new HelperExecutionError(null, false, "The Teams helper returned an incomplete state result.");
	}
	return value as TeamsCommandResult;
}

function parseReactionResult(stdout: string): ReactionCommandResult {
	const value = parseObject(stdout);
	if (
		value.command !== "react"
		|| typeof value.reaction !== "string"
		|| !isReaction(value.reaction)
		|| typeof value.changed !== "boolean"
		|| typeof value.accessibilityAccepted !== "number"
	) {
		throw new HelperExecutionError(null, false, "The Teams helper returned an incomplete reaction result.");
	}
	return value as ReactionCommandResult;
}

export function parseBurstResult(stdout: string): BurstResult {
	const value = parseObject(stdout);
	const stopReasons = ["key-up", "duration-limit", "count-limit", "selection-error", "error"];
	if (
		value.command !== "burst"
		|| typeof value.reaction !== "string"
		|| !isReaction(value.reaction)
		|| typeof value.attempted !== "number"
		|| typeof value.accessibilityAccepted !== "number"
		|| typeof value.elapsedMs !== "number"
		|| typeof value.stopReason !== "string"
		|| !stopReasons.includes(value.stopReason)
	) {
		throw new HelperExecutionError(null, false, "The Teams helper returned an incomplete burst result.");
	}
	return value as BurstResult;
}

function runHelper<T>(args: readonly string[], parser: (stdout: string) => T, options: HelperRunnerOptions): Promise<T> {
	const helperPath = options.helperPath ?? DEFAULT_HELPER_PATH;
	const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
	const execFileImpl = options.execFileImpl ?? (execFile as ExecFileLike);
	ensureExecutable(helperPath);
	return new Promise((resolve, reject) => {
		execFileImpl(helperPath, args, { encoding: "utf8", maxBuffer: MAX_OUTPUT_BYTES, timeout: timeoutMs }, (error, stdout, stderr) => {
			if (!error) {
				try {
					resolve(parser(stdout));
				} catch (parseError) {
					reject(parseError);
				}
				return;
			}
			const rawCode = error.code;
			const exitCode = typeof rawCode === "number" ? rawCode : null;
			const spawnCode = typeof rawCode === "string" && /^E[A-Z0-9]+$/.test(rawCode) ? rawCode : null;
			const killed = "killed" in error && error.killed === true;
			const timedOut = killed && "signal" in error && error.signal === "SIGTERM";
			reject(new HelperExecutionError(exitCode, timedOut, safeDiagnostic(exitCode, spawnCode, timedOut, stderr)));
		});
	});
}

export function runTeamsCommand(command: string, options: HelperRunnerOptions = {}): Promise<TeamsCommandResult> {
	if (!isTeamsCommand(command)) return Promise.reject(new HelperExecutionError(null, false, "An invalid Teams command was blocked before launching the helper."));
	return runHelper([command], (stdout) => {
		const result = parseTeamsResult(stdout);
		if (result.command !== command) throw new HelperExecutionError(null, false, "The Teams helper returned a result for a different command.");
		return result;
	}, { ...options, timeoutMs: options.timeoutMs ?? (command.startsWith("hand-") ? HAND_COMMAND_TIMEOUT_MS : DEFAULT_TIMEOUT_MS) });
}

export function runReactionHelper(reaction: string, options: HelperRunnerOptions = {}): Promise<ReactionCommandResult> {
	if (!isReaction(reaction)) return Promise.reject(new HelperExecutionError(null, false, "An invalid reaction was blocked before launching the helper."));
	return runHelper(["react", reaction], (stdout) => {
		const result = parseReactionResult(stdout);
		if (result.reaction !== reaction) throw new HelperExecutionError(null, false, "The Teams helper returned a result for a different reaction.");
		return result;
	}, options);
}

type StreamLike = {
	on(event: "data", listener: (chunk: Buffer | string) => void): unknown;
};

type InputLike = {
	end(): void;
};

export type BurstChildLike = {
	stdin: InputLike;
	stdout: StreamLike;
	stderr: StreamLike;
	on(event: "error", listener: (error: NodeJS.ErrnoException) => void): unknown;
	on(event: "close", listener: (code: number | null, signal: NodeJS.Signals | null) => void): unknown;
	kill(signal?: NodeJS.Signals): boolean;
};

type SpawnLike = (file: string, args: readonly string[], options: { stdio: ["pipe", "pipe", "pipe"] }) => BurstChildLike;

export type BurstRunnerOptions = {
	helperPath?: string;
	timeoutMs?: number;
	spawnImpl?: SpawnLike;
};

export type BurstSession = {
	completion: Promise<BurstResult>;
	stop(): void;
};

export function startReactionBurst(reaction: string, options: BurstRunnerOptions = {}): BurstSession {
	if (!isReaction(reaction)) throw new HelperExecutionError(null, false, "An invalid reaction burst was blocked before launching the helper.");
	const helperPath = options.helperPath ?? DEFAULT_HELPER_PATH;
	const timeoutMs = options.timeoutMs ?? DEFAULT_BURST_TIMEOUT_MS;
	const spawnImpl = options.spawnImpl ?? (spawn as unknown as SpawnLike);
	ensureExecutable(helperPath);
	const child = spawnImpl(helperPath, ["burst", reaction], { stdio: ["pipe", "pipe", "pipe"] });
	let stdout = "";
	let stderr = "";
	let stopped = false;
	let settled = false;
	let killedByTimeout = false;

	const completion = new Promise<BurstResult>((resolve, reject) => {
		const timer = setTimeout(() => {
			if (settled) return;
			killedByTimeout = true;
			child.kill("SIGTERM");
		}, timeoutMs);
		child.stdout.on("data", (chunk) => {
			if (stdout.length < MAX_OUTPUT_BYTES) stdout += String(chunk).slice(0, MAX_OUTPUT_BYTES - stdout.length);
		});
		child.stderr.on("data", (chunk) => {
			if (stderr.length < MAX_OUTPUT_BYTES) stderr += String(chunk).slice(0, MAX_OUTPUT_BYTES - stderr.length);
		});
		child.on("error", (error) => {
			if (settled) return;
			settled = true;
			clearTimeout(timer);
			const spawnCode = typeof error.code === "string" && /^E[A-Z0-9]+$/.test(error.code) ? error.code : null;
			reject(new HelperExecutionError(null, false, safeDiagnostic(null, spawnCode, false, error.message)));
		});
		child.on("close", (code, signal) => {
			if (settled) return;
			settled = true;
			clearTimeout(timer);
			if (code === 0) {
				try {
					const result = parseBurstResult(stdout);
					if (result.reaction !== reaction) throw new HelperExecutionError(null, false, "The Teams helper returned a burst result for a different reaction.");
					resolve(result);
				} catch (error) {
					reject(error);
				}
				return;
			}
			const timedOut = signal === "SIGTERM" && killedByTimeout;
			reject(new HelperExecutionError(code, timedOut, safeDiagnostic(code, null, timedOut, stderr)));
		});
	});

	return {
		completion,
		stop() {
			if (stopped) return;
			stopped = true;
			child.stdin.end();
		},
	};
}

export class OperationLock {
	private owner: symbol | undefined;

	tryAcquire(): symbol | undefined {
		if (this.owner) return undefined;
		const token = Symbol("teams-operation");
		this.owner = token;
		return token;
	}

	release(token: symbol): void {
		if (this.owner === token) this.owner = undefined;
	}

	get busy(): boolean {
		return this.owner !== undefined;
	}
}

export type CommandExecution = { status: "completed"; result: TeamsCommandResult } | { status: "busy" };

export class CommandCoordinator {
	private readonly lock: OperationLock;
	private readonly invoke: (command: TeamsCommand) => Promise<TeamsCommandResult>;

	constructor(lock = new OperationLock(), invoke: (command: TeamsCommand) => Promise<TeamsCommandResult> = runTeamsCommand) {
		this.lock = lock;
		this.invoke = invoke;
	}

	async execute(command: TeamsCommand): Promise<CommandExecution> {
		const token = this.lock.tryAcquire();
		if (!token) return { status: "busy" };
		try {
			return { status: "completed", result: await this.invoke(command) };
		} finally {
			this.lock.release(token);
		}
	}
}

export type ReactionExecution = { status: "completed"; result: ReactionCommandResult } | { status: "busy" };

export class ReactionCoordinator {
	private readonly lock: OperationLock;
	private readonly invoke: (reaction: Reaction) => Promise<ReactionCommandResult>;

	constructor(lock = new OperationLock(), invoke: (reaction: Reaction) => Promise<ReactionCommandResult> = runReactionHelper) {
		this.lock = lock;
		this.invoke = invoke;
	}

	async execute(reaction: Reaction): Promise<ReactionExecution> {
		const token = this.lock.tryAcquire();
		if (!token) return { status: "busy" };
		try {
			return { status: "completed", result: await this.invoke(reaction) };
		} finally {
			this.lock.release(token);
		}
	}
}

export type BurstStart = { status: "started"; completion: Promise<BurstResult> } | { status: "busy" };

export class ReactionBurstCoordinator {
	private active: { context: string; session: BurstSession } | undefined;
	private readonly lock: OperationLock;
	private readonly startBurst: (reaction: Reaction) => BurstSession;

	constructor(lock = new OperationLock(), startBurst: (reaction: Reaction) => BurstSession = startReactionBurst) {
		this.lock = lock;
		this.startBurst = startBurst;
	}

	start(context: string, reaction: Reaction): BurstStart {
		if (this.active) return { status: "busy" };
		const token = this.lock.tryAcquire();
		if (!token) return { status: "busy" };
		let session: BurstSession;
		try {
			session = this.startBurst(reaction);
		} catch (error) {
			this.lock.release(token);
			throw error;
		}
		this.active = { context, session };
		const completion = (async () => {
			try {
				return await session.completion;
			} finally {
				if (this.active?.session === session) this.active = undefined;
				this.lock.release(token);
			}
		})();
		return { status: "started", completion };
	}

	stop(context: string): void {
		if (this.active?.context === context) this.active.session.stop();
	}

	stopAll(): void {
		this.active?.session.stop();
	}
}

export function isPersistentCommand(command: string): command is TeamsCommand {
	return ["status", "mute", "unmute", "camera-on", "camera-off"].includes(command);
}

type PersistentChild = Omit<BurstChildLike, "stdin"> & {
	stdin: InputLike & {
		write(data: string): unknown;
		on(event: "error", listener: (error: Error) => void): unknown;
	};
};

type PersistentOptions = {
	helperPath?: string;
	timeoutMs?: number;
	spawnImpl?: (file: string, args: readonly string[], options: { stdio: ["pipe", "pipe", "pipe"] }) => PersistentChild;
};

type PendingControl = {
	id: number;
	generation: number;
	command: TeamsCommand;
	resolve: (result: TeamsCommandResult) => void;
	reject: (error: HelperExecutionError) => void;
	timer: ReturnType<typeof setTimeout>;
};

/** Owns one child and one in-flight request. Failed presses are never replayed. */
export class PersistentControlClient {
	private child: PersistentChild | undefined;
	private pending: PendingControl | undefined;
	private sequence = 0;
	private generation = 0;
	private buffer = "";
	private terminating = false;
	private terminalError: HelperExecutionError | undefined;
	private killTimer: ReturnType<typeof setTimeout> | undefined;
	private idleTimer: ReturnType<typeof setTimeout> | undefined;
	private stopped: Promise<void> = Promise.resolve();
	private didStop: (() => void) | undefined;
	private forceFresh = true;
	private paused = false;
	private readonly visible = new Set<string>();
	private readonly listeners = new Set<(state: TeamsState) => void>();

	private readonly options: PersistentOptions;

	constructor(options: PersistentOptions = {}) { this.options = options; }

	retain(context: string): void {
		this.visible.add(context);
		if (this.idleTimer) clearTimeout(this.idleTimer);
	}

	release(context: string): void {
		this.visible.delete(context);
		if (this.visible.size === 0 && !this.pending) this.stop();
	}

	subscribe(listener: (state: TeamsState) => void): () => void {
		this.listeners.add(listener);
		return () => this.listeners.delete(listener);
	}

	invalidate(): void { this.forceFresh = true; this.generation += 1; }

	pause(): void {
		this.paused = true;
		this.invalidate();
		if (this.child && !this.terminating) this.write({ kind: "pause", generation: this.generation });
	}

	resume(): void {
		this.paused = false;
		this.invalidate();
		if (this.child && !this.terminating) this.write({ kind: "resume", generation: this.generation });
	}

	stop(): void {
		if (!this.child || this.terminating) return;
		if (this.pending) this.terminalError = new HelperExecutionError(null, false, "The Teams helper was stopped before confirmation.");
		this.terminating = true;
		this.child.stdin.end();
		this.scheduleKill();
	}

	async execute(command: TeamsCommand): Promise<TeamsCommandResult> {
		if (!isPersistentCommand(command)) throw new HelperExecutionError(64, false, "An invalid persistent command was blocked before launching the helper.");
		if (this.pending || this.paused) throw new HelperExecutionError(null, false, "The Teams helper is busy or stopping.");
		if (this.terminating) await this.stopped;
		if (this.pending || this.paused || this.terminating) throw new HelperExecutionError(null, false, "The Teams helper is busy or stopping.");
		if (this.idleTimer) clearTimeout(this.idleTimer);
		this.start();
		return new Promise((resolve, reject) => {
			const id = ++this.sequence;
			const timer = setTimeout(() => this.abort(new HelperExecutionError(null, true, "The Teams helper timed out.")), this.options.timeoutMs ?? DEFAULT_TIMEOUT_MS);
			this.pending = { id, generation: this.generation, command, resolve, reject, timer };
			const forceFresh = this.forceFresh;
			this.forceFresh = false;
			this.write({ id, command, forceFresh, generation: this.generation });
		});
	}

	private start(): void {
		if (this.child) return;
		const helperPath = this.options.helperPath ?? DEFAULT_HELPER_PATH;
		ensureExecutable(helperPath);
		const child = (this.options.spawnImpl ?? (spawn as unknown as NonNullable<PersistentOptions["spawnImpl"]>))(
			helperPath, ["serve"], { stdio: ["pipe", "pipe", "pipe"] },
		);
		this.child = child;
		this.stopped = new Promise(resolve => { this.didStop = resolve; });
		this.buffer = "";
		this.forceFresh = true;
		child.stdout.on("data", chunk => { if (this.child === child && !this.terminating) this.receive(String(chunk)); });
		child.stderr.on("data", () => { /* Native diagnostics are intentionally suppressed for privacy. */ });
		child.stdin.on("error", () => {
			if (this.child === child) this.abort(new HelperExecutionError(null, false, "The Teams helper input pipe closed."));
		});
		child.on("error", error => {
			if (this.child !== child) return;
			const spawnCode = typeof error.code === "string" && /^E[A-Z0-9]+$/.test(error.code) ? error.code : null;
			this.abort(new HelperExecutionError(null, false, safeDiagnostic(null, spawnCode, false, "")));
		});
		child.on("close", code => {
			if (this.child !== child) return;
			if (this.killTimer) clearTimeout(this.killTimer);
			const pending = this.pending;
			this.pending = undefined;
			this.child = undefined;
			this.buffer = "";
			this.terminating = false;
			this.forceFresh = true;
			if (pending) {
				clearTimeout(pending.timer);
				pending.reject(this.terminalError ?? new HelperExecutionError(code, false, safeDiagnostic(code, null, false, "")));
			}
			this.terminalError = undefined;
			this.didStop?.();
		});
	}

	private write(message: Record<string, unknown>): void {
		try { this.child?.stdin.write(`${JSON.stringify(message)}\n`); }
		catch { this.abort(new HelperExecutionError(null, false, "The Teams helper input pipe closed.")); }
	}

	private receive(chunk: string): void {
		this.buffer += chunk;
		let newline: number;
		while ((newline = this.buffer.indexOf("\n")) >= 0) {
			const line = this.buffer.slice(0, newline);
			this.buffer = this.buffer.slice(newline + 1);
			if (line.length > MAX_OUTPUT_BYTES) { this.protocolFailure(); return; }
			try {
				const message = JSON.parse(line) as Record<string, unknown>;
				if (typeof message !== "object" || message === null || Array.isArray(message)) throw new Error();
				if (message.event === "state" && message.id === undefined) {
					const state = parseTeamsResult(JSON.stringify(message.result));
					if (state.command !== "status") throw new Error();
					if (!this.paused && !this.pending && message.generation === this.generation) {
						this.forceFresh = false;
						for (const listener of this.listeners) listener(state);
					}
					continue;
				}
				const pending = this.pending;
				if (!pending || message.id !== pending.id || message.generation !== pending.generation || !Number.isInteger(message.exitCode)) throw new Error();
				let result: TeamsCommandResult | undefined;
				if (message.exitCode === 0) {
					result = parseTeamsResult(JSON.stringify(message.result));
					if (result.command !== pending.command) throw new Error();
				}
				clearTimeout(pending.timer);
				this.pending = undefined;
				if (result) pending.resolve(result);
				else pending.reject(new HelperExecutionError(message.exitCode as number, false, safeDiagnostic(message.exitCode as number, null, false, "")));
				if (this.visible.size === 0) {
					this.idleTimer = setTimeout(() => this.stop(), 500);
					this.idleTimer.unref();
				}
			} catch {
				this.protocolFailure();
				return;
			}
		}
		if (this.buffer.length > MAX_OUTPUT_BYTES) this.protocolFailure();
	}

	private protocolFailure(): void {
		this.abort(new HelperExecutionError(null, false, "The Teams helper returned an invalid persistent response."));
	}

	private abort(error: HelperExecutionError): void {
		if (!this.child || this.terminating) return;
		this.terminalError = error;
		this.terminating = true;
		this.child.kill("SIGTERM");
		this.scheduleKill();
	}

	private scheduleKill(): void {
		const child = this.child;
		this.killTimer = setTimeout(() => {
			if (child && this.child === child) child.kill("SIGKILL");
		}, 300);
		this.killTimer.unref();
	}
}

/** The SDK has no public close event. A bounded read-only heartbeat detects loss. */
export function watchPluginConnection(
	probe: () => Promise<unknown>, onLost: () => void,
	intervalMs = 5_000, timeoutMs = 3_000,
): () => void {
	let active = true;
	let probing = false;
	let deadline: ReturnType<typeof setTimeout> | undefined;
	const stop = () => { active = false; clearInterval(interval); if (deadline) clearTimeout(deadline); };
	const lost = () => { if (active) { stop(); onLost(); } };
	const interval = setInterval(() => {
		if (!active || probing) return;
		probing = true;
		deadline = setTimeout(lost, timeoutMs);
		deadline.unref();
		Promise.resolve().then(probe).then(() => {
			if (deadline) clearTimeout(deadline);
			probing = false;
		}, lost);
	}, intervalMs);
	interval.unref();
	return stop;
}
