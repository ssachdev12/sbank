# sbank codebase-readiness — handoff document (WP8)

This is the single document a future planning session should read first. It consolidates
WP1–WP8: what was actually built and independently verified in this environment, and what
is still unverified or open. Where a claim is unverified, it is labeled **UNVERIFIED**
below — do not treat those as done.

Read this alongside `.claude-wp/WP*_report.md` (implementation reports) and
`.claude-wp/WP*_review.md` (independent adversarial reviews, where they exist) for full
detail; this document is the summary/index, not a replacement for them.

---

## 1. Branch-stack map

All work happened in this checkout (`/Users/surabhi.sachdev/Documents/work/projects/yinglei/src/sbank`).
**`master` was never touched by any WP** (verified: `git rev-parse master` is `e13f6ac`
before and after every WP) and **still carries the pre-existing smoke-test bug found in
WP1**: `bin/sbank_sim` crashes with a `ValueError` on `cvs_entry_time` formatting under
the installed `python-ligo-lw==1.8.3` (`.claude-wp/WP1_report.md`, "Two bugs the smoke
test found and fixed along the way" / "`master`: FAIL"). This is a real, reproduced defect
on `master`, independent of anything any WP did; the production cluster's
`python-ligo-lw` version may differ (untested here), but do not assume `master` runs
`bin/sbank_sim` successfully as-is.

Real commit topology (`git log --oneline --all`), oldest to newest — **not** always what
each report's own "Branch:" header line says (a few WPs committed onto a later branch
pointer than their own name; the DAG below is the ground truth read from git, not from
report prose):

```
master (e13f6ac, untouched)
  │
  ├─ sync-upstream (WP1: fork-forensics + 3-way merge with upstream/master)
  │     124eca8  merge remote-tracking branch 'upstream/master' into sync-upstream
  │     6a92e44  bin/sbank_sim: capture register_process() return value  <- sync-upstream tip
  │
  ├─ feature/tidal (WP3: tidal waveform support)
  │     9c68256  Add tidal template support (WP3): TaylorF2Tidal + NRTidal classes,
  │              contact-frequency cutoff, lambda plumbing  <- feature/tidal tip
  │
  ├─ feature/eccentric (WP4: eccentric support + WP3 hardening;
  │                      WP5: Phenom-X precessing/HM + per-body tidal contact cutoff)
  │     1406654  Add eccentric template support (WP4) + WP3 hardening
  │     be11622  Add Phenom-X precessing/HM injection classes + per-body tidal
  │              contact cutoff (WP5)  <- feature/eccentric tip
  │              (WP5 was committed directly on the feature/eccentric ref, per the
  │              WP5 spec "continue on feature/eccentric"; verified:
  │              `git rev-parse feature/eccentric` = be11622.)
  │
  ├─ feature/bank-ingestion (WP6: Roche-overflow default cutoff + PyCBC/MBTA ingestion)
  │     fb05169  Roche-overflow default tidal cutoff + multi-bank ingestion (WP6)
  │              <- feature/bank-ingestion tip
  │
  └─ feature/igwn-dag (WP7: DAG generator + campaign configs + container;
                        WP8: preamble fixes + smokes + this document, CURRENT BRANCH)
        5962d01  Add IGWN-pool DAG readiness, campaign config generator, and
                 Apptainer container (WP7)
        1a68f2f  Per-bank flow/casing config fixes, integration smokes, READINESS
                 handoff (WP8)  <- feature/igwn-dag tip
```

**Recommended merge order into `master` (or a new integration branch)**: exactly the
order above — `sync-upstream` → `feature/tidal` → `feature/eccentric` (which already
contains `sync-upstream`+`feature/tidal` in its history, so this is a fast-forward-style
stack, not independent branches to cherry-pick) → the WP5 commit (`be11622`, already an
ancestor of `feature/bank-ingestion`) → `feature/bank-ingestion` → `feature/igwn-dag`.
Because each branch is built directly on top of the previous one (confirmed via
`git log --oneline <branch>`, not just report claims), merging `feature/igwn-dag` into
`master` in one shot brings in the entire stack in the right order; there is no
diverged/conflicting side branch to reconcile. **Do not** merge any of the earlier
branches independently after `feature/igwn-dag` — they are strict ancestors, so it is a
no-op, but doing it in the wrong order first could create spurious conflicts.

### One-line summary per WP

