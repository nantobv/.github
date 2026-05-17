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
- **workflows** — require `nantobv/.github` → `pinact-check.yml@main` to pass before merge

> **Solo-dev note:** `required_approving_review_count` is `0` so you can
> self-merge after CI is green. The PR mechanism itself (and the required
> workflow) is what's enforced.

To extend with language-specific required workflows, add entries to the
`workflows` rule in `scripts/apply-org-policy.sh` referencing
`.github/workflows/{go,rust,python}-ci.yml`. Targeting a workflow at a
repo with a different language is harmless — the caller workflow simply
won't have the right inputs and will fail loudly, which is what you want
for misconfigured repos.

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
