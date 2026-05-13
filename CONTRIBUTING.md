# Contributing to Nanto BV projects

Thanks for your interest in contributing. This file is the org-wide default — individual repositories may publish their own `CONTRIBUTING.md` with project-specific setup, build commands, and test instructions, which takes precedence over this one.

## Before You Start

- **Check existing issues.** Look for issues labeled `good first issue` or `help wanted` — these are scoped to be self-contained.
- **Open an issue first** for non-trivial changes. A short discussion before coding prevents wasted effort and surfaces design constraints early.
- **Claim work** by commenting on the issue so others don't duplicate it.

## Workflow

1. Fork the repository and create a branch from `main` (or whichever branch the repo designates as the integration branch).
2. Make your changes. Match the existing code style — most repos have formatters, linters, and pre-commit hooks; run them locally before pushing.
3. Add or update tests where appropriate.
4. Run the repository's full CI check locally (commonly `make ci`, `npm test`, `cargo test`, or similar — see the project's own `CONTRIBUTING.md` or `README.md`).
5. Open a pull request with a clear description of what changed and why.

## Pull Request Guidelines

- **Keep changes small and focused.** One feature or fix per PR. Refactors that touch many files should be a separate PR from behavior changes.
- **Stage specific files** in your commits — avoid `git add .` to prevent accidentally committing local-only state or secrets.
- **No secrets in tracked files, tests, fixtures, or examples.** Use `.env.example` patterns or test doubles.
- **Update documentation** when behavior, public APIs, or CLI interfaces change.
- **Write meaningful commit messages.** Explain *why*, not just *what*.

## Code Review

- Reviews are about the code, not the contributor. Expect questions; they are not objections.
- Address review feedback by pushing follow-up commits to the PR branch rather than force-pushing — it preserves the review history. Final squash is fine.
- Maintainers may push small fixes directly to your branch to accelerate merge.

## Reporting Issues

Use the issue templates provided. The key things a maintainer needs:

- A clear, minimal reproduction.
- Environment details (OS, runtime version, project version or commit).
- What you expected vs. what happened.

For security issues, see [SECURITY.md](SECURITY.md) — please do **not** open public issues for vulnerabilities.

## Community

- Be respectful and constructive. See our [Code of Conduct](CODE_OF_CONDUCT.md).
- Assume good intent. Most contributors are doing this in their spare time.

## Licensing

Unless a repository states otherwise, contributions are accepted under the same license as the project itself. By submitting a contribution, you confirm you have the right to do so and that your contribution is your own work or properly attributed.
