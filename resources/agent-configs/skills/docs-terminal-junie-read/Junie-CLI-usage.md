# Using Junie in the terminal

<show-structure for="chapter" depth="2" />

Learn about working with Junie CLI in an interactive terminal interface.

## Prompting

With Junie CLI [installed and authenticated](Junie-CLI.md), navigate to the project directory where you want to use it.

1. Start an interactive session with Junie CLI.

    ```
    junie
    ```

2. Type your prompt in the natural language, for example:

    ```
    > find the files in this project that handle log error descriptions
    ```

[//]: # (Tabs are normalized to spaces: when you type or paste a tab character into the input field, it is converted to two spaces. )

[//]: # (This ensures consistent rendering and cursor alignment in the terminal. Practical effect:)

[//]: # (- Typing the Tab key inserts two spaces.)

[//]: # (- Pasting text that contains tabs &#40;for example, code snippets&#41; will have each tab replaced with two spaces.)
  
> For persistent guidance that Junie CLI will apply to all tasks, provide instructions in the `.junie/AGENTS.md` 
> file at the project's root directory. [Learn more](Guidelines-and-memory.md)

### Real-time follow-ups

You can type follow-up prompts while Junie CLI is working on the task without waiting for it to finish. 
The added clarifications are appended to the initial prompt and taken into account by the agent immediately.

### Reference files and directories

Use `@` to quickly reference files or directories in your prompt.

[//]: # (When you include file paths directly in the prompt using the `@<path>` syntax, the CLI now validates those paths and sends only the ones that actually exist on your machine.)

[//]: # ()
[//]: # (- Non-existent paths are ignored silently and are not attached to the request.)

[//]: # (- Existing paths are attached and will be available to Junie during task processing.)

[//]: # (- Use your OS-native path format &#40;the CLI checks paths using the local filesystem&#41;.)

![](reference_files_and_folders.png){width="706"}

You can also drag and drop files and images into the terminal window to reference them.

### Image inputs

Drag and drop or reference screenshots or design specs in the prompt for Junie CLI to read the image details. 
Junie CLI accepts all common image formats such as PNG and JPEG.

### Search the prompt history

Junie CLI preserves your prompt history across all sessions and application runs. 

To search the prompt history, use `Ctrl+R`, and then navigate through the results using Up and Down arrow keys.

## Slash commands and shortcuts

Slash commands allow you to access various Junie CLI features directly from the prompt.
Type `/` in the prompt to see and use the [available slash commands](Slash-commands.md).

In addition to the built-in commands, you can [add custom slash commands](Custom-slash-commands.md) for frequently used prompts and
repetitive tasks.

To see all available shortcuts, type `?`.

## Run shell commands

You can run shell commands without leaving Junie CLI by prefixing it with `!`, for example:

```
!ls -la
```

## Command approval

For running potentially sensitive actions, such as executing most of the terminal commands, 
editing files outside the project, or invoking MCP tools, Junie will ask for approval from the user.

### Action Allowlist

When Junie CLI stops for user approval, you can select the **→ Always allow** option to add 
the indicated command to the Action Allowlist. Once on the Action Allowlist, the command will always be executed 
without user approval in the future Junie runs.

![](action_allowlist_junie_cli.png){width="706"}

The full list of allowed commands and command patterns is stored in the `~/.junie/allowlist.json` file. You can also 
edit this file manually to add or remove allowed or restricted commands and patterns. For details, see 
[Action Allowlist configuration](Action-Allowlist-Junie-CLI.md).

### Brave mode

You can authorize Junie CLI to execute all potentially sensitive actions without user approval by enabling brave mode
with the `Ctrl+B` shortcut.

![](brave_mode_on.png){width="706"}

## Plan mode

In plan mode, Junie CLI analyzes the codebase with read-only operations and creates an implementation plan without
making any changes to the project files.

To toggle plan mode, use the `Shift+Tab` shortcut.   

![](plan_mode_enabled.png){width="706"}

Junie will suggest a plan and wait for the user input – either confirmation or rejection to proceed with the implementation.
If you reject the plan, provide follow-up instructions to continue:

![](reject_the_plan.png){width="706"}

[//]: # (## Terminal mode)

[//]: # (You can run shell commands directly within Junie to inspect your project or run tests:)

[//]: # (1. Type `!` followed by your command &#40;e.g., `!./gradlew test`&#41;.)

[//]: # (2. Junie will execute the command and display the output.)

[//]: # (3. You can also type `/terminal` to enter a persistent terminal session.)

## Manage your account

Use the `/account` command to manage your credentials and API keys:

* Select **Junie Account** to authenticate with Junie CLI via JetBrains Account or a Junie API key. 

  To generate a `JUNIE_API_KEY` access token, go to [junie.jetbrains.com/cli](https://junie.jetbrains.com/cli).

* Select **Bring Your Own Key (BYOK)** to add API keys for LLM providers like OpenAI, Anthropic, Google, or xAI.

    > BYOK can be used on its own or together with JetBrains Account authorization.
    > If a model is available through both the BYOK API key and JetBrains AI subscription, 
  > the requests are billed directly to the model provider without consuming credits from your JetBrains account.

## Manage your session

### Clear up session context

Use `/new` to clear up the context of the current session and start a new session in Junie CLI interactive mode.

### View session transcript

To access the full transcript of the current session, including all previous prompts and the agent output,
use the `Ctrl+T` shortcut.
When in the Transcript view, use `Ctrl+N` to load older entries, or `Esc` to return to the main view.

### Resume previous sessions

To see the session history and resume one of the previous sessions, use `/history`.

Junie CLI stores the full session context, including LLM usage data and the history of user prompts and agent responses, 
for the last 10 sessions.

### Quit the session

To exit the Junie CLI interactive mode without losing login credentials, use `/quit`.
Alternatively, you can exit Junie CLI by using `Ctrl+C` twice.

## Model selection

Use `/model` to select the LLM used for the current session. `Default` is the recommended
pre-selected option that uses a dynamically set model with the best price quality ratio.

The selection of available models depends on your [authentication method](Junie-CLI.md#step-3-authenticate) with Junie CLI. 
With BYOK, only the provider-specific models are available.

## Token usage and costs

The `/usage` command shows the cost breakdown for the current session, including token usage, used models, and remaining balance.

![](check_session_cost.png){width="706"}

## Extend Junie CLI

* [Model Context Protocol (MCP)](Junie-CLI-MCP-configuration.md)
* [](Agent-Skills.md)
* [Subagents](Junie-CLI-subagents.md)
* [](Custom-slash-commands.md)
* [Guidelines and memory](Guidelines-and-memory.md)
