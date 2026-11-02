---
name: dev-just-recipe-manage
description: Discover, run, write and edit `just` recipes in a `justfile`. Use when a project has a `justfile` or the user mentions `just`, `justfile`, or recipes; prefer recipes over ad-hoc commands for commonly used commands.
---

# Just Recipe Management

## Workflow

1. **Discover** - `just --list` (recipes with doc-comments), `just --show <RECIPE>` (source), `just --dump` (whole justfile), `just --evaluate` (variables), `just --summary` (names only), `just --help` (CLI syntax).
2. **Run** - `just` (default recipe), `just <RECIPE>`, `just <RECIPE> <ARG1> <ARG2>`.
3. **Author** - match the existing justfile style; turn commonly used commands and scripts into recipes.
4. **Verify** - `just --list` and run the changed recipe.

## Guidelines

- The comment directly preceding a recipe is its doc-comment and appears in `just --list`; always add one.
- Each recipe line runs in a fresh shell. Recipes whose body starts with `#!` run as a script; use that for multi-line logic and `set -euxo pipefail` for Bash.
- Dependencies go after the colon (`run: compile`); parameters before it, with optional defaults (`serve port='8080':`).
- Variables: `name := 'value'`, interpolated as `{{ name }}`.

## Example

```just
executable := 'main'

# compile main.c
compile:
  cc main.c -o {{ executable }}

# run main
run: compile
  ./{{ executable }}

# start webserver
serve port='8080':
  python -m http.server {{ port }}

# publish current tag
publish:
  #!/usr/bin/env bash
  set -euxo pipefail
  tag=`git describe --tags --exact-match`
  ./bin/check-tag $tag
  git push origin $tag
```
