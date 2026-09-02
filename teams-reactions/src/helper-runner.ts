import { execFile } from "node:child_process";
import { chmod, stat } from "node:fs/promises";
import { fileURLToPath } from "node:url";

export const REACTIONS = ["like", "love", "applause", "laugh", "surprise"] as const;

export type Reaction = (typeof REACTIONS)[number];

const REACTION_SET: ReadonlySet<string> = new Set(REACTIONS);
const DEFAULT_HELPER_PATH = fileURLToPath(new URL("./teams-reaction", import.meta.url));
const DEFAULT_TIMEOUT_MS = 6_000;
const MAX_OUTPUT_BYTES = 64 * 1024;

type ExecFileCallback = (error: NodeJS.ErrnoException | null, stdout: string, stderr: string) => void;
type ExecFileLike = (
	file: string,
	args: readonly string[],
	options: {
		encoding: "utf8";
		maxBuffer: number;
		timeout: number;
	},
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

const EXECUTE_BITS = 0o111;
const HELPER_MODE = 0o755;

/**
 * The Stream Deck packer stores every archive entry as 0644, so the native helper
 * loses its execute bit when the plugin is installed from a .streamDeckPlugin file.
 * Restore it before spawning so a packaged install works without manual repair.
 */
async function ensureExecutable(helperPath: string): Promise<void> {
	try {
		const { mode } = await stat(helperPath);
		if ((mode & EXECUTE_BITS) === EXECUTE_BITS) return;
		await chmod(helperPath, HELPER_MODE);
	} catch {
		// Leave the real failure to execFile, which reports a spawn error code.
	}
}

function safeDiagnostic(
	exitCode: number | null,
	spawnCode: string | null,
	timedOut: boolean,
	stderr: string,
): string {
	if (timedOut) return "The Teams reaction helper timed out.";
	if (spawnCode !== null) return `The helper could not be started (${spawnCode}).`;

	const diagnostics: Record<number, string> = {
		1: "Accessibility permission is required.",
		2: "Microsoft Teams is not running.",
		3: "No safe meeting reaction control was found.",
		4: "The meeting reaction control could not be opened.",
		5: "The requested reaction was not found before the timeout.",
		6: "The requested reaction could not be pressed.",
		64: "The helper rejected its command arguments.",
	};

	if (exitCode !== null && diagnostics[exitCode]) return diagnostics[exitCode];
	if (stderr.trim().length > 0) return "The helper reported an unrecognized error; details were suppressed for privacy.";
	return "The helper exited unexpectedly without a diagnostic.";
}

export async function runReactionHelper(
	reaction: string,
	options: HelperRunnerOptions = {},
): Promise<void> {
	if (!isReaction(reaction)) {
		throw new HelperExecutionError(null, false, "An invalid reaction was blocked before launching the helper.");
	}

	const helperPath = options.helperPath ?? DEFAULT_HELPER_PATH;
	const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
	const execFileImpl = options.execFileImpl ?? (execFile as ExecFileLike);

	await ensureExecutable(helperPath);

	return new Promise((resolve, reject) => {
		execFileImpl(
			helperPath,
			[reaction],
			{
				encoding: "utf8",
				maxBuffer: MAX_OUTPUT_BYTES,
				timeout: timeoutMs,
			},
			(error, _stdout, stderr) => {
				if (!error) {
					resolve();
					return;
				}

				const rawCode = error.code;
				const exitCode = typeof rawCode === "number" ? rawCode : null;
				const spawnCode = typeof rawCode === "string" && /^E[A-Z0-9]+$/.test(rawCode) ? rawCode : null;
				const killed = "killed" in error && error.killed === true;
				const timedOut = killed && "signal" in error && error.signal === "SIGTERM";
				reject(
					new HelperExecutionError(
						exitCode,
						timedOut,
						safeDiagnostic(exitCode, spawnCode, timedOut, stderr),
					),
				);
			},
		);
	});
}

export type HelperInvoker = (reaction: Reaction) => Promise<void>;

export class ReactionCoordinator {
	private running = false;
	private readonly invoke: HelperInvoker;

	constructor(invoke: HelperInvoker = runReactionHelper) {
		this.invoke = invoke;
	}

	async execute(reaction: Reaction): Promise<"completed" | "busy"> {
		if (this.running) return "busy";

		this.running = true;
		try {
			await this.invoke(reaction);
			return "completed";
		} finally {
			this.running = false;
		}
	}
}
