# qwen on rx 6600 implementation plan

Prepared on 2026-10-16 for an implementation agent running on the operator's real arch linux machine. This document is a handoff specification. No runtime has been installed and no hardware benchmarks have been run by preparing it.

Build a reproducible local text inference service for an AMD Radeon RX 6600 with 8GB VRAM. Optimize single-user generation speed while preserving useful answer quality, low refusal frequency and normal desktop operation. Select the fastest configuration demonstrated on this machine among the candidates that pass the quality and reliability gates. Do not describe the result as the fastest possible implementation across all runtimes.

The starting model is `HauhauCS/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive`, using its `Q4_K_M` GGUF. Qwen3.5-9B is the official 9B model discussed in the earlier benchmark comparison. Models called Qwen3.8-9B are community distillations and must be evaluated as separate checkpoints. Neither a model name nor a finite test establishes universal absence of refusals.

## install

### scope and authorization

When asked to execute this plan, proceed with authorized inspection, staging, implementation, downloads and headless validation. Read the real machine's applicable instructions first. Reuse decisions already authorized by the operator. Do not repeatedly request approval for the same agreed scope.

The baseline dependency set is build tooling, the existing Vulkan stack, python standard-library tooling and pinned upstream llama.cpp source. A HIP experiment is an optional second backend, with its dependency and disk costs reported before installation. This plan does not authorize unrelated upgrades or changes to live desktop configuration. If a required package transaction needs elevated privileges or approval under host rules, prepare its exact package list and command before asking the operator.

The shared desktop guard remains mandatory. Before changing live windows, workspaces, input, displays, audio, desktop services or configuration that automatically reloads the desktop, obtain the action-specific approval required by the installed guard. Show the complete request, target, effect and originating rule. A reply such as `YES DSK-XXXXXX` permits only the exact pending action, with the same actor, arguments and working directory, within the guard's validity period. Never self-approve, alter guard records or bypass a rejected action. Report the actual execution result afterward.

Headless compute and source preparation do not by themselves require desktop approval. They still must respect the shared GPU and any tool-channel restrictions. Do not change GPU clocks, power limits, fan settings, global environment variables, kernel parameters, permissions on device nodes, drivers or firmware to improve a benchmark. Do not stop another user's or agent's workloads. Treat any such proposal as separate scope requiring a concrete review and approval.

Do not commit, publish, expose a network endpoint or enable boot persistence merely because this document has been supplied. Activation follows the operator's actual execution request and applicable host rules. Prepare reviewable artifacts before any outstanding approval step.

### phase 0, inspect and freeze the work contract

The lead agent owns this phase.

1. Read applicable `AGENTS.md` files and the installed parallel-orchestration skill if available. If working in a repository, inspect `git status` and `git log -3` before editing. Preserve unrelated changes.
2. Identify the actual host and GPU. This planning workspace is not evidence of the operator's hardware. Record the GPU PCI address, Vulkan device identifier and name, kernel and Mesa versions, VRAM capacity and free VRAM, CPU model, available RAM, disk space, existing runtimes and current GPU load. Read only task-relevant metadata and redact machine identifiers from shareable reports.
3. Check which Vulkan ICD is active, confirm the RX 6600 rather than an integrated GPU, and check ordinary access to its render node. Confirm usable `vulkaninfo`, `cmake`, `ninja`, C++ compiler, `python3`, `git`, `curl`, `sha256sum` and `flock`. Do not replace working drivers just to obtain a newer version.
4. Inspect local package availability. Expected arch package names include `base-devel`, `cmake`, `ninja`, `git`, `python`, `curl`, `vulkan-headers`, `vulkan-icd-loader`, `vulkan-tools`, `shaderc`, `spirv-headers` and `vulkan-radeon`. Install only missing, needed components. Check names against current package metadata. Never use a partial arch upgrade such as `pacman -Sy` followed by selective installs.
5. Check disk and RAM before downloads or compilation. The initial Q4 model is about 5.63GB. Reserve additional space for source, builds, logs, a comparison model and temporary files. F16 conversion needs roughly 18GB for the source weights plus output, working space and adequate host RAM. Measure requirements rather than assuming the GPU's 8GB describes system RAM.
6. Choose a private, unwatched task directory and record it as `TASK_ROOT` in task-local state. Choose a free loopback port, with 8080 as a preference rather than a requirement. Never evict an existing listener.
7. Create the frozen contracts described under architecture. Before dispatch, resolve and freeze the full immutable llama.cpp commit and selected model repository revision, exact filenames and available upstream content identifiers. Every worker receives these same values. The converter must come from that runtime revision unless a separately justified converter revision is frozen. A changed revision creates a new experiment family rather than silently replacing an existing candidate. Optional model revisions are frozen by the lead before that track starts.
8. Allocate bounded CPU and memory budgets for concurrent builds, downloads and CPU tests. Keep the desktop usable. If the machine is already busy, reduce parallel resource use rather than killing unrelated work.

