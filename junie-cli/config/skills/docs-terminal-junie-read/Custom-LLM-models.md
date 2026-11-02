# Custom LLMs

<primary-label ref="eap"/>

Junie CLI supports custom models defined via JSON profiles. This feature allows you to integrate with local providers 
(e.g., Ollama), enterprise proxies, or any LLM endpoint that follows the supported API formats.

> This feature is currently in the [Early Access program](Junie-CLI-EAP.md). To try it,
> [install the EAP build](Junie-CLI-EAP.md) of Junie CLI.

## Configuration

### Location and discovery

By default, custom models are discovered from JSON files located in:
- User-scope: `$JUNIE_HOME/models/*.json`.
- Project-scope: `.junie/models/*.json`.

The filename (without the `.json` extension) is used as the **profile identifier**.

You can control where Junie searches for custom models using the following command-line options:

| Option                                            | Default | Description                                                                              |
|---------------------------------------------------|---------|------------------------------------------------------------------------------------------|
| `--model-default-locations` | `true`  | Enable or disable adding custom models from default locations (per user / per project).  |
| `--model-location <path>`  | —       | Additional folders where custom models should be found. Can be specified multiple times. |
{width="800"}

You can also set these values in the `config.json` file. For details, see [Junie CLI configuration files](Junie-CLI-configuration.md).

### Profile structure

A custom model profile consists of a top-level configuration and two optional model roles:

1. **Top-level properties**: Serve as the default configuration (base URL, API key, API type, and extra headers) for the models in the profile.
2. **`primaryModel`**: The model used for main reasoning and code generation tasks.
3. **`fasterModel`**: The model used for internal helper tasks like summarizing context or classifying tasks.

If `primaryModel` or `fasterModel` is not explicitly defined, they inherit the top-level properties.

### Top-level parameters

These parameters appear at the root of the JSON profile and define the defaults shared by both model roles.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `id` | String | Yes | The model identifier as expected by the API endpoint (for example, `gpt-4o` or `qwen3-coder:latest`). |
| `baseUrl` | String | Yes | The full URL of the LLM API endpoint (for example, `http://localhost:11434/v1/responses`). |
| `apiType` | String | Yes | The API format to use when communicating with the endpoint. See [Supported API types](#supported-api-types) for the list of accepted values. |
| `apiKey` | String | No | The API key for authenticating with the endpoint. If omitted, requests are sent without an `Authorization` header. |
| `extraHeaders` | Object | No | A key-value map of additional HTTP headers to include in every request to the endpoint. |
| `temperature` | Number | No | The sampling temperature to use for requests. If omitted, the provider's default temperature is used. See [Temperature](#temperature). |
| `primaryModel` | Object | No | Role-specific overrides for the primary model. See [Role-specific parameters](#role-specific-parameters). |
| `fasterModel` | Object | No | Role-specific overrides for the faster model. See [Role-specific parameters](#role-specific-parameters). |

### Role-specific parameters

`primaryModel` and `fasterModel` accept the same set of parameters. Any parameter specified here overrides the corresponding top-level value for that model role. Omitted parameters fall back to the top-level defaults.

| Parameter | Type | Description |
|---|---|---|
| `id` | String | Override for the model identifier used for this role. |
| `baseUrl` | String | Override for the API endpoint URL used for this role. |
| `apiType` | String | Override for the API format used for this role. |
| `apiKey` | String | Override for the API key used for this role. |
| `extraHeaders` | Object | Additional headers for this role. Merged with (not replaced by) the top-level `extraHeaders`. |
| `temperature` | Number | Override for the sampling temperature used for this role. |

### Merging logic

Overrides in `primaryModel` or `fasterModel` are merged with the top-level defaults:
- **Simple fields** (`id`, `baseUrl`, `apiKey`, `apiType`, `temperature`) are replaced by the override value when present.
- **Headers** (`extraHeaders`) are merged: headers defined in the override are added to the top-level headers. If the same header key appears in both, the role-level value takes precedence.

### Supported API types {id="supported-api-types"}

The `apiType` field controls which request format Junie uses when calling the endpoint.

| Value | Description |
|---|---|
| `OpenAICompletion` | OpenAI Chat Completions API (`/v1/chat/completions`). Compatible with most self-hosted and third-party OpenAI-compatible endpoints. |
| `OpenAIResponses` | OpenAI Responses API (`/v1/responses`). Use this for endpoints that implement the newer Responses API format. |
| `Google` | Google Gemini API format. Use this for Google AI Studio or Vertex AI endpoints. |
| `Anthropic` | Anthropic Messages API format. Use this for Anthropic Claude endpoints. |

## Temperature {id="temperature"}

By default, Junie does not send a temperature value for custom models, allowing the provider to use its own default.
You can set a specific temperature at the top level (shared by both model roles) or override it per role.

Recommended temperature values vary by model. For example:

| Model | Recommended temperature |
|---|---|
| DeepSeek | 0 |
| Gemini | 1 |
| Kimi | 0.6–1 |
| GLM | 0.7 |
| Qwen | 0.6 |
| MiMo | 0.3 |

> Consult your model provider's documentation for the optimal temperature value.
> Setting temperature to 0 may cause looping behavior with some models.

## Example profiles

### Basic profile

Below is an example of a profile named `local-ollama.json`:

```json
{
  "baseUrl": "http://localhost:11434/v1/responses",
  "id": "qwen3-coder:latest",
  "apiType": "OpenAIResponses",
  "extraHeaders": {
    "X-Custom-Source": "Junie"
  },
  "fasterModel": {
    "id": "qwen2.5-coder:1.5b"
  }
}
```

In this example, the primary model will be `qwen3-coder:latest`, and the faster model will be `qwen2.5-coder:1.5b`. Both will use the same base URL, API type, and extra headers.

### Profile with temperature

Below is an example that sets a default temperature and overrides it for the primary model:

```json
{
  "baseUrl": "http://localhost:11434/v1/responses",
  "id": "qwen3-coder:latest",
  "apiType": "OpenAIResponses",
  "temperature": 0.6,
  "primaryModel": {
    "id": "qwen3-coder:latest",
    "temperature": 0.3
  },
  "fasterModel": {
    "id": "qwen2.5-coder:1.5b"
  }
}
```

In this example, the primary model uses temperature `0.3` (overridden), while the faster model inherits the top-level temperature `0.6`.

## Using custom models

Once a profile is created, you can select it using the `/model` command or the `--model` flag. Custom models are identified by a `custom:` prefix followed by the profile ID:

```bash
junie --model custom:local-ollama
```

In the interactive TUI, custom models appear in the model selection list after the built-in providers.
