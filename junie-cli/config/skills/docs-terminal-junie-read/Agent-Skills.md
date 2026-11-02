# Agent skills

<show-structure for="chapter" depth="3"/>

Agent skills are folders with instructions, templates, scripts, and reference materials that provide Junie with 
task-specific context. Skills follow the open [Agent Skills](https://agentskills.io/specification) 
format and are portable across agents.

Unlike [guidelines](Guidelines-and-memory.md), which are applied with every prompt, agent skills are only invoked when they match
the needs of the current task. Junie follows the skill instructions, loading referenced materials or executing 
bundled scrips as needed.

The added agent skill folders are available both to Junie CLI and [Junie in JetBrains IDEs](Junie-IDE-plugin.md).

## Why agent skills?

Think of skills as cheat sheets that Junie consults when working on specific types of tasks to produce better results.
The benefits of agent skills are:

* **Progressive disclosure:** Each skill's name and description are available to Junie, so it knows what skills exist, 
but doesn't read the full content of a skill until it determines its relevance to the task.
* **Instructions with attached files:** Instructions are bundled with reference materials such as templates or 
assets, so Junie has all the context it needs to complete the task.  
* **Portability**: If your project already has skill folders from other agents (`.cursor/skills/`, `.claude/skills/`, 
or `.codex/skills/`), Junie CLI will detect them and suggest importing into Junie's `.junie/skills/` directory.


## How Junie CLI uses skills

Junie CLI invokes agent skills *automatically*. It scans folders inside `.junie/skills/` at the user and project 
levels and selects the skills that are relevant to the current task.

### Skill location

Junie CLI looks for skill folders in two locations:

* *Project scope:* `<projectRoot>/.junie/skills/<skill-name>/`. 

  Skills in this folder are available only in the current 
  project, but can be checked into version control and shared across all team members. 
    
* *User scope:* `~/.junie/skills/<skill-name>/` on macOS/Linux or `%\USERPROFILE%\.junie\skills\<skill-name>\` on Windows. 

  Skills in this folder are available globally across all projects on your machine while remaining private to your user account.

[//]: # (> The default user-level path can be changed by setting the `JUNIE_HOME` environment)
[//]: # (> variable. In that case, skills are loaded from `$JUNIE_HOME/skills/` &#40;macOS/Linux&#41; or `%\JUNIE_HOME%\skills\` &#40;Windows&#41;.)

> If a project-level (`<projectRoot>/.junie/skills/<skill-name>/`) and a user-level (`~/.junie/skills/<skill-name>/`) 
> skills share the same name, the project-level skill takes precedence and the user-level skill is ignored.
> {style="note" title="Scope priority"}

[//]: # (When you add or update skills, Junie CLI notifies you at the start of the next session.)

### Skill directory structure

Each skill lives in its own folder under the `.junie/skills` directory:

```
.junie/skills/
├── my-skill/
│   ├── SKILL.md              # Required: Main skill documentation
│   ├── scripts/              # Optional: Executable scripts
│   │   └── setup.sh
│   ├── templates/            # Optional: Code or doc templates
│   │   └── component.kt
│   └── checklists/           # Optional: Detailed checklists
│       └── review.md
├── another-skill/
│   └── SKILL.md
```

- The `SKILL.md` file is **required**. A folder without it is not recognized as a skill.
- Subdirectories are optional and can contain any supporting files (checklists, scripts, templates, etc.) that Junie CLI
  can read when needed.

### `SKILL.md` format

The `SKILL.md` file uses Markdown with a YAML frontmatter header:

```Markdown
---
name: my-skill-name
description: A short description of what this skill provides
---

# My Skill Name

Use this skill when [describe when Junie should use this skill].

## Key Principles
- Principle 1
- Principle 2

## Guidelines
- Guideline 1
- Guideline 2

## Examples

[Include code examples, patterns, or references to project files]

## Checklist

See `checklists/review.md` for a detailed checklist.
```

#### Required frontmatter fields

| Field         | Type   | Required | Description                                                                                    |
|---------------|--------|----------|------------------------------------------------------------------------------------------------|
| `name`        | String | **Yes**  | A unique identifier for the skill.                                                             |
| `description` | String | **Yes**  | A short summary that Junie CLI can use to determine the skill's relevance to the current task. |
{width="800"}

#### Body content

The body (everything after the closing `---`) is the main skill documentation, which should contain actionable 
instructions that Junie CLI should follow along with the paths to relevant project files, templates, or additional 
materials within the skill folder.

## Adding a skill

### Prompt Junie to add a skill

The easiest way to add a skill is to ask Junie to create it for you. Describe what you want the skill to cover, 
and Junie will generate the skill folder, `SKILL.md`, and any supporting files.

<procedure>

**Example prompt:**

Create a skill that enforces our API design conventions: all REST endpoints must use kebab-case URLs, return JSON
responses wrapped in a `{ data, error }` envelope, and include request validation using our shared `ValidationUtils`
class. Add a checklist for reviewing new endpoints.

</procedure>

You can also create skills on the fly from your current task if the guidelines or patterns Junie followed 
could be reused in future tasks.

<procedure>

**Example prompt:**

The conventions we've been following for database migrations in this task are useful — create a skill from them so we
follow the same approach next time.

</procedure>

### Create your own skill

1. Create a `.junie/skills/` directory.

2. Add a skill folder to the `.junie/skills/` directory.

3. Add a `SKILL.md` file to the skill folder.

```Markdown
---
name: my-new-skill
description: Provides guidelines for [specific domain or task]
---

# My New Skill

Use this skill when [describe the trigger conditions].

## Key Principles

- [Actionable principle 1]
- [Actionable principle 2]

## Guidelines

- [Specific guideline with examples]
- [Reference to project files: `path/to/relevant/file.kt`]

## Code Patterns

    ```kotlin
    // Example of the preferred pattern
    fun example() {
        // ...
    }
    ```
## Additional Resources

- See `checklists/my-checklist.md` for a detailed checklist.
- Run `scripts/setup.sh` to configure the environment.
```
{collapsible="true" default-state="collapsed" collapsed-title=".junie/skills/my-new-skill/SKILL.md"}

4. (Optional) Add supporting files to the skill folder.

    If your skill needs additional resources, create subdirectories with supporting files.

5. Verify that the skill loads. 

    Ask Junie to list its available skills to confirm it loaded correctly.

[//]: # (Start a new Junie session. You should see a notification that a new skill was detected.)

### Add skills from public repositories

You can import skills shared by the community or your organization by copying them from public Git repositories into
your skills directory.

<tabs>
<tab title="macOS/Linux">

```bash
# Clone the repo (or download just the skill folder)
git clone https://github.com/example/junie-skills.git /tmp/junie-skills

# Copy a specific skill to your project
cp -r /tmp/junie-skills/code-review .junie/skills/

# Or copy to your global skills for use across all projects
cp -r /tmp/junie-skills/code-review ~/.junie/skills/

# Clean up
rm -rf /tmp/junie-skills]]>
```
</tab>

<tab title="Windows">

```powershell
# Clone the repo (or download just the skill folder)
git clone https://github.com/example/junie-skills.git $env:TEMP\junie-skills

