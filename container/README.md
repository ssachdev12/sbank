# sbank-igwn container (WP7 Part C)

`sbank-igwn.def` builds an Apptainer image for running `sbank_sim` banksim jobs on
the IGWN pool, including the `SEOBNRv5EHM` injections used by R1's cross-check block
and R5/R8 (F4 campaign sheet), which need `pyseobnr` -- not shipped by the plain
IGWN pool environment.

**This recipe was not built or run in this WP.** There is no docker/apptainer on the
machine this was authored on (see `.claude-wp/WP7.md`). It was instead written to
*exactly mirror* the environment already built and verified locally in
`.claude-wp/env_build.log` and `.claude-wp/pyseobnr_install.log` (conda-forge
python=3.11 + lalsuite Python bindings + pyseobnr + `pip install --no-build-isolation .`
of this checkout, confirmed to build `sbank.overlap_cpu` and link against conda's
`liblal`). `container/sbank-igwn.def` is syntactically self-consistent and
package-for-package traceable to that log, but has only been lint-checked
(`.claude-wp/tests/WP7_test.py` part (c)), not actually built. **Build and smoke-test
it on a real Linux host/cluster before trusting the resulting `.sif`.**

## Build

```
container/build.sh [output.sif]     # defaults to container/sbank-igwn.sif
```

