import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import test from "node:test";
import { CommandCoordinator, HelperExecutionError, OperationLock, PersistentControlClient, ReactionCoordinator, watchPluginConnection } from "../src/helper-runner.ts";

const state = { meetingActive: true, microphone: "muted", camera: "on", hand: "lowered", backgroundBlur: "unknown", command: "status", changed: false };

function fixture(options = {}) {
	const children = [];
	const client = new PersistentControlClient({
		helperPath: "/fixture/helper", timeoutMs: 1000, ...options,
		spawnImpl: (_file, args) => {
			assert.deepEqual(args, ["serve"]);
			const child = new EventEmitter();
			child.stdout = new EventEmitter(); child.stderr = new EventEmitter(); child.stdin = new EventEmitter();
			child.requests = []; child.signals = []; child.ended = false;
			child.stdin.write = data => { child.requests.push(JSON.parse(data)); };
			child.stdin.end = () => { child.ended = true; queueMicrotask(() => child.emit("close", 0)); };
			child.kill = signal => { child.signals.push(signal); queueMicrotask(() => child.emit("close", null, signal)); return true; };
			child.reply = (result = state, extra = {}) => {
				const request = child.requests.findLast(message => message.id);
				child.stdout.emit("data", JSON.stringify({ id: request.id, generation: request.generation, exitCode: 0, result: { ...result, command: request.command }, ...extra }) + "\n");
			};
			children.push(child); return child;
		},
	});
	client.retain("key");
	return { client, children };
}

test("persistent client reuses its child and parses fragmented correlated replies", async t => {
	const { client, children } = fixture(); t.after(() => client.stop());
	const first = client.execute("status"); const child = children[0];
	const request = child.requests[0];
	const line = JSON.stringify({ id: request.id, generation: request.generation, exitCode: 0, result: state }) + "\n";
	child.stdout.emit("data", line.slice(0, 35)); child.stdout.emit("data", line.slice(35));
	assert.equal((await first).microphone, "muted");
	const second = client.execute("unmute"); child.reply({ ...state, microphone: "unmuted", changed: true });
	assert.equal((await second).microphone, "unmuted");
	assert.equal(children.length, 1);
	assert.equal(child.requests[0].forceFresh, true); assert.equal(child.requests[1].forceFresh, false);
});

test("invalid commands are blocked before spawning and overlapping requests are rejected", async t => {
	const { client, children } = fixture(); t.after(() => client.stop());
	await assert.rejects(client.execute("leave"), HelperExecutionError); assert.equal(children.length, 0);
	const first = client.execute("status");
	await assert.rejects(client.execute("mute"), /busy/);
	children[0].reply(); await first;
});

test("persistent commands share the operation lock with reactions", async t => {
	const { client, children } = fixture(); t.after(() => client.stop());
	const lock = new OperationLock();
	const commands = new CommandCoordinator(lock, command => client.execute(command));
	const reactions = new ReactionCoordinator(lock, async () => { throw new Error("must not run"); });
	const pending = commands.execute("mute");
	assert.deepEqual(await reactions.execute("love"), { status: "busy" });
	children[0].reply(); await pending; assert.equal(lock.busy, false);
});

test("business errors preserve the child and map privacy-safe diagnostics", async t => {
	const { client, children } = fixture(); t.after(() => client.stop());
	const first = client.execute("mute"); children[0].reply(state, { exitCode: 13 });
	await assert.rejects(first, error => error.exitCode === 13 && /not confirmed/.test(error.diagnostic));
	const next = client.execute("status"); children[0].reply(); await next; assert.equal(children.length, 1);
});

for (const mode of ["wrong-id", "wrong-command", "bad-json", "oversized", "incomplete-state"]) {
	test(`persistent protocol fails closed for ${mode}`, async t => {
		const { client, children } = fixture(); t.after(() => client.stop());
		const pending = client.execute("mute"); const child = children[0];
		const rejected = assert.rejects(pending, /invalid persistent response/);
		if (mode === "wrong-id") child.reply(state, { id: 999 });
		if (mode === "wrong-command") child.reply(state, { result: state });
		if (mode === "bad-json") child.stdout.emit("data", "not JSON\n");
		if (mode === "oversized") child.stdout.emit("data", "x".repeat(65 * 1024));
		if (mode === "incomplete-state") child.reply(state, { result: { command: "mute" } });
		await rejected;
		assert.deepEqual(child.signals, ["SIGTERM"]); assert.equal(child.requests.length, 1);
	});
}

