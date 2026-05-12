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
const imageDir = dirname(imagePath);

// Escape spaces per gemini CLI docs: "@My\ Documents/file.txt". Without
// escaping, AT_COMMAND_PATH_REGEX truncates at the first space and falls
// back to plain-text parsing; the model usually recovers, but we shouldn't
// rely on that implicit retry when one replace fixes it deterministically.
const escapedPath = imagePath.replace(/ /g, "\\ ");
const prompt = `Read this image: @${escapedPath}`;

// Gemini CLI sandboxes @<path> to its workspace (cwd + temp). Include the
// image's dir so it can load files from ~/.claude/image-cache/ or anywhere
// else Claude Code stores them. Without this, read_file silently fails and
// Gemini hallucinates a description from the filename alone.
const args = ["-m", geminiModel, "--include-directories", imageDir, "-p", prompt];

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
