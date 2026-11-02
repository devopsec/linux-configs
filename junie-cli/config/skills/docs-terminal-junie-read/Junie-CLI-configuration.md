# Junie CLI configuration files

Junie CLI can load settings from JSON configuration files in addition to command-line flags and environment variables.
Configuration files are useful when you want to keep shared project defaults in the repository or define personal defaults once for all projects.

## Default configuration locations

By default, Junie CLI looks for `config.json` in these locations:

* **User scope**: `~/.junie/config.json`
* **Project scope**: `<project-root>/.junie/config.json`

The project-level configuration is intended for settings that should be shared with the whole team.
The user-level configuration is intended for personal defaults on your machine.

## Configuration precedence

When the same setting is defined in multiple places, Junie resolves it in this order
(highest priority first):

1. Command-line flags
2. User settings from `~/.junie/settings.json`
3. Project configuration from `<project-root>/.junie/config.json`
4. User configuration from `~/.junie/config.json`

For example, if `~/.junie/config.json` sets `"model": "sonnet"`, the project config sets `"model": "gpt"`,
and you run `junie --model opus`, the effective model is `opus`.

## Add extra configuration files

To load additional configuration files, use `--config-location`.
You can specify it multiple times:

```bash
junie \
  --config-location /opt/company/junie/config.json \
  --config-location ./configs/junie.local.json
```

To disable loading from the default user and project locations, use `--config-default-locations false`.

For CI, you can use the equivalent environment variables:

| Environment variable | CLI equivalent | Description |
|---|---|---|
| <code-block>JUNIE_CONFIG_LOCATION</code-block> | <code-block>--config-location</code-block> | Additional configuration file paths. Can be specified multiple times. |
| <code-block>JUNIE_CONFIG_DEFAULT_LOCATIONS</code-block> | <code-block>--config-default-locations</code-block> | Enable or disable loading `config.json` from the default user and project locations. Defaults to `true`. |

## Supported configuration fields

The following JSON fields are currently supported in `config.json`:

| Field | Description |
|---|---|
| `model` | Default model to use. For supported built-in model IDs and custom model profiles, see [Model selection](Junie-CLI-Model-selection.md) and [Custom LLM models](Custom-LLM-models.md). |
| `provider` | Default BYOK provider. For supported provider values, see [LLM providers](Junie-CLI-Model-selection.md#llm-providers). |
| `brave` | Enables brave mode by default. |
| `flags` | Additional feature flags. |
| `mcp-locations` | Extra folders where Junie should search for MCP configurations. |
| `mcp-default-locations` | Enable or disable the default MCP locations. |
| `skill-locations` | Extra folders where Junie should search for agent skills. |
| `skill-default-locations` | Enable or disable the default skill locations. |
| `command-locations` | Extra folders where Junie should search for custom slash commands. |
| `command-default-locations` | Enable or disable the default custom slash command locations. |
| `agent-locations` | Extra folders where Junie should search for custom agents. |
| `agent-default-location` | Enable or disable the default custom agent locations. |
| `model-locations` | Extra folders where Junie should search for custom model profiles. |
| `model-default-locations` | Enable or disable the default model locations. |
| `auto-update` | Enable or disable automatic update checks. |
| `guidelines-location` | Path to the guidelines file Junie should use. |
| `time-limit` | Default task time limit. |
| `byok` | Default BYOK API keys for supported providers. |
| `proxies` | Custom proxy endpoints for routing LLM traffic. See [Custom proxies](Custom-proxies.md). |

Relative paths in `config.json` are resolved relative to the folder that contains that configuration file.

## Example configuration file

```json
{
  "model": "sonnet",
  "provider": "anthropic",
  "brave": false,
  "flags": ["copilot"],
  "mcp-locations": ["./mcp", "./shared/mcp"],
  "mcp-default-locations": true,
  "skill-locations": ["./skills"],
  "skill-default-locations": true,
  "command-locations": ["./commands"],
  "command-default-locations": true,
  "agent-locations": ["./agents"],
  "agent-default-location": true,
  "model-locations": ["./models"],
  "model-default-locations": true,
  "auto-update": true,
  "guidelines-location": "./team-guidelines.md",
  "time-limit": 3600,
  "byok": {
    "anthropic": "sk-ant-...",
    "openai": "sk-..."
  },
  "proxies": [
    {
      "name": "my-proxy",
      "kind": "Ingrazzio",
      "api-url": "https://my-ingrazzio-instance.example.com",
      "headers": ["X-Custom-Header: value"]
    }
  ]
}
```

## How configuration combines with other features

Configuration files control discovery for several other Junie CLI features:

* [MCP configuration](Junie-CLI-MCP-configuration.md)
* [Agent skills](Agent-Skills.md)
* [Custom slash commands](Custom-slash-commands.md)
* [Custom LLM models](Custom-LLM-models.md)
* [Guidelines and memory](Guidelines-and-memory.md)
* [Custom proxies](Custom-proxies.md)

For the exact command-line flags, see [CLI reference](Parameters.md).