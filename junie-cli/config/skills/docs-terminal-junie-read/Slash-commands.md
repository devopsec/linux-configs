# Reference

Complete reference for the slash commands (`/`) and shortcuts available in Junie CLI (interactive mode).

## Built-in slash commands

| Command                  | Description                                                                                                                                                                                                                                                     |
|--------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `/account`               | Manage your Junie Accounts and Junie API keys, or connect your own API key from Anthropic, OpenAI, and other OpenAI API-compatible providers.                                                                                                                   | 
| `/commands`              | Create and manage custom slash commands.                                                                                                                                                                                                                        |
| `/feedback`              | Share feedback about the current session with the Junie team. <tip>A ZIP file with the current session logs is automatically attached to the submitted feedback response. </tip>                                                                                |
| `/history`               | See the session history and resume one of the previous sessions.                                                                                                                                                                                                |
| `/ide`                   | Show the current JetBrains IDE connection status and the JetBrains IDE features available to the current session. For details, see [Junie CLI and JetBrains IDE integration](Junie-CLI-JetBrains-IDE-integration.md).                                  |
| `/install-github-action` | Launch an interactive wizard for installing and configuring [Junie GitHub Action](Junie-on-GitHub.md) in the current GitHub repository.                                                                                                                         |
| `/import`                | Import user- or project-level configs from other coding agents. <br><br>Junie CLI detects and suggests import of guidelines, agent skills, slash commands, or MCP server configurations from other coding agents like Claude Code, Codex, or Cursor.            |
| `/mcp`                   | Connect MCP servers to Junie CLI and manage the connections.                                                                                                                                                                                                    |
| `/model`                 | Select the main Large Language Model (LLM) to be used by Junie. <br><br>`Default` is the recommended pre-selected option with the best price quality ratio. The model behind the `Default` option is set dynamically and may change as new models are released. |
| `/new`                   | Clear up the context and start a new session.                                                                                                                                                                                                                   |
| `/theme`                 | Select the application theme.                                                                                                                                                                                                                                   |
| `/quit`                  | Exit Junie CLI interactive mode while staying logged in.                                                                                                                                                                                                        |
| `/update`                | Check for updates and install if available.                                                                                                                                                                                                                     |
| `/usage`                 | See the cost breakdown for the current session, including token usage and used models.                                                                                                                                                                          |
{width="800"}

You can also add your own slash commands to Junie CLI. For details, see [Custom slash commands](Custom-slash-commands.md).

## Navigation

| Shortcut       | Description                                                             |
|----------------|-------------------------------------------------------------------------|
| `Ctrl+C` twice | Quit Junie CLI interactive mode.                                        |
| `!`            | Run a shell command in the embedded terminal. Example: `!ls`.           |
| `@`            | Search for a file or folder in your project to attach it to the prompt. |
| `/`            | Open the slash command suggestion menu.                                 |
| `?`            | Open the help menu to see all available shortcuts.                      |


## Modes and features

| Shortcut    | Description                                                                                   |
|-------------|-----------------------------------------------------------------------------------------------|
| `Shift+Tab` | Toggle between default mode and [plan mode](Junie-CLI-usage.md#plan-mode).                    |
| `Ctrl+B`    | Enable [brave mode](Junie-CLI-usage.md#brave-mode).                                           |
| `Ctrl+R`    | Search the prompt history.                                                                    |
| `Ctrl+T`    | Open the full transcript of the current session.                                              |
| `Ctrl+N`    | Navigate the transcript of the current session after opening it (`Ctrl+T`).                   |

## Text editing

| Shortcut                    | Description                           |
|-----------------------------|---------------------------------------|
| `Shift+Enter` (or `Ctrl+J`) | Insert a new line in the prompt.      |
| `Ctrl+A`                    | Move cursor to the start of the line. |
| `Ctrl+E`                    | Move cursor to the end of the line.   |
| `Alt+B`                     | Move cursor one word backward.        |
| `Alt+F`                     | Move cursor one word forward.         |
| `Ctrl+U`                    | Delete the entire line.               |
| `Ctrl+W`                    | Delete the word before the cursor.    |



