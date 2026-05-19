# starters/

Files in this directory are **copy-paste starters** for new or existing
nantobv repos. They are intentionally not picked up automatically — copying
makes the resulting config visible inside the consuming repo, where it's
easier to audit and customize.

| File              | Destination in the consuming repo |
| ----------------- | --------------------------------- |
| `dependabot.yml`  | `.github/dependabot.yml`          |

For workflow CI starters, see [`../workflow-templates/`](../workflow-templates/)
— those appear automatically in **Actions → New workflow** for every
nantobv repo.

## Org-wide AGENTS.md shared block

The canonical org-wide AI agent policy lives at [`../AGENTS.shared.md`](../AGENTS.shared.md).
It is **vendored** into each repo's local `AGENTS.md` between marker
comments, rather than auto-applied like community health files (`AGENTS.md`
is not on GitHub's auto-fallback list, and AI agents read it from the local
working tree at runtime).

To wire a repo up:

1. Add the marker pair to the repo's `AGENTS.md` where the shared block
   should appear — typically after the **Project** section and before
   **Coding Standards**:

   ```markdown
   <!-- BEGIN nantobv-shared (sync via nantobv/.github/scripts/sync-agents-shared.sh) -->
   (this body is replaced by sync-agents-shared.sh)
   <!-- END nantobv-shared -->
   ```

2. From the repo root, run the sync script (offline-friendly when a sibling
   `nantobv/.github/` clone exists; otherwise fetches via `curl` from
   GitHub):

   ```sh
   /path/to/nantobv/.github/scripts/sync-agents-shared.sh
   # or, with explicit source:
   NANTOBV_SHARED_PATH=/path/to/nantobv/.github/AGENTS.shared.md \
     /path/to/nantobv/.github/scripts/sync-agents-shared.sh
   ```

3. Commit the regenerated `AGENTS.md` with explicit staging
   (`git add AGENTS.md`).

4. Optionally add a caller workflow that fails CI on drift — see
   [`../.github/workflows/agents-shared-check.yml`](../.github/workflows/agents-shared-check.yml)
   for the reusable workflow and its caller-pattern comment block.