# Copy a specific skill to your project
Copy-Item -Recurse -Force $env:TEMP\junie-skills\code-review .junie\skills\

# Or copy to your global skills for use across all projects
Copy-Item -Recurse -Force $env:TEMP\junie-skills\code-review "$env:USERPROFILE\.junie\skills\"

# Clean up
Remove-Item -Recurse -Force $env:TEMP\junie-skills]]>
```
</tab>
</tabs>

>Junie modifies your code and executes scripts, so it's important to make sure that the skills it uses are safe.
>Treat third-party skills with the same caution as you would with any third-party code you add to your project:
>
>* Only use skills from sources you trust.
>* Read the `SKILL.md` file and all supporting files carefully.
>* Prefer pinning to a specific commit or tag rather than pulling from a branch that may change.
> 
{title="Always review skills from external sources before using them" style="warning"}

## Best practices

* Be specific and actionable and provide as many details as possible. A good example is: 
  
  ```markdown
  Use the AAA pattern (Arrange, Act, Assert). 
  One assertion concept per test. 
  Use fakes instead of mocking libraries.
  ```

* Include examples and show the exact patterns you want Junie to follow. 
Skills with code examples are significantly more effective. 

* Reference project files. Point Junie to existing code that exemplifies the desired patterns:

    ```markdown
    See `src/test/kotlin/com/example/MyServiceTest.kt` for a reference 
    test implementation.
    ```

* Keep it focused. Each skill should cover one domain or concern. Don't create a single monolithic skill that covers 
everything – create multiple focused skills instead.

* Use subdirectories for complex skills. If a skill has extensive documentation, break it into multiple files:
    - Main `SKILL.md` provides an overview and links to sub-documents.
  - `checklists/` for step-by-step verification lists.
  - `scripts/` for automation scripts Junie can execute.
  - `templates/` for boilerplate code Junie can use as starting points.

* Write a clear description. The `description` field is what Junie uses to decide whether a skill is relevant. 
Make it specific enough that Junie can match it to the right tasks.

## Troubleshooting

<procedure collapsible="true" default-state="collapsed" title="Junie not using a skill">

- Junie selects skills based on task relevance. If a skill isn't being used, it may not match the current task, 
or its description may be too vague or generic. Make sure the skill's `description` clearly communicates when it should be used.
- Try asking Junie to use a specific skill explicitly, for example: *Use the testing skill to write tests for this module.*
- Check for name conflicts: if a project-level and a user-level skills have the same name, the user-level skill will be skipped.
- Verify the [SKILL.md file format](#skill-md-format) is followed: proper YAML formatting (no tabs, correct indentation), 
the YAML frontmatter starts with `---`, contains `name` and `description` fields, and ends with `---`; 
values for both `name` and `description` fields are provided.
- Check file permissions and encoding (UTF-8) for file read errors.
</procedure>

## Example skill folder

Below is an example code review skill that contains the main `SKILL.md` file and a referenced checklist.

```
.junie/skills/code-review/
├── SKILL.md
└── checklists/
    └── kotlin.md
