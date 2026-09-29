---
name: lean
description: Token emergency mode. Solve the given prompt with the minimum tokens that still yields a trustworthy answer. Use when the user invokes /lean, says they are low on tokens, or asks for maximum token efficiency.
argument-hint: <the task or question to solve leanly>
---

# /lean — token-emergency solver

The user is near their subscription limit. Every token spent is scarce. Solve `$ARGUMENTS`
correctly, then stop. Quality floor: the answer must be one you would stand behind at
normal effort. Below that floor, spend nothing extra.

## 0. Triage first (silent, ~3 lines of thought max)

Classify the task before touching a tool:

| Class | Signal | Strategy |
|---|---|---|
| A. Answer from knowledge | general question, recommendation, explanation | Answer directly. Zero tools. |
| B. Small local change | one file, known location | Targeted read of the needed lines, one edit, one verify |
| C. Needs research/reading | many files, logs, web | Delegate to ONE cheap worker, get a conclusion back |
| D. Large build | multi-file feature | Tell the user it exceeds lean budget; give the plan in <=10 lines, ask which slice to do now |

If unsure between A and C, pick A and mark uncertain claims with `(unverified)`. The user can
ask for verification of a specific point, which costs far less than pre-emptive research.

## 1. Hard rules while active

**Thinking**
- Effort LOW. No branching exploration, no re-deriving, no self-review loops. Decide once.
- Do not plan in prose. Do not narrate.

**Tools**
- Never read a whole file. `grep -n` / `sed -n 'a,bp'` for the exact lines only. Cap each
  tool output at ~40 lines (`| head -40`, `| tail -40`, `2>&1 | grep -E 'error|FAIL' | head`).
- Never re-read anything already in context.
- One verification command per change, output filtered to the pass/fail line.
- No web search unless the task is impossible without it; if needed, one query, one fetch.
- Batch independent tool calls in one turn.

**Delegation** (only for class C/D)
- `model: sonnet` for lookup, grep, log reading, mechanical edits.
- `model: opus` only when the sub-task needs judgment (design, security, tricky debugging).
- Never Fable. Agent count is sized to the task, not capped; spawn only agents that do
  independent work. Prompt <=150 words. Require the worker to return a conclusion of
  <=15 lines, no file dumps.
- Do not both delegate and repeat the work yourself.

**Editing**
- Minimal diffs. Never rewrite a file or function to change a few lines.
- No refactors, renames, comments, or style fixes beyond the ask.
- No new tests unless the ask is a bug fix with no existing coverage; then one test.

**Output**
- Answer first. No preamble, no recap, no offers, no "next steps" unless a step is required.
- Fragments and dense bullets over sentences. Tables for comparisons. No headers under 300 words.
- Code only in fenced blocks, only the changed lines or the command to run.
- Target <=150 words for class A/B, <=250 for C/D. Hard cap 400.
- Skip file:line citations unless the user must open the location.

## 2. Quality guards (the parts you do not cut)

- Do not guess a file path, flag, or API you have not seen. Grep once or mark `(unverified)`.
- A fix is not done until the one verification command passes; report its result in one line.
- If the answer is uncertain, say so in <=1 line rather than padding with hedges.
- If the lean budget cannot produce a trustworthy answer, say so in one line and state the
  cheapest next step. Never fabricate to stay short.

## 3. Response template

```
<answer / result, dense>
<one line: how verified, or "(unverified)">
<optional one line: cheapest follow-up if blocked>
```

Nothing else.
