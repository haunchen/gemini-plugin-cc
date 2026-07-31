#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { dirname } from "node:path";

const imagePath = process.argv[2];
if (!imagePath) {
  process.exit(1);
}

const agyBin = process.env.AGY_BIN || "agy";
const agyModel = process.env.AGY_MODEL || "gemini-3.6-flash-high";
const imageDir = dirname(imagePath);

// The system prompt lives in the gemini-image-describe agent, installed via
// `agy plugin install <plugin-root>/agy`. agy has no per-call system prompt
// injection (no GEMINI_SYSTEM_MD equivalent), so the prompt must be
// registered up front. Note that --agent silently ignores unknown names:
// a missing install yields a generic description instead of an error.
const prompt = `Read this image: ${imagePath}`;

// agy sandboxes file reads to its workspace. Include the image's dir so it
// can load files from ~/.claude/image-cache/ or anywhere else Claude Code
// stores them. Without this, the read fails and the model hallucinates a
// description from the filename alone.
const args = [
  "--agent", "gemini-image-describe",
  "--model", agyModel,
  "--add-dir", imageDir,
  "--print-timeout", "3m",
  "-p", prompt,
];

const result = spawnSync(agyBin, args, {
  encoding: "utf8",
  stdio: ["ignore", "pipe", "ignore"],
});

if (result.status !== 0) {
  process.exit(1);
}

const output = (result.stdout || "").trim();
if (!output) {
  process.exit(1);
}

process.stdout.write(output);
