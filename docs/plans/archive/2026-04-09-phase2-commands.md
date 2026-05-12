# Phase 2 Expanded Commands Implementation Plan

Goal: 新增 /gemini:ask、/gemini:adversarial-review、/gemini:security-review 三個 command，既有 command 加入 --model 參數支援。全部零程式碼。

Architecture: 延續 Phase 1 純 Markdown plugin 架構。每個 command 是一個 .md 檔（YAML frontmatter + 指示），搭配對應的 system prompt .md 檔。Claude Code 解析 command.md 後自行組裝 bash 指令呼叫 Gemini CLI。

Tech Stack: Claude Code Plugin framework, Gemini CLI, Markdown

Spec: `docs/specs/gemini-review.md` (R7~R13)

---

### Task 1: 既有 review.md 加入 --model 參數

Implements: `gemini-review.md` #R7

Files:
- Modify: `plugins/gemini/commands/review.md`

Step 1: 修改 review.md，在 Step 1 前加入模型判斷，Step 3 改用變數

將 `plugins/gemini/commands/review.md` 完整替換為：

```markdown
---
description: Get a code review from Gemini CLI as a second opinion
allowed-tools: Bash, Read, Glob
argument-hint: [file-path] [--model <model>]
---

Perform a code review using Gemini CLI. This gives you a second opinion from a different AI model.

## Step 1: Parse --model parameter

Check if $ARGUMENTS contains `--model <value>`:
- If yes: extract the value as MODEL, remove `--model <value>` from $ARGUMENTS
- If no: set MODEL = flash

Valid model values: flash, pro, flash-lite, or any full model name.

## Step 2: Determine input

If $ARGUMENTS (after --model removal) is provided:
- If it contains glob characters (* or ?), use the Glob tool to expand it, then Read each matched file
- Otherwise, Read the single file directly
- Concatenate all file contents as REVIEW_INPUT

If $ARGUMENTS is empty:
- Run: `git diff HEAD 2>/dev/null`
- If the command fails (e.g., no commits yet) or the diff is empty, also try: `git diff --cached`
- If still empty, tell the user: "No changes found. Provide a file path or make some changes first."
- Store the diff output as REVIEW_INPUT

## Step 3: Locate system prompt

Determine the absolute path to the system prompt file:
- The file is at `system-prompts/review.md` relative to this plugin's root directory
- The plugin root is the parent of the `commands/` directory containing this file
- Store this absolute path as SYSTEM_PROMPT_PATH

## Step 4: Call Gemini CLI

Run the following bash command, passing REVIEW_INPUT via stdin to avoid shell escaping issues:

```bash
echo "$REVIEW_INPUT" | GEMINI_SYSTEM_MD="$SYSTEM_PROMPT_PATH" gemini -o text -m $MODEL
```

Note: We pipe input via stdin instead of -p flag to handle large diffs and special characters safely.

## Step 5: Present results

Show the Gemini response directly to the user. Do not modify, summarize, or reformat it.

## Error handling

- If `gemini` command is not found: suggest running `/gemini:setup` first
- If the command fails with an auth error: suggest running `gemini` interactively to re-authenticate via Google OAuth
- If the command times out or returns an error: show the error message and suggest retrying
```

Step 2: Commit
```
feat: add --model parameter to /gemini:review
```

---

### Task 2: 既有 setup.md 加入 --model 參數

Implements: `gemini-review.md` #R7

Files:
- Modify: `plugins/gemini/commands/setup.md`

Step 1: 修改 setup.md，在 Summary 後加入模型測試步驟

將 `plugins/gemini/commands/setup.md` 完整替換為：

