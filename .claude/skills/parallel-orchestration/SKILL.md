---
name: parallel-orchestration
description: Orchestrate substantial multi-part work as a parallel-agent build, with a plan, conflict-free tracks on frozen contracts, verified gates and bounded fixes. Use when asked to parallelise, use multiple agents or orchestrate, or for a large feature round, multi-file refactor, multi-platform build or bulk sweep. Small or tightly coupled work stays inline.
argument-hint: [task description]
effort: high
---

# Parallel Agent Orchestration

You are the **orchestrator**. You plan, dispatch, gate and integrate. Workers execute.
The goal is a shorter elapsed time at equal quality; every step that does not serve
that is overhead. Lean tiers are hints about brevity and never weaken a gate in this
skill.

## 1. Size sets the process, risk sets the gates

| Size | Looks like | Process |
|---|---|---|
| **Small** | One known file, a config tweak, a rename across two files | Do it inline. No plan, no workers. |
| **Medium** | Small feature, a few files | State the approach, note the split inline, use workers only for independent tracks. No plan file. |
| **Large** | Feature round, multi-file refactor, multi-platform build, bulk sweep | Everything below. |

When the user supplies a complete written spec, it is the plan: freeze the contracts it
defines, note track ownership in a few lines, and dispatch. Do not rewrite it as a
plan file.

**High-risk work** (destructive or permanent actions, sudo, OS settings, data
migration, security code) keeps its size's process and adds, at any size: the risk
stated to the user, a rollback path, user approval before acting, and an independent
review. A small security fix does not need two plans and five agents.

## 2. Roles and models

| Role | Agent type | Use for |
|---|---|---|
| Orchestrator | this session, Fable or Opus at high effort | Requirements, contracts, decomposition, gates, integration judgment |
| Scout | `scout-sonnet` (low effort) | One narrow question about files, callers or seams. Use an inline search when that is cheaper. |
| Judgment worker | `worker-opus` | Security, concurrency, protocol semantics, unresolved design, hard diagnosis, integration |
| Mechanical worker | `worker-sonnet` | Settled contract and observable correctness: implementation, bulk edits, tests, UI against a frozen state |
| Reviewer | `reviewer-opus` | Review of integrated, consequential changes |

- Route each track by its own difficulty, not the feature's. A complex feature still
  has Sonnet tracks; a detailed plan does not make a silent failure mode safe for Sonnet.
- When a Sonnet worker reports missing design or cannot diagnose a failure, settle the
  design yourself or move the track to Opus. Do not wait for repeated failures.
- Spawned agents never run the premium model. If the session is on a weaker model than
  the planning needs, say so in one line before planning so the user can switch.
- The agent types above pin model and effort. Any other type gets an explicit `model`.
  Use `general-purpose` only when a worker needs web access.
- For N near-identical tasks or fixed-stage pipelines, use the Workflow tool, and only
  when the user has opted into it.

## 3. When to spawn

Spawn only when all hold: the pieces share no files or mutable resources, each costs
more to do than to brief, serial execution would be meaningfully slower, and each has
a precise contract and a verify command.

**Break-even.** Orchestration costs about 2 minutes of planning, packets and gates
before it saves anything, and elapsed time is set by the slowest track. If one session
could write the whole job in about 5 minutes (roughly 1,500 lines of new code from a
settled spec), build it inline, even when asked to parallelise, and say so in one line.

**Balance.** Split by expected output, not by module name. No track should be much
larger than the others; divide the largest until it is not the bottleneck.

**Take a track yourself.** While workers run you are otherwise idle. Own one track,
preferably the glue or the one that depends on the most context you already hold, and
write it during the wait. Gates on returned tracks come first when both are ready.

Agent count is the number of ready, independent tracks that the machine can run
without contention for CPU, memory, ports or build state. Do not fill slots.

Fan-out buys wall-clock, not tokens: every worker re-pays the cost of reading the
plan and the repo. When speed does not matter and the round is small, one worker in
series is the token-optimal choice.

## 4. Plan

1. **Look first.** Read enough source to find the seams. Send a scout only when
   missing context blocks the decomposition.
2. **Requirements.** Settle requirements, design and decisions with the user. For
   Large and high-risk work the user approves before anything is dispatched; silence
   is not approval. Ask in the same exchange whether to commit at green milestones.
3. **Tracks.** Per track: inputs and dependencies, files it owns (tests, generated
   files and shared config included), files it must not touch, contracts, agent type,
   and acceptance as an exact command, a bar and what must be observably true.
4. **Self-review**, as if a stranger wrote it. Fix the plan; do not note and proceed.

| Hunt for flaws | Hunt for savings |
|---|---|
| Two tracks sharing a file, port or build state | Undersized tracks to merge or do inline |
| A consumer dispatched before its contract is complete | A track on a bigger model than it needs, or a smaller one |
| Fix loops with no hard stop | Work an existing library or earlier round already covers |
| Missing dependencies or acceptance | Vague criteria to make executable, over-testing to cut |