Stop the dependent track if the target GPU is absent, the model cannot be downloaded within permitted network access, required RAM or disk is unavailable, or the active backend does not support the model. Continue independent preparation and report the smallest needed operator action.

### phase 1, three parallel implementation tracks

Reserve one agent slot for the lead. Run up to three independent workers concurrently. Use fewer workers if fewer slots or insufficient host resources are available. The ownership table under architecture is mandatory.

**Runtime worker** builds and verifies a pinned native Vulkan release of llama.cpp in an isolated build directory. Build `llama-server`, `llama-bench` and the model inspection or quantization tools needed by the selected revision. Save the source revision, dependency versions, build flags, compiler version, binary hashes, `--version` output and relevant `--help` output. A system package can be a comparison candidate, but a pinned build is needed for reproducibility. Do not use unreviewed install scripts or a moving branch as the recorded release.

**Model worker** verifies provenance, downloads exactly selected weight files at a pinned Hugging Face revision, hashes them and inspects GGUF metadata and tensor names. It creates a manifest and checks the chat template, tokenizer, architecture, quantization, number of layers, vision requirements and actual MTP tensors. Do not download every quantization or use a generic model selector that silently chooses another file.

**Evaluation worker** implements the benchmark driver, result schema, fixture suite, quality scorer and report generator. Use synthetic responses and a mock HTTP server for CPU-only tests while the model is downloading and the runtime is building. Do not start a GPU server until the lead grants the GPU resource lease.

During this wave, the lead prepares a task-local launcher, profile validation, a user service template, installation staging and rollback support. These must use the workers' frozen interfaces rather than modifying worker-owned files.

The runtime worker can use this Vulkan build template after the source checkout has been pinned. Its working directory is the resolved `TASK_ROOT/runtime/src/llama.cpp`. `BUILD_JOBS` must already contain the lead's approved positive concurrency limit. These commands build only in the task directory.

```bash
cmake -S . -B ../../build-vulkan -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DGGML_VULKAN=ON
cmake --build ../../build-vulkan \
  --target llama-cli llama-server llama-bench llama-quantize \
  --parallel "$BUILD_JOBS"
../../build-vulkan/bin/llama-server --version
../../build-vulkan/bin/llama-server --list-devices
```

Success means all selected targets build and device enumeration includes the intended RX 6600. Check target and flag availability against the pinned revision first. Stop if compilation fails or the target GPU is absent. Do not substitute a CPU-only binary.

### phase 2, establish one working baseline

After worker artifacts pass their local checks, the lead reviews their diffs and reports. The lead or one explicitly designated benchmark operator owns all GPU work from this phase onward.

1. Validate pinned files and the selected binary before launching. Resolve the intended GPU explicitly from the recorded device identity. Refuse an unexpected architecture or model hash.
2. Launch a foreground, task-owned server on loopback using the baseline profile below. Wait for readiness with a bounded timeout and retain startup logs.
3. Confirm all transformer layers and the output layer are offloaded as expected. Check the backend log for CPU fallback in the main model evaluation. Tokenization, sampling, orchestration, host buffers and a mapped model file can legitimately use CPU or system RAM. They do not prove layer offloading failed.
4. Record model, compute and cache buffer allocation, GPU memory use and sustained behavior. A successful load or an offload count alone does not prove absence of driver memory eviction. Check throughput and observable residency indicators under generation.
5. Run one short chat, a constrained JSON response and a longer completion. Check readable output, complete streaming, correct stop behavior and reuse for a second request. Confirm no image projector was loaded for this text-only service.
6. Preserve the verified baseline as an immutable reference before tuning. It remains available if any experimental backend or model fails.

If the baseline does not fit, first investigate desktop VRAM use and allocations without closing applications. Reduce physical prompt batch size or context, or test a supported compressed attention cache. Do not silently offload layers, shorten the advertised context or switch to a different model. If full residency remains impossible, report that the objective is blocked under the current constraints.

### phase 3, measure and tune serially

Use the staged experiment sequence under tests. Keep the runtime revision, checkpoint, prompt corpus, sampler and actual prompt lengths fixed when isolating a setting. Test only one resident inference server at a time. CPU-only report analysis may run in parallel if it does not distort the measured workload.

The first search covers Vulkan Flash Attention, cache precision and prompt batching. The second search covers MTP when the selected artifact actually supports it. The third covers a HIP build when feasible and a small number of quantization alternatives. Recheck finalists in interleaved order to reduce temperature and background-load bias.

Do not interpret faster prompt ingestion as faster generation. Do not count rejected draft tokens as generated tokens. Do not reduce reasoning effort or disable thinking and present that as a runtime speedup. If a low-latency non-thinking profile is useful, label it as a different behavior profile and evaluate it separately.

### phase 4, integrate and review

The lead selects a winner only after the quality, residency, reliability and measurement gates pass. Freeze its binary, model, configuration and benchmark report as one release. Keep the baseline and comparison results, including failed or inconclusive experiments.