```markdown
---
description: Check Gemini CLI installation, version, and authentication status
allowed-tools: Bash
argument-hint: [--model <model>]
---

## Step 0: Parse --model parameter

Check if $ARGUMENTS contains `--model <value>`:
- If yes: extract the value as MODEL, remove `--model <value>` from $ARGUMENTS
- If no: set MODEL = flash

Run the following checks in order and report the results:

## 1. Check if Gemini CLI is installed

Run: `which gemini || where gemini 2>/dev/null`

- If found: report the path
- If not found: tell the user to install it with `npm install -g @google/gemini-cli` or visit https://github.com/google-gemini/gemini-cli

## 2. Check Gemini CLI version

Run: `gemini --version`

- Report the version number

## 3. Check authentication

Run: `test -f ~/.gemini/oauth_creds.json && echo "OAuth credentials found" || echo "OAuth credentials not found"`

- If found: confirm Google OAuth is configured
- If not found: tell the user to run `gemini` interactively to authenticate via Google OAuth

## 4. Test model availability

Run: `echo "ping" | gemini -o text -m $MODEL`

- If the command succeeds: report that the model is available
- If the command fails with a model error: report the error and suggest trying a different model

## Summary

After all checks, provide a one-line summary:
- All checks passed: "Gemini CLI is ready to use with model $MODEL. Try /gemini:review"
- Something missing: list what needs to be fixed
```

Step 2: Commit
```
feat: add --model parameter and model test to /gemini:setup
```

---

### Task 3: Ask system prompt

Implements: `gemini-review.md` #R8

Files:
- Create: `plugins/gemini/system-prompts/ask.md`

Step 1: 建立 system-prompts/ask.md

```markdown
You are a senior software engineer. Answer questions concisely and directly.

## Input

You will receive either:
- A question only
- A question followed by file contents as context (separated by a line of dashes)

## Rules

- Answer the question directly. Do not restate the question.
- If file contents are provided as context, reference specific line numbers when relevant.
- If you are unsure, say so. Do not guess.
- Keep answers short. Use code blocks when showing code.
- Do not provide unsolicited advice beyond the question asked.
```

Step 2: Commit
```
feat: add ask system prompt for Gemini CLI
```

---

### Task 4: /gemini:ask command

Implements: `gemini-review.md` #R8, #R12, #R7

Files:
- Create: `plugins/gemini/commands/ask.md`

Step 1: 建立 commands/ask.md

```markdown
---
description: Ask Gemini a question, optionally with file context
allowed-tools: Bash, Read, Glob
argument-hint: <question> [file-path] [--model <model>]
---

Ask Gemini CLI a question. Optionally provide a file for context.

## Step 1: Parse --model parameter

Check if $ARGUMENTS contains `--model <value>`:
- If yes: extract the value as MODEL, remove `--model <value>` from $ARGUMENTS
- If no: set MODEL = flash

## Step 2: Determine input

Split the remaining $ARGUMENTS into QUESTION and optional FILE_PATH:
- Check if the last token in $ARGUMENTS is an existing file path (use `test -f <last_token>`)
- If yes: Read the file contents as CONTEXT, the rest of $ARGUMENTS is the QUESTION
- If no: the entire $ARGUMENTS is the QUESTION, no CONTEXT

If QUESTION is empty, tell the user: "Please provide a question. Example: /gemini:ask What does this regex do? src/utils.js"

Build ASK_INPUT:
- If CONTEXT exists:
  ```
  Question: {QUESTION}
  ---
  {CONTEXT}
  ```
- If no CONTEXT:
  ```
  Question: {QUESTION}
  ```

## Step 3: Locate system prompt

Determine the absolute path to the system prompt file:
- The file is at `system-prompts/ask.md` relative to this plugin's root directory
- The plugin root is the parent of the `commands/` directory containing this file
- Store this absolute path as SYSTEM_PROMPT_PATH

## Step 4: Call Gemini CLI

Run the following bash command, passing ASK_INPUT via stdin:

```bash
echo "$ASK_INPUT" | GEMINI_SYSTEM_MD="$SYSTEM_PROMPT_PATH" gemini -o text -m $MODEL
```

## Step 5: Present results

Show the Gemini response directly to the user. Do not modify, summarize, or reformat it.

## Error handling

- If `gemini` command is not found: suggest running `/gemini:setup` first
- If the command fails with an auth error: suggest running `gemini` interactively to re-authenticate via Google OAuth
- If the command times out or returns an error: show the error message and suggest retrying
```

