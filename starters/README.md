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