Use an independent reviewer after implementation ownership has ended. The reviewer checks different concerns from the implementers, including unsupported performance claims, benchmark fairness, accidental public binding, silent CPU fallback, mutable downloads, incorrect process cleanup, memory headroom and rollback behavior. Findings must name evidence and a concrete reproduction. Allow at most two remediation rounds per track, then report a remaining blocker rather than cycling indefinitely.

### phase 5, install and hand off

Prepare a dry-run installation manifest showing every destination, whether it exists, ownership and how it is restored. Use task-specific names such as `qwen-local` and `qwen-local.service`. Do not overwrite an unrelated launcher or service with that name.

Recommended final locations use the operator's XDG directories, resolved at runtime.

| Artifact | Suggested location |
| --- | --- |
| Versioned binaries, profiles and manifests | `${XDG_DATA_HOME:-$HOME/.local/share}/qwen-local/releases/<release-id>/` |
| Model downloads | `${XDG_DATA_HOME:-$HOME/.local/share}/qwen-local/models/` |
| Private logs and benchmark data | `${XDG_STATE_HOME:-$HOME/.local/state}/qwen-local/` |
| User preferences | `${XDG_CONFIG_HOME:-$HOME/.config}/qwen-local/` |
| Runtime lease and transient state | `${XDG_RUNTIME_DIR}/qwen-local/` |
| Optional user service | `${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/qwen-local.service` |

Install verified release files before switching the current release pointer. Keep the previous release. Retain local-only profiles and machine-specific paths outside tracked source. Configure the launcher with argument arrays, not shell evaluation of configuration strings. Propagate exit status and signals correctly.

Bind only to `127.0.0.1` by default. Verify the actual socket after launch. Keep remote hosting, reverse proxies, authentication design and firewall changes outside this local-service scope. Do not download or build anything during service startup. Use a modest restart limit rather than an endless crash loop. Do not enable lingering or change session targets.

Verify the unit with `systemd-analyze --user verify` against the staged unit and check the exact command on the pinned host version. Prepare start, stop, status and rollback commands with the actor and concrete working directory. Activation and autostart must honor the operator's execution request and any pending host approval. Leave autostart disabled unless requested.

Rollback stops only the task-owned instance, restores the previous release pointer and previous task-owned service configuration, then starts the previous service only if that action is authorized. Record the result and readiness check. On first installation, rollback removes or disables only newly installed task-owned artifacts and retains model files unless deletion was separately requested. Never uninstall shared packages or roll back the graphics stack as part of this task.

## usage

### instruction to the implementation agent

Execute this plan on the real host. Begin with inspection and a short statement of the discovered hardware and any material deviation. Use multiple parallel agents with exclusive file ownership. Complete the implementation and measurements that are authorized. Ask only for a decision or action that materially changes correctness, scope or required approval. Do not claim the benchmark has run if only scripts were prepared.

The service is for text chat and API use. It does not automatically grant model-generated tool calls permission to execute shell commands or alter the host. Tool-call validation in the acceptance suite uses inert mock tools.

### required handoff artifacts

- A working local API and its exact model identity, context limit and thinking behavior.
- A pinned release manifest, model provenance, file hashes and complete effective settings.
- The baseline and selected performance profiles, with a reason for the choice.
- Raw measurement records, a compact comparison table and known limitations.
- Readiness, cancellation, residency, quality and soak-test results.
- Exact start, stop, status, rebuild, retest and rollback commands for the real host.
- The package changes and installation manifest, including anything deliberately left unactivated.

For every operator command, state the actor, resolved working directory, complete commands in order, expected success result and any relevant stop condition. Do not leave the operator to infer paths from this planning clone.

## settings

### baseline profile

These values are an initial experiment, not a performance promise. Validate flag support from the pinned binary. Keep the model's supplied chat template and use the model author's sampling settings as the starting point, recording any change.

| Setting | Baseline | Purpose |
| --- | --- | --- |
| Model | HauhauCS Qwen3.5-9B aggressive | Starting low-refusal checkpoint |
| Weight format | `Q4_K_M` GGUF | Leave room for working memory on 8GB |
| Backend | Vulkan with Mesa RADV | Initial compatible GPU path |
| GPU | Explicitly selected RX 6600 | Avoid accidental integrated-GPU selection |
| GPU layers | All, commonly `-ngl 99` | No partial CPU layer offload |
| Automatic fitting | `--fit off` when supported | Fail visibly instead of changing tested settings |
| Context | `-c 4096` | Initial bounded memory requirement |
| Parallel slots | `--parallel 1` | One active conversation |
| Logical prompt batch | `-b 512` | Initial prompt-processing batch |
| Physical prompt batch | `-ub 128` | Conservative compute-buffer allocation |
| Flash Attention | `--flash-attn auto` | Establish baseline before on/off comparison |
| Attention cache | `f16` K and V | Reference precision for cache comparisons |
| Template handling | `--jinja` when supported | Preserve model formatting and inert tool-call tests |
| Vision | No projector loaded | Text-only memory budget |
| Speculation | Disabled initially | Establish an ordinary decoding reference |
| Listener | `127.0.0.1`, chosen free port | Local access only |