Step 2: Commit
```
feat: add /gemini:ask command
```

---

### Task 5: Adversarial review system prompt

Implements: `gemini-review.md` #R9

Files:
- Create: `plugins/gemini/system-prompts/adversarial-review.md`

Step 1: 建立 system-prompts/adversarial-review.md

```markdown
You are a devil's advocate code reviewer. Your job is NOT to find bugs — it is to challenge design decisions and propose alternatives.

## Input

You will receive either:
- A git diff (unified diff format)
- File contents to review

## Output Format

Always respond in this exact structure:

## Challenge Summary
{One sentence summarizing the main design concerns}

## Challenges

### [IMPACT] {Topic}
- **Current approach**: {What the code currently does}
- **Challenge**: {Why this approach might not be the best choice}
- **Alternative**: {A concrete alternative approach with trade-offs}

(Repeat for each challenge. Order by impact: HIGH first, then MEDIUM, then LOW.)

## Overall Assessment: {SOLID | RECONSIDER | RETHINK}

## Impact Levels

- **HIGH**: Fundamental architecture or design choices that would be costly to change later. Worth reconsidering now.
- **MEDIUM**: Implementation choices where a different approach could meaningfully improve maintainability, performance, or clarity.
- **LOW**: Minor design preferences where the current approach works but an alternative has small advantages.

## Assessment Criteria

- **SOLID**: The design decisions are well-justified. No significant alternatives would clearly be better.
- **RECONSIDER**: One or more MEDIUM/HIGH challenges where an alternative approach is worth seriously evaluating.
- **RETHINK**: One or more HIGH challenges where the current approach has fundamental issues.

## Rules

- Do NOT report bugs, style issues, or code quality problems. That is what /gemini:review is for.
- Focus on the "why" — challenge the reasoning behind decisions, not the syntax.
- For each challenge, the alternative MUST be concrete and actionable, not vague ("consider a better approach").
- If the design decisions are sound, output Overall Assessment: SOLID with an empty Challenges section.
- Do NOT invent challenges to appear thorough. Only challenge decisions where you genuinely see a better alternative.
- Be respectful but direct. "This works, but here's why X might serve you better" — not "this is wrong".
```

Step 2: Commit
```
feat: add adversarial review system prompt
```

---

### Task 6: /gemini:adversarial-review command

Implements: `gemini-review.md` #R9, #R7

Files:
- Create: `plugins/gemini/commands/adversarial-review.md`

Step 1: 建立 commands/adversarial-review.md

```markdown
---
description: Get a devil's advocate review that challenges your design decisions
allowed-tools: Bash, Read, Glob
argument-hint: [file-path] [--model <model>]
---

Get a devil's advocate review using Gemini CLI. Instead of finding bugs, this challenges your design decisions and proposes alternatives.

## Step 1: Parse --model parameter

Check if $ARGUMENTS contains `--model <value>`:
- If yes: extract the value as MODEL, remove `--model <value>` from $ARGUMENTS
- If no: set MODEL = flash

## Step 2: Determine input

If $ARGUMENTS (after --model removal) is provided:
- If it contains glob characters (* or ?), use the Glob tool to expand it, then Read each matched file
- Otherwise, Read the single file directly
- Concatenate all file contents as REVIEW_INPUT

If $ARGUMENTS is empty:
- Run: `git diff HEAD 2>/dev/null`
- If the command fails (e.g., no commits yet) or the diff is empty, also try: `git diff --cached`
- If still empty, tell the user: "No changes found. Provide a file path or make some changes first."
- Store the diff output as REVIEW_INPUT

## Step 3: Locate system prompt

Determine the absolute path to the system prompt file:
- The file is at `system-prompts/adversarial-review.md` relative to this plugin's root directory
- The plugin root is the parent of the `commands/` directory containing this file
- Store this absolute path as SYSTEM_PROMPT_PATH

## Step 4: Call Gemini CLI

Run the following bash command, passing REVIEW_INPUT via stdin:

```bash
echo "$REVIEW_INPUT" | GEMINI_SYSTEM_MD="$SYSTEM_PROMPT_PATH" gemini -o text -m $MODEL
```

## Step 5: Present results

Show the Gemini response directly to the user. Do not modify, summarize, or reformat it.

## Error handling

- If `gemini` command is not found: suggest running `/gemini:setup` first
- If the command fails with an auth error: suggest running `gemini` interactively to re-authenticate via Google OAuth
- If the command times out or returns an error: show the error message and suggest retrying
```

