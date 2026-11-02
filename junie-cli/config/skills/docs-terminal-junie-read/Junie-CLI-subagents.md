# Custom subagents

<show-structure for="chapter" depth="3" />

Subagents in Junie extend the built-in logic of the main agent with task-specific instructions that define a tailored system 
prompt, tool restrictions, and usage of models and [agent skills](Agent-Skills.md).

When Junie CLI runs across a task that matches a subagent’s name and description, it delegates this task to that subagent. 
The subagent then works independently in its own context and returns the result to the main agent.

This page describes the [benefits of using custom subagents](#why-subagents), 
[how custom subagents are invoked](#how-junie-cli-uses-subagents), 
[adding your own subagents](#creating-a-custom-subagent) to Junie CLI, and what [built-in tools](#supported-tool-groups) 
are supported.

## Why subagents?

With subagents, Junie CLI can extend the capabilities to the main agent by delegating tasks to the most appropriate handler 
based on the nature of the request. Subagents let you:

* **Break down complex tasks** into focused, single-purpose chunks that the main agent can delegate 
while keeping the subagent's context out of the main conversation.
* **Tailor and reuse agent's behaviour for specific tasks** by defining coding standards, checklists, procedures, or 
agent skills to invoke and reusing these instructions across projects.
* **Optimize performance and costs** by using lightweight models for simple repetitive tasks, or predefined models for
    specific types of tasks.
* **Enforce tool restrictions** for specific types of tasks, such as restricting the agent to read-only operations 
for security auditing and reviews.

## How Junie CLI uses subagents

Junie CLI invokes subagents *automatically*, informing the user which subagent has started 
working on the task.

The main agent discovers all available subagents, selects the relevant subagent by matching its [`name` and `description`](#frontmatter-fields) to the task at hand, 
runs it as a subtask, and brings the result back into the main session.

> Unlike [custom slash commands](Custom-slash-commands.md), custom subagents cannot be invoked manually 
> via slash commands. They are only called automatically through delegation.

> If your project already has agent files from other tools (`.cursor/agents/`, `.claude/agents/`, or `.codex/agents/`),
> Junie CLI detects such files when opening the project and suggests importing them into Junie's `.junie/agents/` 
> directory automatically.
{title="Agent import"}

## Creating a custom subagent

Subagents are Markdown files with YAML metadata stored in the `.junie/agents/` or `.agents/` directory. For example, a simple 
subagent file for a changelog assistant (`.junie/agents/changelog.md`) looks as follows:

```yaml
---
name: "changelog"
description: "Write a changelog entry for a PR"
---

You are a changelog assistant.

Given the PR title and description, produce a short changelog entry.
```

### File location

Junie CLI looks for custom subagent `*.md` files in the following locations:

* *Project scope:* `<projectRoot>/.junie/agents/`.
* *Project scope:* `<projectRoot>/.agents/`.
* *User scope:* `~/.junie/agents/` on macOS/Linux or `%\USERPROFILE%\.junie\agents\` on Windows.
* *User scope:* `~/.agents/` on macOS/Linux or `%\USERPROFILE%\.agents\` on Windows.

### File format

Subagent files use YAML frontmatter for metadata, followed by the prompt body in Markdown for the system prompt. 

An example subagent file that uses the commonly used supported frontmatter fields looks as follows:

```markdown
---
description: "Review a change and propose a safe patch"
name: "code-review-helper"
tools: ["Read", "Grep", "Edit"]
disallowedTools: ["Bash", "WebSearch"]
model: "sonnet"
reasoningLevel: "high"
skills: ["kotlin", "writerside"]
allowPromptArgument: true
---

You are a careful code reviewer.

Context:

- File: $path
- Focus area: $focus

Tasks:

1) Explain the issue concisely.
2) Propose a minimal fix.
3) If edits are needed, prepare a small patch.

If you need additional context, ask for it.
```

#### Frontmatter fields

| Field             | Type           | Required | Notes                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
|-------------------|----------------|----------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `name`            | `String`       | no       | The subagent name. If missing, the file name (without extension) is used. <br><br>Must match: `[a-z][a-z0-9-]*` (lowercase letters, digits, hyphens).                                                                                                                                                                                                                                                                                                                   |
| `description`     | `String`       | yes      | The subagent description. Used by the main agent to decide when to delegate a task to this subagent.                                                                                                                                                                                                                                                                                                                                                                    |
| `tools`           | `List<String>` | no       | If present and non-empty: an allowlist of [tool groups](#supported-tool-groups).                                                                                                                                                                                                                                                                                                                                                                                        |
| `disallowedTools` | `List<String>` | no       | A denylist of [tool groups](#supported-tool-groups). Applied after the `tools` filtering.                                                                                                                                                                                                                                                                                                                                                                               |
| `model`           | `String`       | no       | Model override for this subagent run (if supported by your environment). Accepted values depend on your environment; to see the model names currently available in your setup, start Junie and use `/model`, or use a name accepted by the `--model` CLI flag. Some builds also support aliases like `sonnet`, `opus`, `grok`, and custom model profile IDs in the `custom:<profile-id>` format. For more details, see [Model selection](Junie-CLI-Model-selection.md). |
| `reasoningLevel`  | `String`       | no       | Optional reasoning override for this subagent run. In most cases, use values such as `low`, `medium`, or `high`, but supported values can vary by model, so check the model's own documentation if in doubt. Junie maps the selected level to the provider-specific reasoning field for the effective model, including compatible custom model profiles.                                                                 |
| `skills`          | `List<String>` | no       | IDs/names of agent skills to load for the subagent worker (if supported by your environment).                                                                                                                                                                                                                                                                                                                                                                           |
| `allowPromptArgument` | `Boolean`  | no       | If `true`, Junie exposes an additional `$prompt` argument to the subagent prompt. When `$prompt` is not referenced explicitly in the prompt body, the delegated user request is appended automatically as `User Input: ...`.                                                                                                                                                                                                                                       |

#### Prompt body

In the prompt body, provide the set of instructions to guide the subagent’s behavior. This prompt will be added to the 
instructions delegated from the main agent.

#### Tips 

* Make delegated work items as independent as possible.
* Ask for specific outputs (for example, “return file paths and the exact symbol names”).
* If you want to keep changes small, say so (“no refactors”, “touch at most one module”, “prefer config-only fix”).

## Supported tool groups

Custom subagents can define which tool groups are allowed (`tools`) or forbidden (`disallowedTools`) during task execution. 

If the `tools` field in the YAML frontmatter is present and non-empty, **only the specified groups are allowed**,
with the rest being banned by default. There's no need to disallow them explicitly using the `disallowedTools` field. 

There are two types of tools that can be either allowed or banned:

* **Built-in tool groups**.
* **Tools provided by MCP servers** (if available in your environment).

The built-in tool group labels are:

| Built-in tool group label | What it enables                                         |                               
|---------------------------|---------------------------------------------------------|
| `Read`                    | Read-only file viewing actions (open/scroll).           |
| `Bash`                    | Running shell commands in the local environment.        |
| `Glob`                    | Searching for files by path pattern (`glob`).           |
| `Grep`                    | Searching for text by regular expression (`grep`).      |
| `Write`                   | Creating new files.                                     |
| `Edit`                    | Modifying existing files (search/replace, apply patch). | 
| `WebSearch`               | Searching the web for up-to-date information.           | 
| `AskUserQuestion`         | Asking the user for input or a choice.                  |

Example of a read-only subagent allowed to search for a text by regular expression:

```yaml
---
name: "symbol-finder"
description: "Find where a symbol is used and summarize"
tools: [ "Read", "Grep" ]
---
```