Requires a Linux host with `apptainer` (or `singularity`) installed, network access
to pull the `condaforge/miniforge3` Docker base and the conda-forge/pyseobnr channel
packages, and local disk for the build (see "Image-size expectations" below).
`build.sh` always `cd`s to the repo root before invoking `apptainer build`, because
the `.def` file's `%files` section paths (`bin`, `sbank`, `setup.py`, ...) are
resolved relative to Apptainer's *current working directory* at build time, not
relative to the `.def` file's own location -- an easy mistake if you `cd
container/` first and run `apptainer build sbank-igwn.sif sbank-igwn.def` directly.

## What's in the recipe, and why

Every package below is present because it appears in the locally verified build
(`.claude-wp/env_build.log`'s final successful `conda create` package list, or
`.claude-wp/pyseobnr_install.log`'s pyseobnr install):

| package | source | why |
|---|---|---|
| `python=3.11` | conda-forge | pinned version matching the verified local env and IGWN's `igwn-py311` pool env (`.claude-wp/WP2_memo.md` section 1) |
| `python-lalsimulation`, `python-lalinspiral` | conda-forge | waveform generation + `Bank`/`sbank_sim` dependencies |
| `python-ligo-lw` | conda-forge | ships the `ligolw_no_ilwdchar` executable `bin/sbank_sim_pipe`'s `NoIlwdJob` wraps -- **not** provided by `igwn-ligolw` (see "ligolw_no_ilwdchar" below) |
| `igwn-ligolw` | conda-forge | what `sbank`'s own Python code imports post-migration (`.claude-wp/WP1_report.md`, upstream commit `94088fe`) |
| `numpy`, `scipy`, `h5py`, `matplotlib`, `cython`, `pip` | conda-forge | sbank's own runtime/build dependencies (`requirements.txt`, `pyproject.toml`) |
| `pyseobnr` | **conda-forge only** | `SEOBNRv5EHM` injections (`sbank/waveforms.py`'s `_HAVE_PYSEOBNR`-gated class). **The pip route is verified BROKEN**: `.claude-wp/pyseobnr_install.log` shows `pip install pyseobnr` failing to build its `pygsl_lite` dependency because `gsl-config` isn't on `PATH` in a bare pip environment. conda-forge's `pyseobnr` package pulls a working `pygsl_lite` + `gsl` automatically. This recipe **never** runs `pip install pyseobnr` anywhere. |
| `lalsimulation-data` | conda-forge | ROM/NRTidal waveform data files + `$LAL_DATA_PATH` -- needed on-cluster for NRTidal ROM models (`.claude-wp/WP2_memo.md` section 1: the minimal pip wheel lacks these, IGWN's own env carries them, so this container does too) |

One addition **not** in the verified package list, justified here per the WP7 spec's
own instruction ("every package in the def appears in the verified recipe list or is
justified in README"):

- **`c-compiler` / `cxx-compiler`** (conda-forge meta-packages, resolve to
  `gcc_linux-64`/`gxx_linux-64` on this Linux-based image). The local verified build
  (`env_build.log`) ran `pip install --no-build-isolation .` on **macOS**, where
  `clang` from the system Xcode Command Line Tools was already on `PATH` -- the log's
  final successful build compiled `sbank/overlap_cpu.pyx` and linked it against
  conda's `liblal` using that system compiler, not a conda one. `condaforge/miniforge3`
  (Debian-based) has **no** system compiler by default, so this container recipe adds
  the conda-forge compiler meta-packages to reproduce the same "compile
  `sbank.overlap_cpu` and link against conda-forge's `liblal`" step the log verified,
  just with a Linux-native toolchain instead of macOS's. This is a like-for-like
  substitution of *how* the compile step happens, not a new capability.

**No package outside this table (or the base `python=3.11`/`pip` toolchain) appears
in the recipe.** In particular: **no `pip install pyseobnr`** anywhere (verified by
`.claude-wp/tests/WP7_test.py` part (c), which greps the `.def` file for this).

Note on `pyyaml`/`lscsoft-glue`/other transitive deps: `sbank`'s own `setup.cfg`
`install_requires` lists `lscsoft-glue` and (as of WP7) `pyyaml` (needed by the new
`bin/sbank_sim_dag_config` -- a *submit-host* tool this container does not need to run
`sbank_sim`/`sbank_plot_sim`/`ligolw_no_ilwdchar`). Neither is listed explicitly in
this recipe's `conda create` line because `.claude-wp/env_build.log`'s verified local
build shows conda's own dependency solver pulling both in transitively from this same
core package set (`lscsoft-glue-4.1.1` and `pyyaml-6.0.3` both appear, unrequested by
name, in that log's `conda create` package list) -- so `pip install --no-build-isolation .`
finds them already satisfied and only needs to compile `sbank.overlap_cpu`, exactly as
the log shows. If a future conda-forge solve of this recipe's package set does NOT
happen to pull one of `sbank`'s `install_requires` in transitively, `pip install
--no-build-isolation .` will fall back to installing it from PyPI directly (no
`--no-deps` flag is used) -- that's a normal pip fallback, not a failure mode, just
worth knowing about at build time.

## `ligolw_no_ilwdchar` -- why both `python-ligo-lw` and `igwn-ligolw`

WP7 audit item 6 (`.claude-wp/WP7_report.md` Part A): post-migration, `igwn_ligolw`
**dropped `ilwd:char` support entirely**, which makes the `ligolw_no_ilwdchar` strip
step *more* necessary for legacy GstLAL-era injection XML, not less -- but the
`ligolw_no_ilwdchar` **executable itself ships with `python-ligo-lw`**, not
`igwn-ligolw`. Installing only `igwn-ligolw` (the package `sbank`'s own Python
imports need) would leave `NoIlwdJob`'s executable missing from `$PATH` inside the
container. This recipe installs both, side by side, in the same conda env -- this is
not redundant packaging, it mirrors the locally verified env exactly
(`.claude-wp/WP1_report.md`: "Confirmed both `lal`/`lalsimulation`/`h5py`/`igwn_ligolw`
(new) and `ligo.lw`/`python-ligo-lw` (old) are installed side by side in this venv").

## Distribution via OSDF

1. Build on a Linux host/cluster: `container/build.sh sbank-igwn.sif`.
2. Copy the `.sif` to OSDF (the IGWN pool's origin/cache-backed distribution layer)
   with whichever OSDF client is provisioned on your submit host -- typically the
   `pelican` CLI (`pelican object put sbank-igwn.sif osdf:///igwn/<namespace>/.../sbank-igwn.sif`)
   or `stashcp` in reverse-copy mode. **This step is a best-known-convention
   description, not verified from this environment** (no OSDF endpoint reachable
   here) -- confirm the exact client/namespace against current
   `computing.docs.ligo.org` OSDF guidance before relying on it.
