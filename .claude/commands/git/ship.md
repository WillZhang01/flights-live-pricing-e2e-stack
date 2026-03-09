---
name: Git: Ship Feature
description: Clean non-feature-related diffs, review with Skyscanner production standards, create a feature branch, commit, push, and open a Pull Request.
category: Git
tags: [git, commit, pr, review, cleanup]
---

**Guardrails**
- Only commit files that are genuinely part of the feature change. Never include formatting-only diffs, local dependency overrides, scratch files (`dump.rdb`, generated jars), build artifacts, or test credentials.
- In this monorepo, services are separate git repositories. Apply each step to each affected service independently, following the dependency order (QRS → FPS → Conductor → stack repo).
- PR bodies must explicitly call out upstream dependencies and the required merge sequence when multiple services are involved.
- Always verify `git status` and `git diff` look correct before staging any files.
- Do not skip the clean or review steps — they exist to keep PRs minimal and production-ready.

**Steps**

1. **Identify scope**: Run `git status --short` in each affected service directory (`quoteretrievalservice/`, `flights-pricing-svc/`, `conductor/`, `itinerary-construction/`, and the stack root). List which services have changes and briefly note what each modified file appears to do.

2. **Clean non-feature changes**: For each repo, inspect and revert anything not directly implementing the feature:
   - *Formatting-only diffs* — line wrapping, blank-line additions/removals, indentation fixes. Verify with `git diff <file>`; revert with `git checkout -- <file>`.
   - *Local dependency version overrides* — `findProperty` patterns added to `build.gradle` for local inter-service testing (e.g., `quoteRetrievalSvcVersionOverride`, `flightsPricingSvcVersionOverride`). Restore hard-coded versions.
   - *Build script additions for local dependency resolution* — version detection loops and `-P` flag passing added to `build-all-services.sh`. Revert to the committed version.
   - *Scratch and generated files* — `dump.rdb`, `*.class`, IDE files. Add to `.gitignore` if they keep reappearing.
   - After each revert, re-run `git diff <file>` to confirm the noise is gone.

3. **Review remaining changes**: Invoke the `service-golden-path:production-standards` skill on each service's cleaned diff. Check for:
   - Proto backward compatibility (new fields are optional/repeated, not replacing existing fields; field numbers are not reused)
   - Null/empty-list safety in mapping code
   - Metrics and logging for new code paths
   - Test coverage (unit tests updated; test builders include new fields with sensible defaults)

4. **Create feature branch**: In each affected repo run:
   ```
   git checkout -b feature/<change-id>
   ```
   Use the OpenSpec `change-id` (from `openspec/changes/<id>/`) if a proposal exists, otherwise derive a short verb-led slug (e.g., `feature/add-payment-price-options`).

5. **Stage feature files explicitly**: Use `git add <file1> <file2> ...` and list each file by name. Never use `git add -A` or `git add .`. Confirm the staging area with `git status --short` before committing.

6. **Commit**: Write a message structured as:
   - *First line* (≤ 72 chars): imperative summary — what the change does, not what you did.
   - *Body*: one or two sentences on why the change exists; if an upstream service PR must be published before this one is buildable, add `Depends on: <repo>#<number>`.
   - *Footer*: `Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>`

7. **Push**: `git push -u origin feature/<change-id>`

8. **Create PR** — target `master` for all four service repos (`quoteretrievalservice`, `flights-pricing-svc`, `conductor`, `itinerary-construction`) and `main` for the stack repo. Verify the default branch with `git remote show origin | grep 'HEAD branch'` if unsure. The PR body must include:
   - **Summary**: 3–5 bullet points of what changed (proto fields, new model classes, mapper logic, test updates).
   - **Dependency chain table**: a Markdown table with Step / Service / PR / Status rows for every service in the chain (mark upstream as ✅ or ⏳).
   - **Merge-order warning** (when upstream deps exist): state which `build.gradle` version constant needs bumping after the upstream artifact is published, and that the upstream PR must be merged and published *before* this one.
   - **Test plan checklist**: unit tests, proto backward-compat verification (`buf breaking`), and any e2e/Postman steps.

**Reference**
- Inspect a single file: `git diff <file>`
- Quick file-level summary: `git diff --stat`
- Check accepted scope: read `openspec/changes/<change-id>/proposal.md` or run `openspec show <change-id>`
- Default branches: `master` for all four service repos; `main` for the stack repo
- GitHub org for service repos: `Skyscanner`; stack repo owner: `WillZhang01`
- Dependency order: `quoteretrievalservice` → `flights-pricing-svc` → `conductor` (IC has no downstream consumers in this stack)