import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
	HelperExecutionError,
	ReactionCoordinator,
	runReactionHelper,
} from "../src/helper-runner.ts";

test("runs an allow-listed reaction with execFile", async () => {
	await runReactionHelper("like", { helperPath: "/usr/bin/true" });
});

test("blocks invalid reactions before launching a process", async () => {
	let launched = false;
	const execFileImpl = () => {
		launched = true;
	};

	await assert.rejects(
		runReactionHelper("raise-hand", { execFileImpl }),
		(error) => error instanceof HelperExecutionError && error.exitCode === null,
	);
	assert.equal(launched, false);
});

test("maps helper exit codes to privacy-safe diagnostics", async () => {
	await assert.rejects(
		runReactionHelper("love", { helperPath: "/usr/bin/false" }),
		(error) =>
			error instanceof HelperExecutionError &&
			error.exitCode === 1 &&
			error.diagnostic === "Accessibility permission is required.",
	);
});

test("does not overlap helper invocations", async () => {
	let release;
	let invocationCount = 0;
	const gate = new Promise((resolve) => {
		release = resolve;
	});
	const coordinator = new ReactionCoordinator(async () => {
		invocationCount += 1;
		await gate;
	});

	const first = coordinator.execute("like");
	await Promise.resolve();
	assert.equal(await coordinator.execute("love"), "busy");
	assert.equal(invocationCount, 1);

	release();
	assert.equal(await first, "completed");
});

test("releases the execution lock after a helper failure", async () => {
	let attempts = 0;
	const coordinator = new ReactionCoordinator(async () => {
		attempts += 1;
		if (attempts === 1) throw new Error("fixture failure");
	});

	await assert.rejects(coordinator.execute("surprise"), /fixture failure/);
	assert.equal(await coordinator.execute("surprise"), "completed");
	assert.equal(attempts, 2);
});

test("restores a missing execute bit before running the packaged helper", async () => {
	const dir = await fs.mkdtemp(path.join(os.tmpdir(), "teams-reaction-"));
	const helperPath = path.join(dir, "teams-reaction");
	await fs.writeFile(helperPath, "#!/bin/sh\nexit 0\n", { mode: 0o644 });

	await runReactionHelper("like", { helperPath });

	const mode = (await fs.stat(helperPath)).mode & 0o777;
	assert.equal(mode & 0o111, 0o111);
});

test("reports a spawn failure code instead of a generic diagnostic", async () => {
	const dir = await fs.mkdtemp(path.join(os.tmpdir(), "teams-reaction-"));
	const helperPath = path.join(dir, "missing-helper");

	await assert.rejects(
		runReactionHelper("love", { helperPath }),
		(error) =>
			error instanceof HelperExecutionError &&
			error.exitCode === null &&
			error.diagnostic === "The helper could not be started (ENOENT).",
	);
});
