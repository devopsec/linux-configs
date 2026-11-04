# Semantic Versioning & changelog

## SemVer 2.0.0 essentials

`MAJOR.MINOR.PATCH[-PRERELEASE][+BUILD]`, tags prefixed `v` (`v2.3.1`).

| Bump | When |
|---|---|
| MAJOR | incompatible API/behaviour/config change (removed flag, changed DB schema contract, SIP header semantics) |
| MINOR | backward-compatible feature |
| PATCH | backward-compatible fix |
| `-rc.N`, `-beta.N` | pre-release; sorts **before** the release (`1.4.0-rc.2 < 1.4.0`) |
| `+meta` | ignored for precedence (`+git.abc1234`) |

Precedence: numeric compare MAJOR→MINOR→PATCH; pre-release identifiers compared dot by dot (numeric < alphanumeric). `0.y.z`: anything may change — treat breaking as minor bump.
Define what the "public API" is for each component (CLI, config files, RPC, DB schema, SIP behaviour) — that defines MAJOR.

## Conventional Commits → bump

| Commit | Bump | Changelog group |
|---|---|---|
| `feat(scope): …` | minor | Features |
| `fix: …`, `perf: …` | patch | Bug Fixes / Performance |
| `feat!: …` or footer `BREAKING CHANGE: …` | major | ⚠ Breaking |
| `docs`, `refactor`, `test`, `ci`, `build`, `chore`, `style` | none | (optional groups / skipped) |
| `revert: …` | patch (by default) | Reverts |

Writing the commits → `vcs-git-commit-create`. Enforce in PR CI with a commit/PR-title linter (`commitlint`, `cog check`) if adopted; squash-merge with a conventional PR title keeps `main` history clean.

## git-cliff v2.14.2 (checked 2026-10-28)

The signed upstream release is `v2.14.2`, commit `5d996de8220d26c0cb8ff329d31791570cab262f`. Pin the tool in the repo's tool manifest; a temporary invocation is `uvx --from git-cliff==2.14.2 git-cliff`. For release archives, verify the published signature/checksum before execution.

```bash
git cliff --init                                  # writes cliff.toml
git cliff --bumped-version                        # next version from commits since last tag
git cliff --unreleased --tag "$(git cliff --bumped-version)"          # preview notes
git cliff --unreleased --tag "$NEXT" --prepend CHANGELOG.md            # update file (commit via PR)
git cliff --latest --strip header                 # body for GitHub Release
```

Minimal `cliff.toml`:

```toml
[changelog]
body = """
{% if version %}## {{ version | trim_start_matches(pat="v") }} - {{ timestamp | date(format="%Y-%m-%d") }}{% else %}## Unreleased{% endif %}
{% for group, commits in commits | group_by(attribute="group") %}
### {{ group | striptags | trim | upper_first }}
{% for commit in commits %}- {% if commit.scope %}**{{ commit.scope }}:** {% endif %}{% if commit.breaking %}[**breaking**] {% endif %}{{ commit.message | upper_first }}
{% endfor %}{% endfor %}
"""
trim = true

[git]
conventional_commits = true
filter_unconventional = true
protect_breaking_commits = true
tag_pattern = "v[0-9]+\\.[0-9]+\\.[0-9]+"
commit_parsers = [
  { message = "^feat", group = "<!-- 0 -->Features" },
  { message = "^fix", group = "<!-- 1 -->Bug Fixes" },
  { message = "^perf", group = "<!-- 2 -->Performance" },
  { message = "^revert", group = "<!-- 3 -->Reverts" },
  { message = "^doc", group = "<!-- 4 -->Documentation" },
  { message = "^(chore|ci|build|style|test|refactor)", skip = true },
]

[bump]
breaking_always_bump_major = false   # keep 0.x semantics until 1.0.0
```

## Python version in `pyproject.toml` (uv)

```bash
uv version                       # show
uv version --bump minor --dry-run
uv version --bump patch          # edits pyproject.toml + uv.lock
uv version 1.4.0-rc.1            # explicit (PEP 440 normalises to 1.4.0rc1)
```

PEP 440 vs SemVer: `1.4.0-rc.1` (tag) ↔ `1.4.0rc1` (Python). Keep the git tag SemVer; let packaging normalise. If the version is derived from tags instead, use `hatch-vcs`/`setuptools-scm` and do not also bump by hand. In the house model the tag is authoritative and the artifact name is `git-<SHA>` — bumping files is optional metadata.

## Alternatives

| Tool | Fit |
|---|---|
| semantic-release (Node) | fully automated tag+publish from CI; conflicts with "human presses release button" model |
| release-please (GitHub) | opens a release PR with changelog + bump; merge creates tag |
| changesets | JS monorepos; per-package intent files |
| commitizen (`cz bump`) | Python-native bump + changelog |

## Rules

- One source of truth for the version (tag); never reuse or move a tag. Bad release → next patch.
- Changelog is for humans: group, link PRs, highlight breaking changes with migration steps.
- Do not let automation commit to `main` directly; use a release PR when files must change.
- Release notes must not include secrets, customer identifiers or internal hostnames.