A fully resident model still needs CPU work and host memory. Do not set a zero-CPU acceptance requirement. Likewise, memory mapping and `mlock` are not automatic generation-speed improvements once weights are resident on the GPU. Benchmark only changes with a plausible bottleneck.

### model selection and provenance

The default file is `Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf` from the publisher's repository. Confirm the filename, exact byte count and revision at execution time. The prior file listing showed about 5.63GB, while prose on the model card used a different rounded size.

The publisher reports 0 refusals in 465 prompts. A separate community evaluation reports zero in 400 for several 9B variants, and also reports capability losses. These are evidence to investigate, not guaranteed properties of the selected Q4 artifact. Do not repeat the publisher's claims of universal compliance or zero capability loss as established facts. Hugging Face hosting and download counts are not an audit.

Record the source model, license, publisher, immutable revision, exact selected file, SHA-256, tensor metadata and any transformation. Review metadata and templates before execution. Use GGUF data directly with the selected runtime. Do not execute model-repository scripts, enable arbitrary remote code or install publisher-provided wrappers just to load weights.

Inspect the tensor inventory for a valid next-token prediction head before planning MTP. A model card listing MTP as an architectural feature does not establish that its downloadable GGUF retains that head. Check the pinned runtime's converter and architecture implementation for expected tensor names and dimensions. A server flag being accepted is insufficient proof that MTP is active.

If the primary model lacks its prediction head, retain it as the baseline. Do not graft a head from an unrelated checkpoint and assume its behavior is preserved. Compare a separately identified model that retains MTP only through the model quality gate.

The optional community Qwen3.8 candidate is `petruhonk/Qwen3.8-9B-Distill-uncensored-heretic-GGUF`. Its card reports 6 refusals in 100 prompts and retained MTP. The inspected repository supplied F16 and Q8 files, with Q8 larger than this card's VRAM. For a fair 8GB candidate, quantize from the pinned F16 artifact or original high-precision safetensors using the pinned converter. Preserve and verify MTP. Do not requantize Q8 when the high-precision source is available. Record calibration data if an importance matrix is used. Validate the produced file and rerun the local quality and refusal suite. Do not claim that this distillation inherits official Qwen3.8-27B or Qwen3.5-9B benchmark scores.

Keep this alternative optional until the baseline works. Use it if the primary artifact fails quality checks or if MTP offers a plausible measured improvement. Compare a documented Qwen3.5-9B Heretic variant as a control only when a specific quality or provenance question remains. Avoid downloading a large collection of similarly named variants.

The documented Heretic control is `trohrbaugh/Qwen3.5-9B-heretic-v2`, the exact variant used in the cited community comparison. Its card publishes ablation parameters and reports 6 refusals in 100 prompts. Prepare or verify its GGUF conversion separately if needed. Results from another Heretic run are not interchangeable. The community comparison used BF16, a specific classifier and manual judgment for some cases. It is useful evidence, not an independent audit of our installed Q4 file.

### runtime alternatives

Native llama.cpp is already direct hosting. A container or frontend is unlikely to determine generation speed when it uses the identical backend, model and settings, but do not publish a percentage without measuring it. Use the native server and its built-in UI initially to keep the implementation small.

The first backend comparison is Vulkan versus HIP in the same llama.cpp revision. The RX 6600 uses `gfx1032`. Official support and workarounds change over time. Investigate the exact installed HIP libraries and target support. If an architecture override is required, scope it only to the task process and record it in the candidate manifest. Never export it globally. A successful build is not proof of numerical correctness or supported kernel coverage.

Consider another runtime or an experimental fork only after confirming support for this exact GPU, Qwen's hybrid architecture, the selected quantization and the required cache or speculation modes. Require an inspectable source revision and a small correctness test before a full benchmark. Results from NVIDIA cards, newer Radeon cards, Strix Halo, large batches or different models do not prove an improvement here.

Do not make unsupported vLLM, CUDA, TensorRT or specialized quantization installations a prerequisite. Do not spend days porting a runtime as an implicit extension of this task. If a candidate needs substantial new implementation, report that separate proposal and finish the verified path.

## requirements

The real host must have a working arch linux userspace, the target RX 6600, access to the render device, sufficient host RAM and disk, allowed access to the selected source and model repositories, and permission for any missing dependencies. Detect rather than assume each requirement.

Maintain a configurable VRAM margin for the desktop. Start with a target of at least 768MiB free under sustained inference, increasing it if the observed desktop varies more. This margin is an engineering starting point, not an upstream requirement. Do not reduce it just to make a benchmark win. Use a documented smaller margin only after operator acceptance and a successful stability test.

Freeze a telemetry method before GPU tests. Map the target PCI address to the matching device under `/sys/class/drm/` and read its `mem_info_vram_total` and `mem_info_vram_used` byte counters. Sample before loading, during warm-up and at 100ms intervals throughout measured runs and the soak. Compute sampled free VRAM from total minus used. Record monotonic timestamps, missed samples and the device mapping. Read `mem_info_gtt_used` and available busy, temperature and throttling counters as supporting observations, not as independent proof of CPU offload.

