import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
	CommandCoordinator,
	HelperExecutionError,
	OperationLock,
	ReactionBurstCoordinator,
	ReactionCoordinator,
	parseBurstResult,
	parseTeamsResult,
	runReactionHelper,
	runTeamsCommand,
	startReactionBurst,
} from "../src/helper-runner.ts";

const STATE_RESULT = {
	meetingActive: true,
	microphone: "muted",
	camera: "off",
	backgroundBlur: "unknown",
	hand: "lowered",
	command: "status",
	changed: false,
};

function execResult(result, capture = {}) {
	return (file, args, options, callback) => {
		capture.file = file;
		capture.args = args;
		capture.options = options;
		callback(null, `${JSON.stringify(result)}\n`, "");
	};
}

test("runs an allow-listed state command and parses JSON", async () => {
	const capture = {};
	const result = await runTeamsCommand("status", { helperPath: "/fixture/helper", execFileImpl: execResult(STATE_RESULT, capture) });
	assert.deepEqual(capture.args, ["status"]);
	assert.equal(result.microphone, "muted");
	assert.equal(result.backgroundBlur, "unknown");
});

test("runs an allow-listed reaction with explicit react arguments", async () => {
	const capture = {};
	const result = await runReactionHelper("love", {
		execFileImpl: execResult({ command: "react", reaction: "love", changed: true, accessibilityAccepted: 1 }, capture),
	});
	assert.deepEqual(capture.args, ["react", "love"]);
	assert.equal(result.accessibilityAccepted, 1);
});

test("blocks invalid commands and reactions before launching a process", async () => {
	let launched = false;
	const execFileImpl = () => { launched = true; };
	await assert.rejects(runTeamsCommand("toggle-everything", { execFileImpl }), HelperExecutionError);
	await assert.rejects(runReactionHelper("raise-hand", { execFileImpl }), HelperExecutionError);
	assert.equal(launched, false);
});

test("rejects incomplete helper JSON instead of inventing state", () => {
	assert.throws(() => parseTeamsResult('{"meetingActive":true}'), /incomplete state result/);
	assert.throws(() => parseBurstResult('{"command":"burst"}'), /incomplete burst result/);
});

test("maps helper exit codes to privacy-safe diagnostics", async () => {
	await assert.rejects(
		runTeamsCommand("status", { helperPath: "/usr/bin/false" }),
		(error) => error instanceof HelperExecutionError && error.exitCode === 1 && error.diagnostic === "Accessibility permission is required.",
	);
});

test("restores a missing execute bit before running the packaged helper", async () => {
	const dir = await fs.mkdtemp(path.join(os.tmpdir(), "teams-reaction-"));
	const helperPath = path.join(dir, "teams-reaction");
	await fs.writeFile(helperPath, "fixture", { mode: 0o644 });

	await runReactionHelper("like", {
		helperPath,
		execFileImpl: execResult({ command: "react", reaction: "like", changed: true, accessibilityAccepted: 1 }),
	});

	const mode = (await fs.stat(helperPath)).mode & 0o777;
	assert.equal(mode & 0o111, 0o111);
});

test("reports a spawn failure code instead of a generic diagnostic", async () => {
	const dir = await fs.mkdtemp(path.join(os.tmpdir(), "teams-reaction-"));
	const helperPath = path.join(dir, "missing-helper");

	await assert.rejects(
		runReactionHelper("love", { helperPath }),
		(error) =>
			error instanceof HelperExecutionError
			&& error.exitCode === null
			&& error.diagnostic === "The helper could not be started (ENOENT).",
	);
});

test("one lock prevents state commands and reactions from overlapping", async () => {
	const lock = new OperationLock();
	let release;
	const gate = new Promise((resolve) => { release = resolve; });
	const commands = new CommandCoordinator(lock, async () => {
		await gate;
		return STATE_RESULT;
	});
	const reactions = new ReactionCoordinator(lock, async () => ({ command: "react", reaction: "love", changed: true, accessibilityAccepted: 1 }));

	const first = commands.execute("status");
	await Promise.resolve();
	assert.deepEqual(await reactions.execute("love"), { status: "busy" });
	release();
	assert.equal((await first).status, "completed");
	assert.equal((await reactions.execute("love")).status, "completed");
});

