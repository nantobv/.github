# Org-wide policy for nantobv

This repo doubles as the configuration source for org-wide policy on
`github.com/nantobv` (under the `nanto-org` Enterprise account). Policy that
lives **inside the org Settings UI** (rulesets, custom properties, required
workflows) is captured here as code, with an idempotent apply script.

## What lives where

| Artifact                         | Path                                         | Applied by                                   |
| -------------------------------- | -------------------------------------------- | -------------------------------------------- |
| Reusable CI workflows            | `.github/workflows/*.yml`                    | Each caller repo (`uses:`)                   |
| Workflow templates (UI picker)   | `workflow-templates/*.yml` + `.properties.json` | GitHub, automatically from the `.github` repo |
| Starter Dependabot config        | `starters/dependabot.yml`                    | Copy-paste into each repo                    |
| Shared AGENTS.md agent policy    | `AGENTS.shared.md`                           | Vendored via `scripts/sync-agents-shared.sh` |
| Custom repo properties           | `scripts/apply-org-policy.sh`                | `./scripts/apply-org-policy.sh`              |
| Production ruleset (branch protection + required workflow) | `scripts/rulesets/production.json` | `./scripts/apply-org-policy.sh` |
| Community health defaults (CoC, CONTRIBUTING, SECURITY, PR/issue templates) | Repo root + `ISSUE_TEMPLATE/` | GitHub, automatically from the `.github` repo |
| Org profile README               | `profile/README.md`                          | GitHub, automatically                        |

## Custom properties

Two organization-level properties are defined. They are the routing primitive
for everything else — rulesets target by property, not by repo name.

| Property   | Type            | Values                                           | Purpose                                       |
| ---------- | --------------- | ------------------------------------------------ | --------------------------------------------- |
| `language` | single_select   | `go`, `rust`, `python`, `mixed`, `none`          | Selects the right reusable CI template/policy |
| `tier`     | single_select   | `production`, `internal`, `experiment`, `archived` | Selects ruleset strictness                  |

Set them per repo with `gh`:

```sh
gh api -X PATCH "orgs/nantobv/properties/values" \
  -F 'repository_names[]=<repo>' \
  -F 'properties[][property_name]=tier' -F 'properties[][value]=production' \
  -F 'properties[][property_name]=language' -F 'properties[][value]=go'
```

Or in the UI: **Org Settings → Repository → Custom properties → Set values**.

## Rulesets

### `production-main`

Targets the default branch of every repo with `tier=production`. Rules:

- **deletion** — block branch deletion
- **non_fast_forward** — block force pushes
- **required_linear_history** — no merge commits on `main`; rebase or squash
- **pull_request** — require PR to merge (0 approvals, thread resolution required, stale reviews dismissed)

> **Solo-dev note:** `required_approving_review_count` is `0` so you can
> self-merge after CI is green. The PR mechanism + thread-resolution is
> what's enforced.

### `production-<lang>-ci`

`production-main` only requires that a PR *exists* — on its own it would let
a red build self-merge. The actual CI gate lives in three companion rulesets,
applied by default by `apply-org-policy.sh`:

| Ruleset | Targets (ANDed) | Requires |
| --- | --- | --- |
| `production-go-ci` | `tier=production` + `language=go` | `required-go-ci.yml` |
| `production-python-ci` | `tier=production` + `language=python` | `required-python-ci.yml` |
| `production-rust-ci` | `tier=production` + `language=rust` | `required-rust-ci.yml` |

Each uses a `workflows` rule pointing at a non-reusable wrapper in
`nantobv/.github`. Wrappers are required because the GitHub API rejects
reusable (workflow_call-only) workflows — the target must have a
`pull_request`/`pull_request_target`/`merge_group` trigger. Language scoping
means a Python repo is never forced to run Go CI.

> **Prerequisite:** the `required-<lang>-ci.yml` wrappers must already be on
> `nantobv/.github@main`, or the API rejects the rule with HTTP 422. While
> bootstrapping (wrappers not yet merged), skip this block:
>
> ```sh
> APPLY_REQUIRED_CI=false ./scripts/apply-org-policy.sh
> ```