The required placement evidence combines runtime buffer allocation logs, all-layer offload, complete device telemetry and stable repeated generation at matched context occupancy. Add per-client DRM residency or migration counters if available for the owned server. Report that global counters and sampled peaks cannot prove zero transient migration between samples. If finer residency evidence is unavailable, use the explicit label full layer offload with measured memory headroom and a passed stability proxy, rather than claiming driver eviction is impossible. If primary VRAM telemetry is unavailable or has gaps longer than 1s during a measured run, the memory-margin gate is unverified and that run cannot certify deployment. Do not change device permissions to obtain telemetry.

Use separate staging and release directories. Keep weight files, binaries, raw prompts, completions, machine inventories and local configuration out of a public dotfiles repository. If reusable scripts or documentation are added to a whitelist-based repository, add only their explicit ignore exceptions and follow that repository's documentation and commit rules.

Do not run GPU benchmarks concurrently with other task-owned model tests. A cooperative lock protects the task's processes, not every program on the machine. Record background GPU activity and invalidate contaminated measurements. Wait or report contention rather than taking control of another session.

## troubleshooting

| Symptom | Required investigation and response |
| --- | --- |
| Unknown model architecture | Check pinned runtime support, GGUF metadata and conversion revision |
| Allocation failure | Inspect actual VRAM and buffers, reduce physical batch or context, test supported cache compression |
| Unexpectedly low speed | Confirm GPU identity, full offload, memory residency, context length and background load |
| HIP kernel or target error | Check compiled target and library coverage, preserve Vulkan fallback, stop repeated override guessing |
| MTP ignored or rejected | Inspect tensor inventory and runtime feature support, verify actual draft counters |
| MTP slower than baseline | Check acceptance, verification cost, cache use and prompt family, retain ordinary decoding |
| Corrupt output or repetition | Compare baseline with identical inputs, inspect template, cache and backend correctness |
| More refusals after conversion | Recheck checkpoint, template, thinking mode, precision and evaluator before tuning prompts |
| Device reset or desktop instability | Stop task-owned load, preserve logs, restore prior task profile, report before retrying |
| Port already occupied | Select a free loopback port, never terminate the unknown listener |
| Permission or guard denial | Preserve the pending action and its full reason, never retry through a different tool |

Use provider-owned process or task handles to stop work. Do not use a numeric PID or matching username as proof of ownership. Once a uniquely named task service owns a process, use that service's exact lifecycle operations subject to host rules. Do not use broad process-name termination.

## tests

### measurement contract

Use the server's own token counters and timings together with a streaming client. Store the exact meaning of every metric. Record at least the following for each run.

- Model hash, quantization, runtime revision and binary hash.
- Complete effective arguments, environment overrides and selected GPU identity.
- Prompt fixture hash, actual tokenized prompt length, context capacity and completion budget.
- Sampler, seed when supported, thinking mode and token counting method.
- Cold-load time, warm time to first streamed token and time to first user-visible answer token when distinguishable.
- Prompt processing speed, accepted output generation speed and total request latency.
- Reasoning tokens and visible answer tokens separately when observable. If unavailable, mark them unavailable rather than estimating silently.
- Peak process memory, sampled VRAM use and free VRAM, background GPU load and available thermal or throttling observations.
- Draft count, accepted draft count, acceptance rate and verification cost for MTP when exposed.
- Completion status, stop reason, truncation, correctness result and any runtime warnings.

Do not equate a server's reported token rate with client-visible delivery speed without naming the difference. Use accepted final output tokens for speculative throughput. Separate startup and first-use shader compilation from warm measurements. Keep the user interface and network path identical across performance candidates.

Control prompt-prefix caching explicitly. Use equivalent fresh request state or a supported cache reset for the principal prompt-processing comparison. Otherwise repeated prompts can appear faster because their prefix was reused. Measure realistic warm-prefix reuse separately and label it. Record the actual evaluated prompt-token count rather than assuming every submitted token was recomputed.

Pin the performance sampler, while separately evaluating the author's recommended conversational sampler. For initial thinking-mode quality tests, the primary card recommends temperature 0.6, top-p 0.95, top-k 20 and min-p 0. Verify the active template and current card before use. Give quality tasks enough generation budget to finish, record truncation as its own outcome and do not score an unfinished reasoning trace as a completed answer.

### staged benchmark matrix

Use a small deterministic prompt corpus spanning code completion, technical explanation and ordinary prose. Use synthetic or licensed public content. Do not benchmark against private documents or the user's repositories unless explicitly supplied for that purpose.

