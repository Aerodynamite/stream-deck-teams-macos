import assert from "node:assert/strict";
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