```

```Markdown
---
name: code-review
description: Provides guidelines and checklists for thorough Kotlin code reviews
---

# Code Review Skill

Use this skill when reviewing Kotlin code for quality, correctness, and maintainability.

## Review Priorities

1. **Correctness** — Does the code do what it's supposed to?
2. **Error Handling** — Are errors handled gracefully?
3. **Readability** — Is the code easy to understand?
4. **Performance** — Are there obvious performance issues?
5. **Testing** — Are there adequate tests?

## Kotlin-Specific Checks

- Prefer `val` over `var`
- Use data classes for value objects
- Prefer early returns over nested `if` blocks
- Use sealed classes for restricted hierarchies

## Detailed Checklist

See `checklists/kotlin.md` for a comprehensive review checklist.]]>
```
{collapsible="true" default-state="collapsed" collapsed-title=".junie/skills/code-review/SKILL.md"}

```Markdown
# Kotlin Code Review Checklist

## Naming
- [ ] Classes use PascalCase
- [ ] Functions and variables use camelCase
- [ ] Constants use SCREAMING_SNAKE_CASE

## Null Safety
- [ ] Avoid `!!` operator
- [ ] Use `?.let {}` or safe calls
- [ ] Nullable types are justified

## Error Handling
- [ ] Errors are handled gracefully
- [ ] Error propagation is clean and readable

## Testing
- [ ] New code has corresponding tests
- [ ] Edge cases are covered
- [ ] Tests follow AAA pattern]]>
```
{collapsible="true" default-state="collapsed" collapsed-title=".junie/skills/code-review/checklists/kotlin.md"}
