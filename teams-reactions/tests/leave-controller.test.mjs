import assert from "node:assert/strict";
import process from "node:process";
import test from "node:test";

import { HoldGate } from "../src/hold-gate.ts";
import { LEAVE_ARMED_IMAGE, LEAVE_HOLD_MS, LeaveController } from "../src/leave-controller.ts";

function fakeTimers() {
	let next = 1;
	const pending = new Map();
	return {
		pending,
		set(callback, ms) { const id = next++; pending.set(id, { callback, ms }); return id; },
		clear(id) { pending.delete(id); },
		fireAll() { for (const [id, { callback }] of [...pending]) { pending.delete(id); callback(); } },
	};
}

/** A Stream Deck key that records calls. `failing` names methods that reject. */
function fakeKey(id = "key", failing = {}) {
	const calls = [];
	const record = (name, ...args) => {
		calls.push(args.length ? [name, ...args] : [name]);
		const failure = failing[name];
		const reject = typeof failure === "function" ? failure(...args) : failure;
		return reject ? Promise.reject(new Error(`${name} failed`)) : Promise.resolve();
	};
	return {
		id,
		calls,
		setImage: (...args) => record("setImage", ...args),
		showAlert: () => record("showAlert"),
		showOk: () => record("showOk"),
	};
}

function fakeLogger() {
	const lines = [];
	return {
		lines,
		info: message => lines.push(["info", message]),
		warn: message => lines.push(["warn", message]),
		reportError: (operation, error) => lines.push(["error", operation, error]),
	};
}

function setup(execute = async () => ({ status: "completed" })) {
	const timers = fakeTimers();
	const logger = fakeLogger();
	let executions = 0;
	const controller = new LeaveController(async () => {
		executions += 1;
		return execute();
	}, logger, new HoldGate(LEAVE_HOLD_MS, timers));
	return { timers, logger, controller, executions: () => executions };
}

const flush = () => new Promise(resolve => setImmediate(resolve));

test("a tap restores the image, alerts and never executes", async () => {
	const { timers, logger, controller, executions } = setup();
	const key = fakeKey();
	await controller.keyDown(key, false);
	assert.deepEqual(key.calls, [["setImage", LEAVE_ARMED_IMAGE]]);
	await controller.keyUp(key);
	await flush();
	timers.fireAll();
	await flush();
	assert.equal(executions(), 0);
	assert.deepEqual(key.calls, [["setImage", LEAVE_ARMED_IMAGE], ["setImage"], ["showAlert"]]);
	assert.deepEqual(logger.lines, [["info", `Leave cancelled: the key was released before ${LEAVE_HOLD_MS} ms.`]]);
});

test("a hold executes once, from the timer, then shows OK", async () => {
	const { timers, logger, controller, executions } = setup();
	const key = fakeKey();
	await controller.keyDown(key, false);
	assert.equal([...timers.pending.values()][0].ms, LEAVE_HOLD_MS);
	assert.equal(executions(), 0, "nothing executes on key-down");
	timers.fireAll();
	await flush();
	assert.equal(executions(), 1);
	await controller.keyUp(key);
	await flush();
	assert.equal(executions(), 1);
	assert.deepEqual(key.calls, [["setImage", LEAVE_ARMED_IMAGE], ["setImage"], ["showOk"]], "key-up after the hold does not alert");
	assert.deepEqual(logger.lines, [["info", "Teams meeting leave completed."]]);
});

test("a busy coordinator warns and alerts", async () => {
	const { timers, logger, controller, executions } = setup(async () => ({ status: "busy" }));
	const key = fakeKey();
	await controller.keyDown(key, false);
	timers.fireAll();
	await flush();
	assert.equal(executions(), 1);
	assert.deepEqual(key.calls, [["setImage", LEAVE_ARMED_IMAGE], ["setImage"], ["showAlert"]]);
	assert.deepEqual(logger.lines, [["warn", "Ignored leave because another Teams operation is running."]]);
});

test("a throwing execute reports the error and alerts", async () => {
	const failure = new Error("helper crashed");
	const { timers, logger, controller } = setup(async () => { throw failure; });
	const key = fakeKey();
	await controller.keyDown(key, false);
	timers.fireAll();
	await flush();
	assert.deepEqual(key.calls, [["setImage", LEAVE_ARMED_IMAGE], ["setImage"], ["showAlert"]]);
	assert.deepEqual(logger.lines, [["error", "Teams command leave", failure]]);
});