Step 2: Commit
```
feat: add /gemini:adversarial-review command
```

---

### Task 7: Security review system prompt

Implements: `gemini-review.md` #R10, #R11

Files:
- Create: `plugins/gemini/system-prompts/security-review.md`

Step 1: 建立 system-prompts/security-review.md

```markdown
You are a security researcher specializing in application security. Your job is to find security vulnerabilities — nothing else.

## Input

You will receive either:
- A git diff (unified diff format)
- File contents to review

## Output Format

Always respond in this exact structure:

## Security Summary
{One sentence summarizing the overall security posture}

## Vulnerabilities

### [SEVERITY] {Vulnerability Type} — {file_path}:{line_number}
- **Risk**: {How this could be exploited and what an attacker could achieve}
- **Attack example**: {A concrete attack payload, curl command, or exploitation scenario}
- **Evidence**: {The specific code that causes this vulnerability}
- **Fix**: {How to fix it, with code}
- **Verify**: {How to verify the fix works — a test, curl command, or manual step}
- **CWE**: {CWE ID, e.g., CWE-79}

(Repeat for each vulnerability. Order by severity: CRITICAL first, then HIGH, MEDIUM, LOW.)

## Verdict: {SECURE | CONCERNS | VULNERABLE}

## Severity Levels

- **CRITICAL**: Actively exploitable vulnerabilities allowing remote code execution, authentication bypass, or full data breach. Fix immediately.
- **HIGH**: Exploitable vulnerabilities like SQL injection, XSS with session theft, SSRF, path traversal. Must fix before deployment.
- **MEDIUM**: Security weaknesses that increase attack surface — missing rate limiting, overly permissive CORS, missing security headers, information leakage via error messages.
- **LOW**: Defense-in-depth improvements — missing CSP directives, cookie attributes not fully hardened, minor configuration improvements.

## Verdict Criteria

- **SECURE**: No vulnerabilities found.
- **CONCERNS**: One or more MEDIUM or LOW vulnerabilities found.
- **VULNERABLE**: One or more CRITICAL or HIGH vulnerabilities found.

## Checklist

Check for ALL of the following that apply to the code:

**Injection & Input**
- SQL / NoSQL injection (parameterized queries?)
- XSS — reflected, stored, DOM-based (output encoding?)
- Command injection (shell escaping?)
- Path traversal (input sanitization?)
- SSRF (URL validation?)
- Unsafe deserialization

**Authentication & Authorization**
- Hardcoded secrets, API keys, passwords
- Broken authentication flows
- Missing or bypassable authorization checks
- Insecure token/session management (HttpOnly, Secure, SameSite?)
- CSRF protection missing on state-changing endpoints

**Configuration & Headers**
- Missing Content-Security-Policy
- Overly permissive CORS (Access-Control-Allow-Origin: *)
- Missing X-Frame-Options, X-Content-Type-Options
- Debug/stack traces exposed in production error responses

**Dependencies & Supply Chain**
- Known CVEs in dependencies
- Outdated packages with security patches available

**Data Protection**
- Sensitive data logged or exposed in responses
- Missing rate limiting on authentication or sensitive endpoints
- Insecure cryptographic practices

## Rules

- ONLY report security vulnerabilities. Do NOT report code quality, style, or performance issues.
- Every finding MUST include a concrete attack example — not just "this could be exploited".
- Every finding MUST include a CWE reference.
- If there are no security vulnerabilities, output Verdict: SECURE with an empty Vulnerabilities section.
- Do NOT invent vulnerabilities to appear thorough.
- Be specific: always include file path and line number.
```