| WP | Branch tip (sha) | Verdict | Summary |
|---|---|---|---|
| WP1 | `sync-upstream` @ `6a92e44` | (forensics + merge, no adversarial review) | 3-way fork/upstream merge; fixed the upstream `register_process()` `NameError`; found and documented (not fixed) `master`'s pre-existing `cvs_entry_time` crash. |
| WP2 | (memo only, no code) | (advisory memo, no review) | Approximant availability/recommendation survey; basis for WP3–WP5's model choices and this document's capability matrix. |
| WP3 | `feature/tidal` @ `9c68256` | **APPROVE** | `TaylorF2Tidal`, `IMRPhenomD_NRTidalv2`, `IMRPhenomXAS_NRTidalv3`; C-Love contact-frequency cutoff (pre-WP6 default). |
| WP4 | `1406654` (on `feature/eccentric`) | **APPROVE** | `TaylorF2Ecc`, `TaylorF2EccTidal`; conditional `SEOBNRv5EHM` (pyseobnr-gated); NRTidalv3 kappa2T fast-fail. |
| WP5 | `feature/eccentric` @ `be11622` (branch tip) | **APPROVE** | Injection-only `IMRPhenomXHM`/`IMRPhenomXPHM`/`IMRPhenomXO4a`/`IMRPhenomXP_NRTidalv2`; per-body tidal contact cutoff (S4) generalized in `TaylorF2TidalTemplate._get_f_final`. |
| WP6 | `feature/bank-ingestion` @ `fb05169` | **REQUEST-CHANGES → resolved** (see §2) | Roche-overflow `disruption` default tidal cutoff (**breaking change, see §2**); `bin/sbank_convert_bank` (strict PyCBC converter, honest MBTA stub). |
| WP7 | `feature/igwn-dag` @ `5962d01` | **APPROVE** | `bin/sbank_sim_dag_config` (dependency-free YAML→DAGMan generator, no `lalapps`/`glue.pipeline`); 9 `configs/*.yaml` campaign templates; `container/sbank-igwn.def` (not built, lint-checked only — see §5). |
| WP8 | `feature/igwn-dag` (this work, see `.claude-wp/WP8_report.md`) | (self-implemented, this document) | Per-bank `--flow`/`--fhigh-max` override + historical `SSM`/`ALL` casing fix (WP7 NB-1/NB-2); R7 self-documenting `tidal:` block (NB-4); one real `bin/sbank_sim` integration smoke per new capability (S1–S5); this document. |

WP6's review (`.claude-wp/WP6_review.md`) initially returned **REQUEST-CHANGES** for a
single blocking, documentation-only finding (B1: the reproducibility warning below was
missing from the report) — resolved by adding the warning; the underlying implementation
was independently verified correct on the first pass. WP1 and WP2 had no separate
adversarial-review pass (WP1 is forensics/merge with its own verified test case; WP2 is
an advisory memo, not a code change) — treat their "verified" status as self-reported plus
this document's own spot checks (§3), not independently reviewed.

---

## 2. ⚠ REPRODUCIBILITY WARNING — WP6 changed the default tidal cutoff

**Read this before rerunning any tidal campaign command line without an explicit
`--tidal-ffinal-mode`.**

WP6 changed the **default** `--tidal-ffinal-mode` from `contact` (WP3–WP5 behavior) to
`disruption` = `min(f_ISCO, f_contact, f_Roche)`. A pre-WP6 (or original paper-era) tidal
banksim command line, rerun today **without** an explicit `--tidal-ffinal-mode contact`,
now produces **silently different fitting factors** — not an error, just a different
number, because the template/injection termination frequency drops substantially
wherever Roche overflow binds:

| system | contact (pre-WP6 / current `--tidal-ffinal-mode contact`) | disruption (current default) |
|---|---:|---:|
| 0.5+0.5 M☉, Λ=1e6 | 376 Hz | 248 Hz |
| 4+0.2 M☉, Λ₂=1e6 | 1047 Hz | 596 Hz |

**To reproduce any pre-WP6 (or original paper-era) tidal run**, pass
`--tidal-ffinal-mode contact` explicitly (or `isco` for the earlier fiveo01-reference
behavior). This was a deliberate user decision (2026-07-15 gate, recorded in
`.claude-wp/WP6_report.md`): `disruption` is the physically defensible default for the
subsolar campaigns, and the FF difference between modes is itself a quotable
model-uncertainty band — but it is a **breaking change to the default**, and every WP7
campaign config (`configs/*.yaml`) that touches tidal runs sets `tidal.ffinal_mode`
**explicitly** for exactly this reason (`tidal_bns.yaml`, `tidal_subsolar.yaml`;
`r7_precess_nsbh.yaml` also now sets it explicitly for self-documentation, WP8 NB-4 —
see §6 of `.claude-wp/WP7_review.md`). If you hand-invoke `bin/sbank_sim` for a tidal
run outside the generator, you must set `--tidal-ffinal-mode` yourself.