1. Establish the baseline with warm-up followed by three measured repetitions on short and moderate prompts, targeting about 256 and 2048 actual input tokens. Use a 256-token output budget. Record early stop separately and exclude it from fixed-length throughput comparisons.
2. Screen Flash Attention on and off against the baseline. Test cache precision `f16` and supported `q8_0` on finalists. Test `q4_0` cache only when memory pressure justifies the additional quality check. Qwen's recurrent state is separate from the attention KV cache, so do not assume these flags compress every state buffer.
3. Sweep physical prompt batches such as 128, 256 and 512 with logical batches at least as large. Keep only configurations that improve the relevant metric without violating residency or stability. These primarily affect prompt ingestion and speculative verification, not a guaranteed ordinary decode speedup.
4. If verified MTP weights are available, compare speculation off and draft lengths 1, 2 and 3 with the exact same artifact. Measure acceptance and output quality on each prompt family. Include total request latency and memory, not just generation speed. Test actual HTTP inference because a microbenchmark may not exercise server speculation.
5. Run the strongest Vulkan profile and feasible HIP candidates against the same fixtures and effective settings. Use comparable builds from the same revision. Check correctness before trusting a backend speedup.
6. Compare weight formats only after the backend is understood. Start with `Q4_K_M`. Test a simpler or smaller supported format if it plausibly improves the active kernels and passes quality. Test Q5 only if it fits with margin and quality warrants the cost. Generate alternative formats from the same high-precision checkpoint, with matched calibration where applicable.
7. Confirm finalists with at least seven measured repetitions per prompt family, interleaving baseline and candidate. Report medians, variation and a confidence interval for paired changes using a documented method. Add a prompt near the declared context limit while leaving room for completion and template tokens. Test 8192 context only if the 4096 profile passes and there is enough memory for the actual longer prompt.
8. Run a 30-minute sequential-request soak on the winner at realistic context occupancy. Include cancellation and recovery, repeated requests and a fresh startup. Do not leave an unowned benchmark running after the task ends.

Use `llama-bench` as a kernel-level diagnostic and record its revision-specific supported flags. Use the HTTP harness for the final service decision. Do not run the Cartesian product of every flag. Eliminate invalid and clearly inferior candidates early, changing one factor at a time before confirming interacting settings on the finalists.

Keep the initial screen to about 20 distinct configurations and carry at most three finalists into the full suite. This is a planning budget, not a reason to skip a required gate. Extend it only when measurements identify a concrete unresolved bottleneck, and record why. Save each completed run and a stage marker. Resume only when artifact hashes and settings still match, otherwise start a new run ID. Finish once the declared matrix and acceptance gates are complete instead of continuing speculative tuning.

### quality and refusal evaluation

Freeze a small suite before looking at candidate results. Include at least 40 benign tasks covering executable coding checks, instruction following, structured output, short math or factual questions, long-input retrieval and inert tool-call formatting. Prefer deterministic expected outputs and tests. Record manual scoring rules for open-ended answers before scoring.

Run generated code only after a tested isolation mechanism exists. The evaluation worker should use an existing approved sandbox, or prepare a minimal bubblewrap profile if its dependency is authorized. Require an isolated network namespace, an empty credential environment, a read-only allowlist of runtime files, an isolated process namespace, no user home or desktop sockets, no GPU devices, a disposable writable work directory, wall-clock timeout, process and memory limits, and cleanup through the owned task handle. A working directory alone is not a sandbox. Preflight fixtures must demonstrate denied access to a harmless host sentinel outside the sandbox, denied network access, denied host writes and termination of an over-time task. If isolation is unavailable or any preflight fails, do not execute generated code. Use static or known-output checks, record executable-code capability as unverified and do not claim that gate passed.

Name the critical fixtures in the frozen suite before evaluation. Include required structured-output validity, correct retrieval of a supplied fact, valid inert tool-call arguments, termination and basic instruction adherence. Both the baseline and winner must pass every critical fixture and at least 36 of the 40 benign tasks, or the same 90% floor for a larger suite. This is a local usefulness floor, not a general benchmark claim. A baseline below the floor triggers investigation or a checkpoint comparison, not a relaxed threshold after seeing results.

Compare runtime changes on the exact same model. Compare checkpoint or quantization changes against both the selected baseline and an official same-size model when affordable. If an official control cannot be evaluated, disclose that capability preservation relative to the original remains unmeasured. Avoid assertions based on incompatible public benchmark settings.

Use a separate, versioned refusal suite covering benign controversial discussion, legitimate technical questions, creative writing and clearly scoped requests that ordinary models sometimes refuse unnecessarily. For prohibited-content refusal rates, use only an appropriate existing evaluation harness and policy-permitted procedure. Do not generate or publish harmful instructions merely to reproduce a marketing claim. If a permitted adversarial evaluation cannot run, explicitly leave that claim unverified.

Distinguish explicit refusal, evasive answer, helpful substantive answer, truncation and incoherent output. A missing refusal phrase is not proof of compliance or useful content. Report sample size, prompt categories, thinking mode, generation limit, scoring method and uncertainty. Keep raw evaluation material private and include only safe examples in the shareable report.

A zero result should be written as zero refusals in the tested set. Do not extrapolate it to every possible prompt. Re-evaluate the actual installed quantization and template, not just its high-precision ancestor. An MTP comparison must retain the same sampling semantics where the implementation claims equivalence and must include behavioral checks rather than assuming bitwise output identity.

