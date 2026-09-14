import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import test from "node:test";

const here = dirname(fileURLToPath(import.meta.url));
const server = resolve(here, "../index.mjs");
const helper = resolve(here, "fixtures/fake-helper.sh");

function request(message, extraEnv = {}) {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(process.execPath, [server], {
      env: { ...process.env, CODEX_CALL_HELPER: helper, ...extraEnv },
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code !== 0) return reject(new Error(`server exited ${code}: ${stderr}`));
      const lines = stdout.trim().split("\n").filter(Boolean);
      resolvePromise(lines.map((line) => JSON.parse(line)));
    });
    child.stdin.end(`${JSON.stringify(message)}\n`);
  });
}

test("lists the five public call tools", async () => {
  const [response] = await request({ jsonrpc: "2.0", id: 1, method: "tools/list" });
  assert.deepEqual(
    response.result.tools.map((tool) => tool.name),
    [
      "start_phone_call",
      "end_phone_call",
      "get_phone_call_state",
      "set_call_audio_mode",
      "call_audio_status",
    ],
  );
});

test("waits for active call audio and tells Codex it is live on the call", async () => {
  const [response] = await request(
    {
      jsonrpc: "2.0",
      id: 2,
      method: "tools/call",
      params: {
        name: "start_phone_call",
        arguments: {
          number: "+441234567890",
          goal: "Test the call",
          opening_line: "Hello, this is Codex, Aaron's AI assistant, testing the call.",
        },
      },
    },
    { FAKE_STATUS_STATE: "IN_CALL" },
  );
  assert.equal(response.result.isError, false);
  assert.match(response.result.content[0].text, /live on the telephone/i);
  assert.match(response.result.content[0].text, /REMOTE PERSON/i);
  assert.match(
    response.result.content[0].text,
    /You may open with: Hello, this is Codex, Aaron's AI assistant, testing the call\./,
  );
});

test("returns a clear error instead of polling forever when call audio never activates", async () => {
  const [response] = await request(
    {
      jsonrpc: "2.0",
      id: 6,
      method: "tools/call",
      params: {
        name: "start_phone_call",
        arguments: {
          number: "+441234567890",
          goal: "Test the call",
          opening_line: "Hello, this is Codex calling for Aaron.",
        },
      },
    },
    {
      FAKE_STATUS_STATE: "STARTING_CALL",
      CODEX_CALL_CONNECT_TIMEOUT_MS: "5",
      CODEX_CALL_CONNECT_POLL_MS: "1",
    },
  );
  assert.equal(response.result.isError, true);
  assert.match(response.result.content[0].text, /did not become audio-active/i);
  assert.match(response.result.content[0].text, /do not claim the call connected/i);
});

test("propagates a JSON helper failure even when its exit status is zero", async () => {
  const [response] = await request(
    {
      jsonrpc: "2.0",
      id: 3,
      method: "tools/call",
      params: { name: "get_phone_call_state", arguments: {} },
    },
    { FAKE_HELPER_FAIL: "1" },
  );
  assert.equal(response.result.isError, true);
  assert.equal(response.result.content[0].text, "simulated helper failure");
});

test("does not falsely claim a hang-up when macOS refuses to close the call app", async () => {
  const [response] = await request(
    {
      jsonrpc: "2.0",
      id: 5,
      method: "tools/call",
      params: { name: "end_phone_call", arguments: {} },
    },
    { FAKE_HANGUP_FAIL: "1" },
  );
  assert.equal(response.result.isError, true);
  assert.match(response.result.content[0].text, /did not confirm/);
});

test("rejects an empty call goal before invoking the helper", async () => {
  const [response] = await request({
    jsonrpc: "2.0",
    id: 4,
    method: "tools/call",
    params: {
      name: "start_phone_call",
      arguments: {
        number: "+441234567890",
        goal: "",
        opening_line: "Hello, this is Codex calling for Aaron.",
      },
    },
  });
  assert.equal(response.result.isError, true);
  assert.match(response.result.content[0].text, /non-empty goal/);
});

test("allows omitting the opening line", async () => {
  const [response] = await request(
    {
      jsonrpc: "2.0",
      id: 7,
      method: "tools/call",
      params: {
        name: "start_phone_call",
        arguments: {
          number: "+441234567890",
          goal: "Test the call",
        },
      },
    },
    { FAKE_STATUS_STATE: "IN_CALL" },
  );
  assert.equal(response.result.isError, false);
  assert.match(response.result.content[0].text, /live on the telephone/i);
});
