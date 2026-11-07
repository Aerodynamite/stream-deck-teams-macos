import assert from "node:assert/strict";
import fs from "node:fs/promises";
import test from "node:test";

const manifest = JSON.parse(await fs.readFile(new URL("../com.laurens-bolle.teams-reactions.sdPlugin/manifest.json", import.meta.url), "utf8"));

test("the shipped manifest does not enable the Node.js inspector", () => {
	// "enabled" or "break" makes Stream Deck start the plugin with --inspect in
	// developer mode, which lets any local process attach and run code in it.
	assert.equal(manifest.Nodejs?.Debug, undefined);
});