test("crashes are not replayed and the next request starts a fresh helper", async t => {
	const { client, children } = fixture(); t.after(() => client.stop());
	const pending = client.execute("unmute"); const rejected = assert.rejects(pending, HelperExecutionError);
	children[0].emit("close", 12); await rejected; assert.equal(children.length, 1);
	const next = client.execute("status"); children[1].reply(); await next;
	assert.equal(children[1].requests[0].forceFresh, true);
});

test("timeouts kill the old child before allowing a replacement", async t => {
	const { client, children } = fixture({ timeoutMs: 10 }); t.after(() => client.stop());
	await assert.rejects(client.execute("mute"), error => error.timedOut);
	assert.deepEqual(children[0].signals, ["SIGTERM"]);
	const next = client.execute("status"); children[1].reply(); await next;
	assert.equal(children[0].requests.length, 1);
});

test("visibility references retain the helper and release it only after the last control", async () => {
	const { client, children } = fixture(); client.retain("other");
	const pending = client.execute("status"); children[0].reply(); await pending;
	client.release("key"); assert.equal(children[0].ended, false);
	client.release("other"); assert.equal(children[0].ended, true);
});

test("pause/resume generations discard stale events and warm the cache after one-shot operations", async t => {
	const { client, children } = fixture(); t.after(() => client.stop());
	const updates = []; client.subscribe(value => updates.push(value));
	const pending = client.execute("status"); children[0].reply(); await pending;
	client.pause(); client.resume();
	const child = children[0]; const generation = child.requests.at(-1).generation;
	child.stdout.emit("data", JSON.stringify({ event: "state", generation: 0, result: state }) + "\n");
	assert.equal(updates.length, 0);
	child.stdout.emit("data", JSON.stringify({ event: "state", generation, result: state }) + "\n");
	assert.equal(updates.length, 1);
	const next = client.execute("mute"); assert.equal(child.requests.at(-1).forceFresh, false); child.reply(); await next;
});


test("a nonresponsive child is killed before timeout rejection and is never replayed", async t => {
    const { client, children } = fixture({ timeoutMs: 10 }); t.after(() => client.stop());
    const pending = client.execute("mute"); const child = children[0];
    child.kill = signal => {
        child.signals.push(signal);
        if (signal === "SIGKILL") queueMicrotask(() => child.emit("close", null, signal));
        return true;
    };
    const keepAlive = setTimeout(() => {}, 1000);
    try { await assert.rejects(pending, error => error.timedOut); }
    finally { clearTimeout(keepAlive); }
    assert.deepEqual(child.signals, ["SIGTERM", "SIGKILL"]);
    assert.equal(child.requests.length, 1);
});

test("successive commands without visible keys can reuse the ephemeral helper", async t => {
    const { client, children } = fixture(); t.after(() => client.stop());
    const first = client.execute("mute"); client.release("key"); children[0].reply(); await first;
    const second = client.execute("unmute"); children[0].reply(); await second;
    assert.equal(children.length, 1);
});

test("losing the Stream Deck heartbeat fails closed once", async () => {
    let lost = 0, probes = 0;
    const stopped = new Promise(resolve => {
        watchPluginConnection(() => { probes += 1; return new Promise(() => {}); }, () => { lost += 1; resolve(); }, 5, 10);
    });
    const keepAlive = setTimeout(() => {}, 1000);
    try { await stopped; } finally { clearTimeout(keepAlive); }
    assert.equal(lost, 1); assert.equal(probes, 1);
});

test("connection heartbeat stops cleanly without reporting a failure", async () => {
    let lost = false;
    const stop = watchPluginConnection(async () => {}, () => { lost = true; }, 5, 10);
    stop(); await new Promise(resolve => setTimeout(resolve, 20));
    assert.equal(lost, false);
});


test("requests waiting for shutdown cannot overwrite each other on restart", async t => {
    const { client, children } = fixture(); t.after(() => client.stop());
    const first = client.execute("status"); children[0].reply(); await first;
    client.stop();
    const next = client.execute("status");
    const blocked = assert.rejects(client.execute("mute"), /busy/);
    await new Promise(resolve => setImmediate(resolve));
    children[1].reply(); await next; await blocked;
    assert.equal(children[1].requests.length, 1);
});

test("late pipe errors from a closed child cannot terminate its replacement", async t => {
    const { client, children } = fixture(); t.after(() => client.stop());
    const first = client.execute("status"); children[0].reply(); await first;
    client.stop(); const next = client.execute("status");
    await new Promise(resolve => setImmediate(resolve));
    children[0].stdin.emit("error", new Error("late pipe error"));
    assert.deepEqual(children[1].signals, []);
    children[1].reply(); await next;
});