---

## 3. Capability matrix — approximant × injection/template × availability

Legend: **local venv** = confirmed generating in `.venv-test` here; **igwn-py311** =
expected to work on IGWN's pinned pool env per WP2's same-minor-lalsimulation-series
argument, **UNVERIFIED** against a real `igwn-py311` install from this environment;
**container** = only reachable via `container/sbank-igwn.def` (see §5), because
`pyseobnr` is not shipped by the plain `igwn-py311` pool env. "Template" = usable for
bank placement; several classes are registered **injection-only** by design (their
docstrings say so explicitly) even though nothing mechanically prevents constructing
one as a template.

| approximant | injection | template (bank) | availability | WP | notes |
|---|:-:|:-:|---|---|---|
| `TaylorF2` | Y | Y | local venv, igwn-py311 | (pre-existing) | production baseline |
| `TaylorF2Tidal` | Y | Y | local venv, igwn-py311 | WP3 | WP6 disruption default — §2 |
| `TaylorF2Ecc` | Y | Y | local venv, igwn-py311 | WP4 | e≲0.1, O(e²), no mean anomaly dependence — §7 |
| `TaylorF2EccTidal` | Y | Y | local venv, igwn-py311 | WP4/WP6 | combined; same e-validity + Roche-cutoff caveats |
| `IMRPhenomD_NRTidalv2` | Y | Y | local venv, igwn-py311 | WP3 | BNS-scale Λ only (§7) |
| `IMRPhenomXAS_NRTidalv3` | Y | Y | local venv, igwn-py311 | WP3 | κ₂T guard, rejects Λ≳60,000 (§7) |
| `IMRPhenomXAS` | Y | Y | local venv, igwn-py311 | (pre-existing) | aligned-spin IMR, no HM |
| `IMRPhenomXHM` | Y | **injection-only** | local venv, igwn-py311 | WP5 | not intended for bank placement |
| `IMRPhenomXPHM` | Y | **injection-only** | local venv, igwn-py311 | WP5 | precessing + HM |
| `IMRPhenomXO4a` | Y | **injection-only** | local venv, igwn-py311 | WP5 | O4-tuned; **primary** precessing injection approximant per user decision (replaces the F4 sheet's `IMRPhenomXPHM`/`SEOBNRv5PHM` text — `SEOBNRv5PHM` is not available, see below) |
| `IMRPhenomXP_NRTidalv2` | Y | **injection-only** | local venv, igwn-py311 | WP5 | precessing + tidal (NSBH); **no κ₂T fast-fail** — only empty/non-finite backstops (§7) |
| `SEOBNRv5EHM` | Y | **injection-only** | local venv (pyseobnr 0.3.6 confirmed installed), **container** for cluster use | WP4 | TD-generated via gwsignal/pyseobnr; aligned-spin eccentric IMR; **not in default `igwn-py311`** |
| `SEOBNRv5PHM` | — | — | **not implemented** | — | absent from lalsimulation's enum *and* no pyseobnr precessing model is registered in `sbank/waveforms.py` (confirmed, WP2/WP7) |
| `SEOBNRv4EHM`, `IMRPhenomTEHM` | — | — | **not implemented** | — | absent from this lalsimulation's approximant enum (WP2, confirmed by round-trip `GetStringFromApproximant` check) |
| `EccentricFD`, `EccentricTD` | — | — | **not implemented in sbank** | — | available in lalsimulation per WP2's probe but not adopted (`TaylorF2Ecc`/`SEOBNRv5EHM` chosen instead); `EccentricTD` also rejects non-zero spin |
| `SEOBNRv4_ROM_NRTidalv2`, `SEOBNRv5_ROM_NRTidalv3`, `SEOBNRv4T_surrogate` | — | — | **not implemented in sbank**; would need `lalsimulation-data` | — | WP2 probe: `SEOBNRv5_ROM_NRTidalv3` also **crashes** at subsolar Λ (rc=-11) — explicitly rejected as a subsolar tidal option, not just unimplemented |

`bin/sbank_convert_bank` (WP6) additionally accepts a **PyCBC-schema HDF5 bank** as a
template-side input, mapped to a native sbank approximant via an explicit table
(`SPAtmplt`/`TaylorF2`→`TaylorF2`, `IMRPhenomD`→`IMRPhenomD`, `SEOBNRv4_ROM`→`SEOBNRv4_ROM`,
direct-name passthrough otherwise) — verified end-to-end in WP6's own test and again in
WP8's S5 smoke (§4). `--format mbta` is a **deliberate stub** (see §7) — no MBTA schema
was available to verify against, so none was invented.

---

## 4. Test index

All commands: `OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 ./.venv-test/bin/python <script>`
(some also want `MPLCONFIGDIR=/tmp/matplotlib-wpN` to avoid font-cache warnings polluting
stdout). None of `.claude-wp/` is git-tracked (`.git/info/exclude` excludes it, same as
`.venv-test/`) — these test files live only in this working tree; carry them along
explicitly if this branch is exported/rebased elsewhere.

| file | pins | run |
|---|---|---|
| `.claude-wp/tests/WP1_smoke.py` (+ `WP1_run.sh`) | single-bank `bin/sbank_sim` smoke: builds a small TaylorF2 bank + 20 injections directly, asserts the `01_consolidate_banksim.py` HDF5 contract (`sim_inspiral`/`match_map` fields, length alignment) | `bash .claude-wp/tests/WP1_run.sh` (drives master-vs-sync-upstream comparison; **do not run against `master`** expecting success, see §1) |
| `.claude-wp/tests/WP2_probe.py` | capability probe only (no pass/fail gate) — approximant generation/cost/availability survey backing §3 | `./.venv-test/bin/python .claude-wp/tests/WP2_probe.py` |
| `.claude-wp/tests/WP3_test.py` | `TaylorF2Tidal` waveform equivalence/monotonicity; extreme-Λ contact cutoffs (969/376/171 Hz pins, `mode="contact"` explicit post-WP6); registry/CLI/NRTidal guards; HDF5 legacy contract + Λ round-trip; documented XFAIL vs the fiveo01 reference | `./.venv-test/bin/python .claude-wp/tests/WP3_test.py` |
| `.claude-wp/tests/WP4_test.py` | `TaylorF2Ecc`/`TaylorF2EccTidal` equivalence + monotonicity; NRTidalv3 κ₂T fast-fail/finiteness backstops; eccentric transport + legacy HDF5 contract; `SEOBNRv5EHM` generation/e=0 sanity (auto-`SKIPPED(env)` if pyseobnr absent) | `./.venv-test/bin/python .claude-wp/tests/WP4_test.py` |
| `.claude-wp/tests/WP5_test.py` | aligned-limit XPHM/XHM/XAS matches; `IMRPhenomXO4a` corner-point cost + XO4a-vs-XPHM match; `IMRPhenomXP_NRTidalv2` phase monotonicity + tidal-Λ-to-non-tidal-model rejection; S4 per-body tidal cutoff pins (`mode="contact"` explicit); 10-injection `bin/sbank_sim` precessing transport + legacy schema | `./.venv-test/bin/python .claude-wp/tests/WP5_test.py` |
| `.claude-wp/tests/WP6_test.py` | disruption/contact/ISCO cutoff pins + monotonicity (639.41/248.31/112.88 Hz disruption pins); PyCBC-converter round-trip (`add_from_hdf`/`bin/sbank_sim` match identity vs a natively-written control); strict PyCBC refusal + honest MBTA stub message | `./.venv-test/bin/python .claude-wp/tests/WP6_test.py` |
| `.claude-wp/tests/WP7_test.py` | generates all 9 shipped `configs/*.yaml`, cross-checks node counts/no-ilwdchar parent edges/sub-file fields against an independent re-derivation from the raw YAML; schema-validation error messages; `container/sbank-igwn.def` lint; reruns WP3–WP6 as a regression gate | `MPLCONFIGDIR=/tmp/matplotlib-wp7 ./.venv-test/bin/python .claude-wp/tests/WP7_test.py` |
| `.claude-wp/tests/WP8_test.py` | (a) per-bank `--flow`/`--fhigh-max` reaching the emitted leg + missing-flow validation error + 15/45 explicit in templates; (b) historical `SSM`/`ALL` directory/tag casing; (c) S1–S5 real `bin/sbank_sim` integration smokes (tidal contact-vs-disruption, eccentric + combined tidal-eccentric, precessing/HM + tidal-NSBH-ish, `SEOBNRv5EHM`, PyCBC-converted-bank-as-template); (d) full WP3–WP7 regression rerun | `MPLCONFIGDIR=/tmp/matplotlib-wp8 ./.venv-test/bin/python .claude-wp/tests/WP8_test.py` |
| `.claude-wp/tests/WP3_review_*.py`, `WP4_review_*.py`, `WP6_review_*.py` | independent-reviewer scratch scripts (adversarial checks, reference reproduction, physics spot-checks) backing the corresponding `WP*_review.md` verdicts | see each `WP*_review.md` for the exact invocation used |

`.claude-wp/WP8_report.md` (this WP's own report) carries the verbatim `WP8_test.py`
output, including the nested full WP3–WP7 regression rerun (WP7's own suite reruns
WP3–WP6 again internally, so a single `WP8_test.py` run exercises the entire stack
twice — once directly, once via WP7's internal gate).

---

## 5. Container

`container/sbank-igwn.def` + `container/build.sh` + `container/README.md` (WP7 Part C).
**Not built or run anywhere in this project** — no docker/apptainer was available in any
WP's environment. The recipe is syntactically self-consistent and every package in its
`conda create` block is traceable to a locally verified build log
(`.claude-wp/env_build.log`, `.claude-wp/pyseobnr_install.log`) or justified in
`container/README.md`; this is lint-checked automatically by `WP7_test.py` part (c), but
**lint-checked is not built-and-run**.

**Build** (Linux host with `apptainer`/`singularity`, per `container/README.md`):
```
container/build.sh [output.sif]     # defaults to container/sbank-igwn.sif
```
Must be run from the repo root (the `.def` file's `%files` paths are resolved relative to
Apptainer's CWD at build time, not the `.def` file's own location).

**OSDF copy** (best-known-convention, **UNVERIFIED** — no OSDF endpoint reachable from any
WP's environment):
```
pelican object put sbank-igwn.sif osdf:///igwn/<namespace>/.../sbank-igwn.sif
```

**Submit-file container attributes** emitted by `bin/sbank_sim_dag_config` for every
banksim job class (both attributes together, for pool-migration compatibility):
```
container_image = osdf:///igwn/<namespace>/.../sbank-igwn.sif
+SingularityImage = "osdf:///igwn/<namespace>/.../sbank-igwn.sif"
getenv = OMP_NUM_THREADS,OPENBLAS_NUM_THREADS
```

### UNVERIFIED items (from WP7, carried forward unchanged by WP8)

- **The image itself**: not built, not measured. `container/README.md`'s size estimate
  (3–5 GB uncompressed conda env, ~2–3 GB compressed `.sif`) is explicitly labeled an
  ESTIMATE — replace with a real number on first build.
- **The `container_image`/`+SingularityImage` dual-attribute convention**: sourced from
  the HTCondor manual and general IGWN/OSG convention as known at authoring time, **not**
  verified against a live IGWN submit host (no condor installed anywhere in this project).
  Confirm against current `computing.docs.ligo.org` container-submission guidance before
  a production submit.
- **OSDF distribution steps** (`pelican object put` / `stashcp`): best-known-convention
  description, not exercised against a real OSDF endpoint.
- Part A's opt-in `bin/sbank_sim_pipe` changes (accounting/resources/transfer/container/
  log-dir/policy helpers) were verified only by source inspection and `--help`, **not** by
  actually generating a DAG — `lalapps.inspiral.InspiralAnalysisJob` is unavailable on any
  modern lalsuite (item 0, §7), so `bin/sbank_sim_pipe`/`bin/sbank_pipe` cannot generate a
  DAG at all in this environment. Use `bin/sbank_sim_dag_config` (WP7 Part B, fully
  exercised) for any new campaign instead.

---

## 6. What the follow-up plan needs from the user/Yinglei

- **PyCBC bank files** for any non-GstLAL bank the next campaign wants to ingest via
  `bin/sbank_convert_bank`, plus **a sample MBTA bank file** — B3's MBTA stub
  (`--format mbta`) refuses with an actionable message listing exactly what's unknown
  (distribution file format, parameter column names/units, `f_low` convention, split-bank
  structure); nothing was invented without a real sample to verify against.
- **Real accounting tags** (`condor.accounting_group`/`condor.accounting_group_user`) —
  every shipped `configs/*.yaml` ships `{{ACCOUNTING_TAG}}`/`{{ACCOUNTING_USER}}`
  placeholders, not production values.
- **Cluster paths** for every other `{{...}}` placeholder in `configs/*.yaml`
  (`{{BANK_PATH_*}}`, `{{PSD_PATH}}`, `{{INJECTION_FILE_*}}`, `{{OUTPUT_DIR}}`,
  `{{LOG_DIR}}`, `{{CONTAINER_OSDF_PATH}}`) — fill via `--set TOKEN=VALUE` or edit a copy.
- **An `apptainer build` on a real Linux host** — see §5; this is the single largest
  unverified item blocking a real cluster submission.
- **An R8 (`eccentricNSBH`) decision** — WP7 shipped no config for it; it appears in the
  F4 campaign sheet's 8-run list but was not in WP7.md's own enumerated Part B list, and
  WP7's report flags this explicitly as "read as intentional scoping ... flagged here in
  case the reviewer intended otherwise." Still open.
- **Per-bank `flow` values for non-GstLAL banks** (PyCBC/MBTA) — WP8's per-bank
  `banks.<name>.flow`/`fhigh_max` schema (§ "Part P" below) makes this pluggable with no
  hardcoded convention, but the actual numbers for a PyCBC or MBTA bank are unknown here
  and must come from whoever built that bank.
- **A B&B `f_Roche` validation task** — WP6's Roche-overflow disruption cutoff uses the
  Eggleton rigid-Roche-lobe approximation as a closed-form proxy for Bandopadhyay & Brown
  2212.03855's EOS-consistent LORENE quasi-equilibrium `f_Roche`; this substitution is
  documented as a modelling choice (§7) but not independently validated against the
  EOS-consistent calculation.
- **Pilot protocol**: F4's own instruction is 100-injection pilots per run block (F4
  §5) before launching a full campaign — none of WP7/WP8's work ran an actual pilot on a
  real cluster; only the tiny local smokes in §4/§7 below.

---

## 7. Known limitations (honest)

- **Item 0 — legacy pipe scripts dead on modern lalsuite.** `bin/sbank_sim_pipe` and
  `bin/sbank_pipe` both build their DAG job classes on
  `lalapps.inspiral.InspiralAnalysisJob`, removed from lalsuite in Spring 2025
  (confirmed: `import lalapps.inspiral` → `ModuleNotFoundError` in this environment).
  Neither script can generate a DAG on any modern IGWN stack — only `--help` works. Use
  `bin/sbank_sim_dag_config` (WP7) for any new campaign.
- **`glue.pipeline` vanilla-universe transfer limitation.** `CondorDAGNode.add_input_file()`/
  `add_file_opt()` only populate a submit file's `transfer_input_files` for the `grid`
  universe, not `vanilla` (verified by reading the installed `glue/pipeline.py` source
  directly) — a real limitation of the legacy pipe machinery that `bin/sbank_sim_dag_config`
  avoids entirely by writing `transfer_input_files` directly per job class.
- **MBTA ingestion is a stub, not a guess.** `bin/sbank_convert_bank --format mbta` always
  fails with an actionable "MBTA schema unverified — provide a sample file" error; no MBTA
  schema was available in any WP to verify against.
- **NRTidal validity bounds + κ₂T guard.** `IMRPhenomD_NRTidalv2` is BNS-scale-calibrated
  only (Λ ≲ few×10³) — do not reuse for subsolar. `IMRPhenomXAS_NRTidalv3` has an explicit
  κ₂T (`SimNRTunedTidesComputeKappa2T`) fast-fail rejecting Λ combinations above ~60,000
  (measured onset 68,151–102,345 depending on mass ratio, with a documented safety
  margin). `IMRPhenomXP_NRTidalv2` (WP5, precessing+tidal) has **no validated
  extreme-Λ fast-fail boundary** — only empty-output and non-finite-waveform backstops,
  which are authoritative but not a proactive bound like κ₂T.
- **Eggleton-vs-LORENE Roche approximation.** WP6's `disruption` mode combines the
  existing C-Love compactness fit with an Eggleton rigid-Roche-lobe fraction — a
  closed-form proxy for Bandopadhyay & Brown's EOS-consistent LORENE-derived `f_Roche`,
  not a reproduction of it. Flagged as a TODO in `TaylorF2TidalTemplate`'s own docstring
  and in §6 above.
- **HM phase-maximization caveat in matches.** Higher-order-mode template classes
  (`IMRPhenomXHM` family) maximize over sky location and amplitude but explicitly **not**
  over phase (`HigherOrderModeTemplate.brute_match`) — this is physically correct for HM
  content (phase maximization is invalid across modes) but means HM matches are not
  directly comparable to phase-maximized aligned-spin matches without accounting for the
  difference (WP5's own aligned-limit test notes phase/time maximization "absorbs the
  small documented Phenom convention differences" for the ≥0.999 aligned-limit checks
  specifically, which is a narrower claim than "HM matches are phase-maximized").
- **Eccentric + tidal validity.** `TaylorF2Ecc`/`TaylorF2EccTidal` are the Moore/Favata
  3PN, leading-O(e²) model, valid for e ≲ 0.1, with **no periastron/mean-anomaly phase
  dependence** (mean anomaly is transported for interoperability with eccentric IMR models
  only, not used in the TaylorF2Ecc phase itself). `SEOBNRv5EHM` is the higher-e,
  IMR-capable alternative (injection-only, pyseobnr-gated, TD-generated — keep injection
  counts small, WP8's S4 smoke uses 2–3).
- **WP8-specific, still open** (per WP7 NB-1's broadened-reach finding, now *partially*
  closed): the per-bank `flow` schema fix (§ below) resolves the allsky/SSM f_low split
  for the shipped BNS/subsolar configs, but the **combined "ALL"/`all` bank's own f_low
  convention is not specified anywhere in F4** — every multi-bank template currently
  leaves the `all` bank's leg falling back to the campaign's global `psd.flow` (documented
  per-config, not silently guessed), which is a reasonable default but not a confirmed
  convention. See §6.

---

## Appendix: WP8's own changes (Part P + Part S)

**Part P (config-generator preamble fixes).**
`bin/sbank_sim_dag_config`'s schema gained an optional per-bank `banks.<name>.flow`
(overrides the global `psd.flow` for that bank's legs) and `banks.<name>.fhigh_max`
(emits `--fhigh-max` for that leg), plus `banks.<name>.tag` (display casing for the
emitted directory/job/file names, defaulting to the bank's own YAML key). No convention
is hardcoded in the generator — a bank leg with neither its own `flow` nor a resolvable
global `psd.flow` is a clear schema-validation error naming exactly which leg and how to
fix it. `configs/r1_eccentric_bns_lowspin.yaml`, `r6_eccentric_bns_spincross.yaml`,
`tidal_bns.yaml`, and `tidal_subsolar.yaml` now set the GstLAL O4 conventions (allsky:
15.0 Hz, SSM: 45.0 Hz) **explicitly as data** on each bank entry, with a comment naming
them as such — this closes WP7 review finding NB-1 (previously the SSM leg of every
multi-bank BNS run silently inherited the allsky bank's 15 Hz, and tidal_subsolar's
allsky leg silently inherited the SSM campaign's 45 Hz). The same four configs also set
`tag: SSM` / `tag: ALL` on their SSM/ALL bank entries so emitted directories/job
tags/file stems match the historical campaign casing `01_consolidate_banksim.py`'s
`SCENARIOS` globs expect (closes NB-2). `r7_precess_nsbh.yaml` gained an explicit
(functionally no-op) `tidal:` block for self-documentation parity with the tidal configs
(closes NB-4). R3's existing two-directory documentation (NB-3) was left as-is per the
WP8 spec.

**Part S (integration smokes).** `.claude-wp/tests/WP8_test.py` runs five real
`bin/sbank_sim` invocations (tiny: ~10 injections vs a ~20-template mini-bank, except
S4's SEOBNRv5EHM smoke which uses 2–3 injections against a 5-template bank to keep the
TD-model runtime sane): S1 tidal contact-vs-disruption (asserts different matches at a
high-Λ subsolar point, identical legacy schema); S2 eccentric (`TaylorF2Ecc`) and
combined (`TaylorF2EccTidal`); S3 precessing/HM (`IMRPhenomXO4a` vs an `IMRPhenomXAS`
bank) and tidal-precessing (`IMRPhenomXP_NRTidalv2` vs the same bank, NSBH-ish point); S4
`SEOBNRv5EHM` injections vs an `IMRPhenomXAS` bank; S5 a `bin/sbank_convert_bank`-ingested
PyCBC-schema mini-bank as the template side of a run. Every smoke asserts exit 0, the
consolidator-contract schema (`sim_inspiral`/`sngl_inspiral`/`match_map`/`process`/
`process_params`, plus the additive `lambda1`/`lambda2`/`eccentricity`/`mean_anomaly`
datasets exactly where the injection approximant's `is_tidal`/`is_eccentric` flags say
they should appear), and finite matches in (0, 1]. Full verbatim output is in
`.claude-wp/WP8_report.md`.

## WP9 campaign tooling (2026-11)

`bin/sbank_sim_dag_config` now prepares transfer-mode jobs for the IGWN pool:
the default executable is `/opt/conda/envs/sbank-igwn/bin/sbank_sim` inside the
container, `transfer_executable = false`, full input paths/OSDF URLs are staged
while arguments use basenames, each initialdir and its `logs/` are created, and
only `$(tag).h5` is returned. Shared-filesystem mode keeps full argument paths.
Non-HDF banks require an explicit approximant. Raw `condor.extra_submit` lines,
optional string `condor.getenv` (absent by default), and global/bank/injection
`extra_args` are supported; NOILWD and PLOT default off. Per-injection `tidal`
overrides the campaign block, with `tidal: null` disabling tidal options for BBH.
Container image directives and the `--allow-placeholders`, `--set`, and
`--user-tag` CLI remain available. These are generation checks; no live IGWN
submission has been performed.

- `configs/dd2_subsolar.yaml`: DD2 subsolar TaylorF2Tidal injections, explicit
  ISCO cutoff and alpha/alpha1 lambdas, and a `SUBSOLAR_CUT_ARGS` placeholder.
- `configs/dd2_bns.yaml`: DD2 BNS TaylorF2Tidal injections; the ALL bank leg uses
  15 Hz (the other new configs use 45 Hz for ALL).
- `configs/lvk_ssm_release_aligned.yaml`: separate tidal BNS and TaylorF2 BBH
  blocks; alpha4 preserves the release row index and BBH disables tidal options.
- `configs/lvk_ssm_release_precessing.yaml`: IMRPhenomXP_NRTidalv3 BNS with
  `--injection-f-ref 30 --skip-waveform-errors`, and IMRPhenomXPHM BBH with
  `--injection-f-ref 30`; alpha4 preserves the release row index. All four
  templates use explicit TaylorF2 banks, neighborhood size 1 in tau0, and
  placeholders for production inputs/resources. Their integer count defaults
  (100000 injections / 5000 jobs / 20 per job) **must be reset to the final
  selected or post-EOS-cut count** before submission. ISCO matches the ALF2-era
  runs; this fork uses LAL's default PN order and has no `--template-pn-order`.
- `bin/sbank_inj_eos_lambda`: writes tidal deformabilities from a named lalsimulation
  equation of state (e.g. `GPPVA_DD2_BSK24`, `ALF2`) into a sim_inspiral XML's
  `alpha`/`alpha1` columns (Lambda = 2/3 k2 / C^5 from `SimNeutronStarRadius` and
  `SimNeutronStarLoveNumberK2`), drops rows with a component mass outside the EOS's
  stable range (or zeroes them with `--keep-outside`), records input md5, EOS limits
  and counts in process_params, and prints the kept count (the DAG `n_total`).
  `--verify` recomputes Lambda for an existing XML or a banksim `.h5` and exits 1 on
  masses outside support or deviations above `--tolerance` (default 1e-3), with
  constant-factor and swapped-component diagnostics. 100k rows: about 2 s.
- `bin/sbank_inj_from_lvk_release`: converts an LVK search-sensitivity injection HDF5
  (`events` compound dataset, O4a sub-solar release) to a sim_inspiral XML for
  `sbank_sim`: detector-frame masses by default, `--spin-mode aligned|precessing`,
  release Lambdas into `alpha`/`alpha1`, eccentricity into `alpha2`, the release row
  index into `alpha4`, optimal network SNR into `alpha5`; right ascension,
  declination, polarisation and time are folded into sbank's detector-frame
  polarisation angle (latitude pi/2, longitude 0, psi = atan2(Fc, Fp)/2 from the
  detector's antenna response). `--index-csv` writes a row map. 300k rows: about
  7 s, 0.75 GB.
- `IMRPhenomXP_NRTidalv3` is registered as an injection/template class (kappa2T >
  6e4 rejected, an sbank safety choice). `sbank_sim --injection-f-ref HZ` sets the
  spin reference frequency for the injection bank only (default: flow, unchanged
  behaviour). `sbank_sim --skip-waveform-errors` continues past per-injection LAL
  failures, writing NaN matches and a 1 in the new `/inj_status` int8 dataset (always
  written, zeros otherwise). Tests: `.claude-wp/tests/WP9_{dag,eos,lvk,wave}_test.py`.