test("a Multi Action is refused with an alert", async () => {
	const { timers, logger, controller, executions } = setup();
	const key = fakeKey();
	await controller.keyDown(key, true);
	assert.equal(timers.pending.size, 0, "the gate is not armed");
	timers.fireAll();
	await flush();
	assert.equal(executions(), 0);
	assert.deepEqual(key.calls, [["showAlert"]]);
	assert.deepEqual(logger.lines, [["warn", "Ignored leave inside a multi-action because Leave requires a held key."]]);
});

test("a repeat key-down is ignored", async () => {
	const { timers, controller, executions } = setup();
	const key = fakeKey();
	await controller.keyDown(key, false);
	await controller.keyDown(key, false);
	assert.equal(timers.pending.size, 1);
	assert.deepEqual(key.calls, [["setImage", LEAVE_ARMED_IMAGE]]);
	timers.fireAll();
	await flush();
	assert.equal(executions(), 1);
});

test("disappear disarms and restores the image", async () => {
	const { timers, logger, controller, executions } = setup();
	const key = fakeKey();
	await controller.keyDown(key, false);
	controller.disappear(key.id);
	await flush();
	assert.equal(timers.pending.size, 0);
	timers.fireAll();
	await flush();
	assert.equal(executions(), 0);
	assert.deepEqual(key.calls, [["setImage", LEAVE_ARMED_IMAGE], ["setImage"]]);
	assert.deepEqual(logger.lines, []);
	controller.disappear("never-seen");
	assert.deepEqual(key.calls.length, 2, "an unknown key is a no-op");
});

test("cancelAll disarms and restores every key", async () => {
	const { timers, controller, executions } = setup();
	const first = fakeKey("a");
	const second = fakeKey("b");
	await controller.keyDown(first, false);
	await controller.keyDown(second, false);
	controller.cancelAll();
	await flush();
	assert.equal(timers.pending.size, 0);
	timers.fireAll();
	await flush();
	assert.equal(executions(), 0);
	for (const key of [first, second]) assert.deepEqual(key.calls, [["setImage", LEAVE_ARMED_IMAGE], ["setImage"]]);
	await controller.keyUp(first);
	assert.deepEqual(first.calls.length, 2, "key-up after cancelAll is not a cancellation");
});

test("appear clears the image", async () => {
	const { controller } = setup();
	const key = fakeKey();
	await controller.appear(key);
	assert.deepEqual(key.calls, [["setImage"]]);
});

test("a rejecting armed-image call is logged, the gate stays armed and Leave still runs", async () => {
	const { timers, logger, controller, executions } = setup();
	const key = fakeKey("key", { setImage: image => image === LEAVE_ARMED_IMAGE });
	await controller.keyDown(key, false);
	assert.equal(timers.pending.size, 1);
	assert.deepEqual(logger.lines, [["warn", "Could not show the armed Leave image."]]);
	timers.fireAll();
	await flush();
	assert.equal(executions(), 1);
	assert.deepEqual(key.calls.at(-1), ["showOk"]);
});

test("a rejecting restore before execute is logged and Leave still runs", async () => {
	const { timers, logger, controller, executions } = setup();
	const key = fakeKey("key", { setImage: image => image === undefined });
	await controller.keyDown(key, false);
	timers.fireAll();
	await flush();
	assert.equal(executions(), 1);
	assert.deepEqual(key.calls, [["setImage", LEAVE_ARMED_IMAGE], ["setImage"], ["showOk"]]);
	assert.deepEqual(logger.lines, [
		["warn", "Could not restore the Leave key image."],
		["info", "Teams meeting leave completed."],
	]);
});

test("a rejecting showAlert in the error path leaves no unhandled rejection", async () => {
	const unhandled = [];
	const listener = reason => unhandled.push(reason);
	process.on("unhandledRejection", listener);
	try {
		const failure = new Error("helper crashed");
		const { timers, logger, controller } = setup(async () => { throw failure; });
		const key = fakeKey("key", { showAlert: true });
		await controller.keyDown(key, false);
		timers.fireAll();
		await flush();
		await flush();
		assert.deepEqual(unhandled, []);
		assert.deepEqual(key.calls.at(-1), ["showAlert"]);
		assert.deepEqual(logger.lines, [
			["error", "Teams command leave", failure],
			["warn", "Could not show the Leave alert."],
		]);
	} finally {
		process.off("unhandledRejection", listener);
	}
});