3. Reference the resulting `osdf://` URL from a submit file's container attribute
   (this is exactly what `bin/sbank_sim_dag_config` does with a config's
   `condor.container_image` field -- see any `configs/*.yaml` template's
   `{{CONTAINER_OSDF_PATH}}` placeholder):

   ```
   universe = vanilla
   container_image = osdf:///igwn/<namespace>/.../sbank-igwn.sif
   +SingularityImage = "osdf:///igwn/<namespace>/.../sbank-igwn.sif"
   getenv = OMP_NUM_THREADS,OPENBLAS_NUM_THREADS
   ```

   Both attributes are emitted together (`container_image` is the modern
   HTCondor/OSG convention for `osdf://`/`cvmfs://` image URLs; `+SingularityImage`
   is the older classic-universe classad some pool nodes may still key off of) --
   **FLAGGED FOR REVIEWER**: this dual-attribute approach is sourced from the
   HTCondor manual's `container_image` submit command and general IGWN/OSG
   container-submission convention as known at authoring time, **not** verified
   against a live IGWN submit host from this environment (no condor installed here).
   Confirm against a current pool's `condor_submit -dump` / container-submission docs
   before depending on both simultaneously in production.

## Image-size expectations (ESTIMATE, not measured)

No docker/apptainer was available to actually build and measure this image in this
WP -- the following is an order-of-magnitude estimate, not a measurement, and should
be replaced with a real number the first time `container/build.sh` is actually run:

- A conda-forge lalsuite Python stack (lal/lalsimulation/lalinspiral + numpy/scipy/
  h5py/matplotlib) typically runs **1.5-2.5 GB** installed.
- `pyseobnr` pulls a substantial extra dependency tree (numba/llvmlite, pandas,
  `spherical`/`scri`/`sxs`/`quaternion`, `pyjuliacall`/`pyjuliapkg` -- see the package
  list in `.claude-wp/pyseobnr_install.log`), plausibly another **1-2 GB**.
- `lalsimulation-data`'s ROM/NRTidal HDF5 files add a further **0.5-1.5 GB**
  (`.claude-wp/WP2_memo.md` describes these as "large HDF5 waveform-data files").
- Compressed `.sif` (SquashFS) is typically 30-50% smaller than the installed conda
  env size.

**Rough total estimate: 3-5 GB uncompressed conda env, plausibly 2-3 GB compressed
`.sif`.** Verify on first real build and update this section with the measured
number.

## `igwn-py311` alternative (native env, no container, no `pyseobnr`)

For any campaign that does **not** use `SEOBNRv5EHM` (i.e. everything except R1's
`eccBNSxchkEHM` cross-check block, R5, and R8's optional EHM path -- see the F4
campaign sheet and `.claude-wp/WP2_memo.md` section 5's recommendation table), prefer
running directly against IGWN's own pinned `igwn-py311` conda environment (lalsuite
7.26 / lalsimulation 6.2.0 / python 3.11.15, already provisioned via CVMFS on IGWN
pool nodes -- see https://computing.docs.ligo.org/conda/environments/igwn-py311/)
instead of this container. That avoids container-image transfer/pull overhead
entirely and needs no `container_image`/`+SingularityImage` submit attributes (a
plain `should_transfer_files`/shared-filesystem or OSDF-input-file setup suffices for
the bank/PSD/injection files). `bin/sbank_sim_dag_config`'s
`condor.container_image` field is a hard requirement of this WP7 generator's schema
today (every shipped `configs/*.yaml` template sets it, even for non-EHM runs) --
using the `igwn-py311` path in practice means pointing `container_image` at a
pre-existing IGWN-provided image/CVMFS path rather than this repo's own `.sif`, or
running `sbank_sim`/`ligolw_no_ilwdchar` directly on an `igwn-py311` execute node
outside of DAGMan's container attributes altogether (a schema/generator extension
beyond this WP's scope -- flagged for a follow-up work package if that split proves
worth automating).