Step 2: Commit
```
feat: add security review system prompt
```

---

### Task 8: /gemini:security-review command

Implements: `gemini-review.md` #R10, #R7

Files:
- Create: `plugins/gemini/commands/security-review.md`

Step 1: 建立 commands/security-review.md

```markdown
---
description: Get a security-focused review that checks for vulnerabilities
allowed-tools: Bash, Read, Glob
argument-hint: [file-path] [--model <model>]
---

Get a security-focused review using Gemini CLI. This checks for OWASP Top 10 vulnerabilities, injection attacks, auth flaws, hardcoded secrets, and more.

## Step 1: Parse --model parameter

Check if $ARGUMENTS contains `--model <value>`:
- If yes: extract the value as MODEL, remove `--model <value>` from $ARGUMENTS
- If no: set MODEL = flash

## Step 2: Determine input

If $ARGUMENTS (after --model removal) is provided:
- If it contains glob characters (* or ?), use the Glob tool to expand it, then Read each matched file
- Otherwise, Read the single file directly
- Concatenate all file contents as REVIEW_INPUT

If $ARGUMENTS is empty:
- Run: `git diff HEAD 2>/dev/null`
- If the command fails (e.g., no commits yet) or the diff is empty, also try: `git diff --cached`
- If still empty, tell the user: "No changes found. Provide a file path or make some changes first."
- Store the diff output as REVIEW_INPUT

## Step 3: Locate system prompt

Determine the absolute path to the system prompt file:
- The file is at `system-prompts/security-review.md` relative to this plugin's root directory
- The plugin root is the parent of the `commands/` directory containing this file
- Store this absolute path as SYSTEM_PROMPT_PATH

## Step 4: Call Gemini CLI

Run the following bash command, passing REVIEW_INPUT via stdin:

```bash
echo "$REVIEW_INPUT" | GEMINI_SYSTEM_MD="$SYSTEM_PROMPT_PATH" gemini -o text -m $MODEL
```

## Step 5: Present results

Show the Gemini response directly to the user. Do not modify, summarize, or reformat it.

## Error handling

- If `gemini` command is not found: suggest running `/gemini:setup` first
- If the command fails with an auth error: suggest running `gemini` interactively to re-authenticate via Google OAuth
- If the command times out or returns an error: show the error message and suggest retrying
```

Step 2: Commit
```
feat: add /gemini:security-review command
```

---

### Task 9: Manual testing

Files: none (verification only)

Step 1: 驗證 plugin 目錄結構
```bash
find plugins/gemini -type f | sort
```

Expected output:
```
plugins/gemini/.claude-plugin/plugin.json
plugins/gemini/commands/adversarial-review.md
plugins/gemini/commands/ask.md
plugins/gemini/commands/review.md
plugins/gemini/commands/security-review.md
plugins/gemini/commands/setup.md
plugins/gemini/system-prompts/adversarial-review.md
plugins/gemini/system-prompts/ask.md
plugins/gemini/system-prompts/review.md
plugins/gemini/system-prompts/security-review.md
```

Step 2: 重新載入 plugin 並測試各 command
```
# 重啟 Claude Code session 載入新 command
/gemini:setup
/gemini:ask What is a closure in JavaScript?
/gemini:ask What does this file do? plugins/gemini/commands/review.md
/gemini:review
/gemini:adversarial-review plugins/gemini/commands/review.md
/gemini:security-review plugins/gemini/commands/review.md
```

Step 3: 測試 --model 參數
```
/gemini:review --model pro
/gemini:ask --model pro What is a promise?
```

Step 4: 最終 commit（如有微調）
```
chore: Phase 2 commands complete
```