**Vulnerability scans are deliberately *not* part of the merge gate.** The
wrappers call the reusables with `run-vuln-scan: false` (Rust:
`run-cargo-audit: false`), so a freshly-disclosed CVE in a transitive dep
can't turn every production repo's merges red overnight. Vuln scanning still
runs as **advisory** in each repo's own `ci.yml` (and via the Dependabot
starter / scheduled scans), where it's visible without blocking unrelated work.

### Required pinact check (opt-in)

A separate wrapper at `.github/workflows/required-pinact-check.yml` calls the
reusable `pinact-check.yml`. It's injected into `production-main` only when
opted in:

```sh
REQUIRED_WORKFLOW_PATH=.github/workflows/required-pinact-check.yml \
  ./scripts/apply-org-policy.sh
```

## Shared AGENTS.md block

`AGENTS.shared.md` is the canonical org-wide AI agent policy — git hygiene,
plan-first, evidence-before-claiming-done, no secrets, source-files-are-user-owned,
and the `claude-adversarial-review` standing grant. GitHub's community-health-file
auto-fallback does not cover `AGENTS.md`, and AI agents read it from the local
working tree at runtime, so the file is **vendored into each repo's `AGENTS.md`**
between marker comments rather than auto-applied.

To wire a new repo:

1. Add the marker pair to the repo's `AGENTS.md` (typically after the
   **Project** section):

   ```markdown
   <!-- BEGIN nantobv-shared (sync via nantobv/.github/scripts/sync-agents-shared.sh) -->
   (this body is replaced by sync-agents-shared.sh)
   <!-- END nantobv-shared -->
   ```

2. Run `scripts/sync-agents-shared.sh` from the repo root. Idempotent;
   resolves the canonical source from `$NANTOBV_SHARED_PATH`, a sibling
   `nantobv/.github/` clone, or `curl` against `main` in that order.

3. Optionally add a caller workflow that fails CI on drift — see
   [`.github/workflows/agents-shared-check.yml`](.github/workflows/agents-shared-check.yml)
   for the reusable workflow.

The required-check wrapper and ruleset wiring are deferred until every active
repo has the marker block embedded; otherwise a required check would fail
on un-migrated repos.

## Workflow templates

`workflow-templates/{go,rust,python}-ci.yml` appear in **Actions → New
workflow** for every nantobv repo, scoped by their `filePatterns` (e.g.,
the Go template surfaces when `go.mod` is present). Each template is a
thin caller of the matching reusable workflow plus the pinact check, so a
new repo gets the full org CI bar with one click.

## Applying / re-applying

```sh
# Auth as an org owner first:
gh auth login

# Apply (or update) custom properties and the production ruleset:
./scripts/apply-org-policy.sh
```

The script is idempotent: it upserts properties via `PUT
/orgs/.../properties/schema/{name}` and finds the existing ruleset by name
before issuing `PUT` vs `POST`.

## Enterprise features to enable manually (one-time)

These live in the Enterprise/Org Settings UI and aren't expressed as code here.
Each is high-leverage; flip them on when you have ten minutes.

1. **Push protection for secret scanning** — Org Settings → Code security →
   "Push protection for the entire organization". Free for public repos;
   bundled with GHAS for private/internal. Blocks committed secrets at push time.
2. **Dependabot alerts + security updates** — Org Settings → Code security →
   enable both globally. Pairs with the Dependabot starter to update
   vulnerable deps automatically.
3. **Restrict allowed Actions** — Org Settings → Actions → General →
   "Allow `actions/*` and `nantobv/*` plus selected non-nantobv actions".
   Supply-chain hardening: limits which third-party actions any repo can run.
4. **Default workflow permissions** — Same page → "Read repository contents
   and packages permissions" (read-only). Forces workflows to opt into write
   scopes explicitly.
5. **Two-factor authentication** — Org Settings → Authentication security →
   require 2FA for all members.
6. **Audit log streaming** — Enterprise Settings → Audit log → Stream to
   S3/Datadog/Splunk. Worth it the first time you need to look back further
   than the 6-month UI retention.
