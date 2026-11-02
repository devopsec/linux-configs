# Quickstart

<show-structure for="chapter,procedure" depth="3"/>

**Junie CLI** is the agentic coding tool by JetBrains that provides an interactive terminal interface for developers to 
review, write, and modify code.

<procedure title="Supported operating systems" id="supported-operating-systems">
Junie CLI is available on Linux, macOS, and Windows.
</procedure>

## Step 1: Install Junie CLI {level="3"}

In the terminal or command prompt of your choice, run:

<tabs>
    <tab title="Linux / macOS">
        <code-block lang="Console">curl -fsSL https://junie.jetbrains.com/install.sh | bash</code-block>
    </tab>
    <tab title="Windows">
        <code-block lang="PowerShell">powershell -NoProfile -ExecutionPolicy Bypass -Command "iex (irm 'https://junie.jetbrains.com/install.ps1')"</code-block>
    </tab>
    <tab title="Homebrew">
            <code-block lang="Console">
                brew tap jetbrains/junie
                brew update
                brew install junie
            </code-block>
            <p>
                To verify the installation:
            </p>
            <code-block lang="Console">
                junie --version
            </code-block>
    </tab>
</tabs>

[//]: # (EAP channel:)

[//]: # (<code-block lang="Console">curl -fsSL https://junie.jetbrains.com/install-eap.sh | bash</code-block>)

## Step 2: Start Junie in your project {level="3"}

Navigate to the root directory of the project where you want to use Junie CLI and run `junie`:

```console
cd /path/to/your/project
```

```sh
junie
```

## Step 3: Authenticate {level="3"}

On the Junie welcome screen, select one of the available authentication options:

* **Log in with your JetBrains Account**

    Use Junie CLI as part of your subscription plan with JetBrains. When selecting this option, you'll be redirected to 
the JetBrains Junie login page in your browser.

* **Use `JUNIE_API_KEY`** 

    Run Junie CLI with usage-based billing. When selecting this option, you'll be prompted to provide an access 
token. To generate your `JUNIE_API_KEY` access token, go to [junie.jetbrains.com/cli](https://junie.jetbrains.com/cli).

* **[Bring Your Own Key (BYOK)](BYOK.md)**

    Use your own API keys or OAuth tokens from Anthropic, OpenAI, Google, or other third-party LLM providers.
    Junie CLI uses these API keys to send requests to LLMs directly without requiring a JetBrains AI subscription.

    BYOK can be used on its own or together with JetBrains Account authorization or Junie API key.
    If a model is available through both the BYOK API key and JetBrains AI subscription, the requests are billed to your BYOK provider directly.

[//]: # (> By authenticating with Junie CLI, you agree to [Junie Terms of Service]&#40;https://junie.jetbrains.com/tos-eap&#41;.)

[//]: # (> {style="note"})

## Step 4: Type your prompt {level="3"} 

Type the prompt in the interactive CLI, for example:

```Console
> give me an overview of this codebase
```

Use `@` to attach a file or folder from the current project to the request context. 
To see the list of available slash commands and use them, type `/`.

[Learn more about using Junie in the terminal](Junie-CLI-usage.md)

## Non-interactive (headless) mode {level="3"}

You can run Junie CLI in headless mode, that is, programmatically without interactive UI, in CI/CD environments
and build pipelines. 

To add Junie to your CI/CD script:

```bash
# Install Junie CLI
curl -fsSL https://junie.jetbrains.com/install.sh | bash

# Authenticate and use Junie
junie --auth="$JUNIE_API_KEY" "Review and fix any code quality issues in the latest commit"
```
The `junie` command takes [options](Parameters.md) and [environment variables](Parameters.md#environment-variables). 

For more information and examples, see [Headless mode](Junie-headless.md).

## Other scenarios {level="3"}

* [Junie GitHub Action](Junie-on-GitHub.md)
* [Junie GitLab CI/CD](Junie-GitLab-CI-CD.md)