### acceptance gates

These thresholds are proposed engineering rules for this installation. Record any justified change before the final comparison.

| Gate | Passing result |
| --- | --- |
| Identity | Pinned model and binary hashes, expected architecture and device |
| Residency | All intended model layers on RX 6600, no hidden layer fallback, defined telemetry and stability proxy pass, configured sampled VRAM margin maintained |
| Local service | Readiness succeeds, loopback-only listener verified, streaming and non-streaming requests work |
| Context | Declared context usable with actual long input and completion, overflow gives a controlled response |
| Reliability | No crash, GPU reset, corrupted output or unexplained memory growth during the soak |
| Lifecycle | At least 30 sequential requests and 10 cancellation cycles succeed, graceful stop and restart work |
| Quality | All named critical fixtures pass, at least 90% absolute benign-task pass rate, no more than 2 additional failures per 40 tasks relative to baseline |
| Refusal behavior | No unexplained new refusal in the fixed benign suite, adversarial claims labeled by actual evidence |
| Performance promotion | A tuned candidate improves median generation by at least 5% across the selected workload, with paired uncertainty excluding no improvement |
| Latency | No more than 10% regression in median time to first token without an explicitly recorded tradeoff |
| Reproducibility | Winner can be recreated from pinned manifests and gives comparable repeated results |
| Recovery | Previous release or first-install rollback procedure validated without touching unrelated services |

The small quality suite detects regressions and does not certify general capability. When a performance difference is smaller than the noise or the 5% practical threshold, prefer the simpler, supported configuration. The verified baseline can be the final winner if no candidate establishes a qualifying improvement. Report per-workload results and any tradeoff rather than hiding losses in an average. A faster configuration that fails a hard gate is not the winner.

Exercise malformed requests, unavailable models and excessive context or output limits through bounded errors, then send a valid request. Test client disconnect as well as explicit cancellation. Readiness must distinguish loading from ready. Avoid inducing GPU OOM or device resets on the shared desktop as a fault-injection technique. Use mocked failures for destructive cases. By default, service logs must omit prompt and completion bodies.

### repository and artifact validation

Workers run focused tests for their owned files. The lead runs the complete relevant test suite after final integration, plus applicable lint, formatting, type checks and service validation. Do not run unrelated system or repository suites. If validation changes code, rerun the affected final gate.

The frozen interface requires these commands from `TASK_ROOT` after implementation. The tools are deliverables to create, not commands assumed to exist now.

```bash
python3 -m unittest discover -s tests
python3 tools/verify.py --manifest manifests/release.json --offline
python3 bench/run.py --profile profiles/baseline.json --suite bench/suites/smoke.json
python3 bench/run.py --profile profiles/winner.json --suite bench/suites/acceptance.json
python3 bench/report.py --runs results --output docs/benchmark-report.md
python3 tools/install.py --manifest manifests/install.json --dry-run
```

The actor is the implementation agent. The lead must record the resolved `TASK_ROOT` and exact commands in its final report. Expected results are passing CPU tests, verified local artifacts without network access, successful runtime gates, a report linked to raw run IDs, and an installation preview with no mutation. Stop dependent work when these checks fail. The benchmark runner must launch and clean up only its own server instances through the agreed resource lease and task handles.

## architecture

### service path

```text
local client
    -> loopback llama-server
    -> pinned Vulkan or validated HIP backend
    -> RX 6600
    -> pinned model weights and GPU working state
```

Use a native process initially. The launcher resolves a versioned profile and invokes the selected binary directly. The optional user service invokes the same launcher. There is one implementation of model selection and runtime settings, avoiding divergence between a benchmark command and the installed service.

### source ownership and parallel agents

The lead is responsible for planning, frozen interfaces, integration and the final decision. In a Codex environment with the installed profiles, use `orchestration_explorer` for read-only discovery, `orchestration_worker` for bounded implementation and `orchestration_reviewer` for substantive review. Follow the installed orchestration skill's model routing. If those profiles are unavailable, use the host's closest supported roles and disclose the fallback. Never silently inherit an expensive lead model for every worker. Reserve a lead slot and respect the actual concurrency limit.

| Actor | Exclusive write ownership under `TASK_ROOT` | Forbidden writes |
| --- | --- | --- |
| Runtime worker | `runtime/`, its isolated build directories and runtime tests | Model files, benchmark implementation, final profiles and service |
| Model worker | `models/` metadata and acquisition scripts, its model tests | Runtime source, benchmark scoring, final profiles and service |
| Evaluation worker | `bench/`, benchmark tests and result schema tests | Runtime and model artifacts, final profiles, service and installations |
| Lead | `schemas/`, `manifests/`, `profiles/`, `tools/`, `service/`, `docs/` and integration tests | Active worker-owned files before handback |
| Independent reviewer | Read-only review and a private findings report | All implementation files |

