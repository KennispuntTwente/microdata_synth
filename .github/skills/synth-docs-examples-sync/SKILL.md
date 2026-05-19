---
name: synth-docs-examples-sync
description: Keep README, examples, and public API behavior synchronized after code changes. Use for any feature, bug fix, or refactor that may affect documented usage, function signatures, outputs, or sample workflows.
---

# Docs and Examples Sync Skill

## When To Use

Activate this skill when a user asks to:
- update docs after code changes
- verify examples still run
- align README function signatures with current implementation
- remove stale claims from docs
- add missing usage examples for new behavior

Use this skill after changes in:
- `R/main.R`
- `R/catalog_interface.R`
- `R/data_generator.R`
- `R/validation.R`
- `R/export.R`

## Source Of Truth

Priority order for resolving inconsistencies:
1. Executable code in `R/`
2. Test suite expectations in `tests/testthat/`
3. README and example scripts

If docs conflict with code/tests, update docs/examples to match current behavior unless maintainers explicitly request code rollback.

## Files To Check

- `README.md`
- `examples.R`
- `multi_key_examples.R`
- `LINKING_KEYS.md`
- `.github/copilot-instructions.md`

## Sync Checklist

### 1. Public API signatures

Confirm documented signatures match actual function definitions:
- function name
- required and optional arguments
- defaults
- return shape

Typical drift points:
- `search_datasets()` mode/limit arguments
- `check_referential_integrity()` optional parameters
- export options and defaults

### 2. Behavioral claims

Verify key claims are still true:
- search backend behavior (`auto`, `fuzzy`, `fts`)
- composite tuple-level integrity checks
- NA handling policy in reporting
- period-aware date generation and ordering constraints

### 3. Examples execution validity

Ensure examples use valid current arguments and objects:
- no outdated function names
- no removed columns referenced
- no assumptions that conflict with current validation logic

Prefer concise, realistic examples that run with current code.

### 4. Cross-file consistency

Keep terminology and examples aligned across docs:
- key type names
- dataset naming style
- output path conventions
- warnings/limitations sections

## Recommended Workflow

1. Identify changed behavior from code/tests.
2. Search docs/examples for impacted function names or claims.
3. Update README API list and usage snippets.
4. Update `examples.R` and `multi_key_examples.R` where needed.
5. If linking semantics changed, update `LINKING_KEYS.md`.
6. Run tests and optionally run a short example script segment.

## Validation Commands

Run tests:

```r
Rscript tests/testthat.R
```

Optional quick docs sanity checks:

```r
Rscript -e "source('R/main.R'); print(formals(search_datasets))"
Rscript -e "source('R/main.R'); print(formals(check_referential_integrity))"
Rscript -e "source('R/main.R'); print(head(search_datasets('polis', mode='auto', limit=3)))"
```

## Guardrails

- Do not document unimplemented behavior as complete.
- Avoid copying stale signatures from old docs.
- Keep examples deterministic where possible (set seed).
- Prefer minimal edits that resolve factual drift.

## Completion Checklist

- README API section matches code signatures.
- Search/linking/reporting claims reflect current behavior.
- examples files use valid, runnable calls.
- Relevant tests pass after doc/example updates.
