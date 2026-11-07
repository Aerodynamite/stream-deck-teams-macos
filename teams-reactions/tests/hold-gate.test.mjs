import assert from "node:assert/strict";
import test from "node:test";

import { HoldGate } from "../src/hold-gate.ts";

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

test("a tap released before the hold time never fires", () => {
	const timers = fakeTimers();
	const gate = new HoldGate(1500, timers);
	let fired = 0;
	assert.equal(gate.press("key", () => { fired += 1; }), true);
	assert.equal(gate.release("key"), "cancelled");
	timers.fireAll();
	assert.equal(fired, 0);
});

test("holding past the hold time fires exactly once, from the timer", () => {
	const timers = fakeTimers();
	const gate = new HoldGate(1500, timers);
	let fired = 0;
	gate.press("key", () => { fired += 1; });
	assert.equal([...timers.pending.values()][0].ms, 1500);
	assert.equal(fired, 0, "nothing fires on key-down");
	timers.fireAll();
	assert.equal(fired, 1);
	assert.equal(gate.release("key"), "idle", "key-up after firing is not a cancellation");
	timers.fireAll();
	assert.equal(fired, 1);
});

test("a repeated key-down while armed does not start a second timer", () => {
	const timers = fakeTimers();
	const gate = new HoldGate(1500, timers);
	let fired = 0;
	gate.press("key", () => { fired += 1; });
	assert.equal(gate.press("key", () => { fired += 1; }), false);
	assert.equal(timers.pending.size, 1);
	timers.fireAll();
	assert.equal(fired, 1);
});

test("cancelAll disarms every key, for disconnect and wake", () => {
	const timers = fakeTimers();
	const gate = new HoldGate(1500, timers);
	let fired = 0;
	gate.press("a", () => { fired += 1; });
	gate.press("b", () => { fired += 1; });
	gate.cancelAll();
	assert.equal(timers.pending.size, 0);
	assert.equal(gate.isArmed("a"), false);
	timers.fireAll();
	assert.equal(fired, 0);
});

test("keys are independent", () => {
	const timers = fakeTimers();
	const gate = new HoldGate(1500, timers);
	const fired = [];
	gate.press("a", () => fired.push("a"));
	gate.press("b", () => fired.push("b"));
	gate.release("a");
	timers.fireAll();
	assert.deepEqual(fired, ["b"]);
});

test("rejects a non-positive hold time", () => {
	assert.throws(() => new HoldGate(0), RangeError);
	assert.throws(() => new HoldGate(Number.NaN), RangeError);
});
