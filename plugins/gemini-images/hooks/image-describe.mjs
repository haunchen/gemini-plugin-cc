#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

const imagePath = process.argv[2];
if (!imagePath) {
  process.exit(1);
}

const geminiBin = process.env.GEMINI_BIN || "gemini";
const geminiModel = process.env.GEMINI_MODEL || "flash";
const systemPromptPath = resolve(__dirname, "../system-prompts/image-describe.md");

const prompt = `Read this image: @${imagePath}`;

const args = ["-m", geminiModel, "-p", prompt];

const result = spawnSync(geminiBin, args, {
  encoding: "utf8",
  stdio: ["ignore", "pipe", "ignore"],
  env: { ...process.env, GEMINI_SYSTEM_MD: systemPromptPath },
});

if (result.status !== 0) {
  process.exit(1);
}

const output = (result.stdout || "").trim();
if (!output) {
  process.exit(1);
}

process.stdout.write(output);