Assign test files by prefix within `tests/`, such as `test_runtime_*`, `test_models_*`, `test_bench_*` and `test_integration_*`. Freeze any shared test support before workers start or give it sole lead ownership. Only the lead runs package transactions, approves candidate execution order, writes the release manifest or changes installed artifacts.

The benchmark operator has exclusive write access to raw `results/<run-id>/` during each run. Analysis workers may read only completed runs. Download workers own distinct temporary files and use atomic rename after verification. Build workers use separate build trees and bounded resources. No worker writes another worker's mutable state.

### frozen interfaces

Create and freeze schema version 1 before dispatch. Keep these interfaces small and use JSON plus python standard-library code unless a verified requirement justifies a dependency.

| Contract | Required fields or behavior |
| --- | --- |
| Runtime candidate | ID, source URL and revision, build flags, binary path and hash, backend, supported features, captured help path |
| Model manifest | ID, source repository and revision, filename, byte count, hash, architecture, quantization, tokenizer and template identity, verified MTP status |
| Run profile | Runtime and model IDs, device identity, argument array, environment map, context, slots, sampler, memory margin and thinking mode |
| Run result | Schema version, run ID, complete effective profile, fixture hash, timestamps, counters, timings, memory observations, validity and failure reason |
| Release manifest | Selected immutable artifacts, winner profile, baseline profile, verification results, linked run IDs and installation version |
| Installation manifest | Exact source and destination, existing-file check, ownership, hash, backup or rollback action |

Use paths relative to the task or release root in shareable manifests. Resolve private machine-specific paths at runtime. Reject unsupported keys, malformed numbers, missing files and inconsistent feature requests before starting a process. Treat MTP availability as verified, absent or unknown, not a default true value.

The runner owns process creation, readiness timeout, cancellation, cleanup and a cooperative GPU lease. It must not infer ownership from a PID alone. The launcher must not download dependencies, change devices, fall back to CPU layers or rewrite its profile after a validation failure.

### worker brief template

Every dispatch must include the resolved task root, instructions to read, owned and forbidden paths, verbatim frozen interfaces, deliberate design choices, acceptance commands and passing criteria. Include this text in every implementation brief.

```text
You are not alone in the codebase. Preserve other agents' and the user's edits.
Write only your assigned files and adapt to frozen cross-track interfaces.
Do not commit, publish, install dependencies, alter the desktop or start GPU work
without the lead's resource assignment and any required host approval.
Use focused tests for your ownership and report exact commands and results.
Allow one behavioral fix attempt and up to three genuinely different build or
lint fixes. Escalate specification conflicts immediately. Do not repeat a failed
approach without new evidence. Do not spawn additional agents without the lead's
capacity and ownership assignment.

STATUS: complete | blocked | deviated
FILES TOUCHED: exact list
VERIFICATION: commands, results and pass or fail against the acceptance bar
DEVIATIONS: differences from the brief and reasons
CONCERNS: relevant findings left unchanged
```

The lead reviews exact diffs and evidence rather than accepting a completion label. Resume an existing worker after a transient interruption instead of recreating its work. Progress updates should state measured findings, important failures and changed assumptions. Completion means implemented artifacts and passing relevant validation, or an exact documented blocker with all independent work completed.

## docs

Recheck moving upstream documentation at implementation time and capture the relevant revision. Sources below support discovery and candidate selection. They do not substitute for local measurements.

- [llama.cpp source and supported backends](https://github.com/ggml-org/llama.cpp)
- [llama.cpp build instructions](https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md)
- [llama.cpp server flags and API](https://github.com/ggml-org/llama.cpp/tree/master/tools/server)
- [llama-bench semantics](https://github.com/ggml-org/llama.cpp/blob/master/tools/llama-bench/README.md)
- [llama.cpp MTP implementation discussion](https://github.com/ggml-org/llama.cpp/pull/22673)
- [arch Vulkan driver package](https://archlinux.org/packages/extra/x86_64/vulkan-radeon/)
- [amdgpu memory telemetry](https://docs.kernel.org/gpu/amdgpu/driver-misc.html)
- [bubblewrap sandbox primitives and limitations](https://github.com/containers/bubblewrap)
- [official Qwen3.5-9B model](https://huggingface.co/Qwen/Qwen3.5-9B)
- [primary aggressive 9B model](https://huggingface.co/HauhauCS/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive)
- [primary model files](https://huggingface.co/HauhauCS/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive/tree/main)
- [community Qwen3.8 distillation with retained MTP](https://huggingface.co/petruhonk/Qwen3.8-9B-Distill-uncensored-heretic-GGUF)
- [community distillation files](https://huggingface.co/petruhonk/Qwen3.8-9B-Distill-uncensored-heretic-GGUF/tree/main)
- [documented Heretic control](https://huggingface.co/trohrbaugh/Qwen3.5-9B-heretic-v2)
- [Heretic project](https://github.com/p-e-w/heretic)
- [community comparison and its methodology](https://abliterlitics.dev/models/qwen3.5-9b/)
- [vLLM hardware requirements](https://docs.vllm.ai/en/latest/getting_started/installation/gpu/)
