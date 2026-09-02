import { execFile, spawn } from "node:child_process";
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
const DEFAULT_BURST_TIMEOUT_MS = 4_500;
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

function safeDiagnostic(exitCode: number | null, timedOut: boolean, stderr: string): string {
	if (timedOut) return "The Teams helper timed out.";
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
			const killed = "killed" in error && error.killed === true;
			const timedOut = killed && "signal" in error && error.signal === "SIGTERM";
			reject(new HelperExecutionError(exitCode, timedOut, safeDiagnostic(exitCode, timedOut, stderr)));
		});
	});
}

export function runTeamsCommand(command: string, options: HelperRunnerOptions = {}): Promise<TeamsCommandResult> {
	if (!isTeamsCommand(command)) return Promise.reject(new HelperExecutionError(null, false, "An invalid Teams command was blocked before launching the helper."));
	return runHelper([command], (stdout) => {
		const result = parseTeamsResult(stdout);
		if (result.command !== command) throw new HelperExecutionError(null, false, "The Teams helper returned a result for a different command.");
		return result;
	}, options);
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
			reject(new HelperExecutionError(null, false, safeDiagnostic(null, false, error.message)));
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
			reject(new HelperExecutionError(code, timedOut, safeDiagnostic(code, timedOut, stderr)));
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