test("command coordinator releases the lock after helper failure", async () => {
	let attempts = 0;
	const coordinator = new CommandCoordinator(new OperationLock(), async () => {
		attempts += 1;
		if (attempts === 1) throw new Error("fixture failure");
		return STATE_RESULT;
	});
	await assert.rejects(coordinator.execute("status"), /fixture failure/);
	assert.equal((await coordinator.execute("status")).status, "completed");
});

class FakeStream extends EventEmitter {}

class FakeChild extends EventEmitter {
	stdout = new FakeStream();
	stderr = new FakeStream();
	stdinEnded = false;
	killedWith = undefined;
	stdin = { end: () => { this.stdinEnded = true; } };
	kill(signal) {
		this.killedWith = signal;
		queueMicrotask(() => this.emit("close", null, signal));
		return true;
	}
}

test("burst runner starts one helper and stops it by closing stdin", async () => {
	const child = new FakeChild();
	let capturedArgs;
	const session = startReactionBurst("love", {
		spawnImpl: (_file, args) => { capturedArgs = args; return child; },
	});
	assert.deepEqual(capturedArgs, ["burst", "love"]);
	session.stop();
	assert.equal(child.stdinEnded, true);
	child.stdout.emit("data", JSON.stringify({ command: "burst", reaction: "love", attempted: 1, accessibilityAccepted: 1, elapsedMs: 180, stopReason: "key-up" }));
	child.emit("close", 0, null);
	assert.equal((await session.completion).accessibilityAccepted, 1);
});

test("restores a missing execute bit before starting a reaction burst", async () => {
	const dir = await fs.mkdtemp(path.join(os.tmpdir(), "teams-reaction-"));
	const helperPath = path.join(dir, "teams-reaction");
	await fs.writeFile(helperPath, "fixture", { mode: 0o644 });
	const child = new FakeChild();
	const session = startReactionBurst("love", { helperPath, spawnImpl: () => child });

	const mode = (await fs.stat(helperPath)).mode & 0o777;
	assert.equal(mode & 0o111, 0o111);
	child.stdout.emit("data", JSON.stringify({ command: "burst", reaction: "love", attempted: 1, accessibilityAccepted: 1, elapsedMs: 180, stopReason: "key-up" }));
	child.emit("close", 0, null);
	await session.completion;
});

test("burst runner contains a missing key-up with a timeout", async () => {
	const child = new FakeChild();
	const session = startReactionBurst("like", { timeoutMs: 15, spawnImpl: () => child });
	await assert.rejects(session.completion, (error) => error instanceof HelperExecutionError && error.timedOut);
	assert.equal(child.killedWith, "SIGTERM");
});

test("burst runner still reports a timeout when the helper ignores key-up", async () => {
	const child = new FakeChild();
	const session = startReactionBurst("like", { timeoutMs: 15, spawnImpl: () => child });
	session.stop();
	await assert.rejects(session.completion, (error) => error instanceof HelperExecutionError && error.timedOut);
});

test("burst coordinator matches key-up by action context and stays exclusive", async () => {
	let resolveBurst;
	let stopCount = 0;
	const completion = new Promise((resolve) => { resolveBurst = resolve; });
	const coordinator = new ReactionBurstCoordinator(new OperationLock(), () => ({ completion, stop: () => { stopCount += 1; } }));
	const started = coordinator.start("key-a", "love");
	assert.equal(started.status, "started");
	assert.deepEqual(coordinator.start("key-b", "like"), { status: "busy" });
	coordinator.stop("key-b");
	assert.equal(stopCount, 0);
	coordinator.stop("key-a");
	assert.equal(stopCount, 1);
	resolveBurst({ command: "burst", reaction: "love", attempted: 1, accessibilityAccepted: 1, elapsedMs: 100, stopReason: "key-up" });
	await started.completion;
});