5. **Post the plan** to the user and proceed. Step 2 is the approval gate.

**Plan file.** For Large work, write decisions, tracks and every frozen contract to
`docs/plans/<task>.md`, or to task scratch space when the repo should not carry it.
The orchestrator is its only writer. Workers and scouts return findings in their
report.

## 5. Decomposition rules

- **One writer per file and per mutable resource.** Ownership moves only after the
  previous writer has stopped.
- **Contracts are complete and literal.** Every cross-track interface is written once,
  as compilable code, with the semantics code cannot show: errors, lifecycle, ordering.
  A reference to an undefined type is not a contract. Each contract file has one owner.
- **Contracts stay frozen while consumers run.** To change one, pause its consumers,
  change it, then redispatch them.
- **Deliberate designs are listed** with their reason, under `DO NOT CHANGE`.
- **Focused tests may compile.** Each worker verifies its own track using isolated
  build output, port and scratch directory. Where isolation is impossible, schedule
  that step exclusively. Whole-project gates belong to the integration owner.

## 6. Dispatch

Launch every ready track in **one message**. Start a dependent track as soon as the
specific tracks it needs are accepted; hold a whole phase back only for shared build
state. Workers run in the background and the harness notifies you. Do not poll; use
the wait for your own track.

A packet carries what is specific to the track, and everything the worker cannot
infer from the files it is told to read. Workers start only when the whole dispatch
message is written, so every packet line delays every worker. When a spec or plan on
disk already states the requirement, name the file and section and do not restate it;
such a packet is about 100 words. Completeness outranks brevity only for what is
written nowhere else.

```
REPO: <path>; instruction files that apply
READ FIRST: <plan file>, sections <contracts>, <track N>, DO NOT CHANGE
OWNS: <files>            MUST NOT TOUCH: <files> (owner)
TASK: <outcome and non-goals, specific enough that two workers would build the same thing>
VERIFY: <command> -> <bar>; <observable checklist>
RESOURCES: <build dir, port, scratch dir>
```

Point to stable plan sections instead of pasting them; inline a contract only when it
is a few lines. The worker agent types carry the standing rules (fix budget, no git
writes, exit status and log, report shape). Paste those rules only into packets for
other agent types.

## 7. Gates, integration and fix limits

**Per track, on return:**

1. Read the diff against the packet: in scope, complete, deliberate designs intact,
   only owned files touched.
2. Check the evidence: command, real exit status, log. Rerun the verify command when
   it takes seconds, when evidence is missing or when inputs changed since it ran.
   Otherwise reuse it; the final suite below is the backstop.
3. A malformed or incomplete report gets one follow-up to the same agent, not
   acceptance.
4. A reported deviation holds dependent tracks until you have judged it. One that
   changes scope or a public contract needs the user's approval.

**Integration.** The orchestrator runs integration checks. Hand substantial
integration coding to one `worker-opus` with explicit ownership of the glue files. It
repairs another track's files only after that track's worker has stopped and
ownership has been transferred.

**Fix limit: 2 rounds per track.** A round is one fix-and-reverify cycle after the
original handoff, however many edits it contains, whoever performs it, and whether
gate, integration or review triggered it. After round 2 fails, stop that track and
report: what it was meant to deliver, what each attempt tried and why it failed, the
state of its files, your diagnosis. Independent tracks continue.

## 8. Review

Review integrated work that is consequential: high-risk changes and substantial
integration. One `reviewer-opus` by default; add reviewers only for separate,
substantial risk areas, and run them in parallel.

- Give each a scope, a threat model and the stakes. Vague stakes produce vague findings.
- Weight scope toward integration code, where no worker's tests reach.
- Systems with several implementations get an interop question: do they agree on the
  wire?
- Pass workers' CONCERNS on as leads, not conclusions.
- Substantiate a blocking finding yourself before assigning its fix.

## 9. Finish

After the **last** change to code or configuration, run the full relevant test suite
and every gate the repository requires: lint, format, types, build. A later fix
invalidates earlier results for what it touches. Report commands, results and what
could not be tested.

Commit at green milestones only when the user authorised commits for this build, using
the commit skill. Workers never commit. Pushing always follows the commit skill's
approval rule.

## 10. When things go wrong

| Problem | Response |
|---|---|
| Worker died or hung | Resume it with SendMessage; its transcript is intact. Ask it to confirm edits are on disk, re-verify and report. Confirm it is inactive before reassigning its files. |
| Apparent hang | Check for two workers contending for a port, daemon or build directory. |
| Worker needs a file it does not own | It asks; you transfer ownership or make the change yourself. |
| Long-reading worker | It keeps notes in its own scratch file so compaction loses nothing. |
| Same topic given to two agents | Only as a deliberate cross-check you will reconcile. |

A worked decomposition is in `example.md` beside this file. Read it only when you
need a model for splitting a feature round.
