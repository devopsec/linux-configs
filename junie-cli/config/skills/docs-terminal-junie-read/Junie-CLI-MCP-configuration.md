<show-structure depth="3"/>

# Add and configure MCP servers

You can connect Junie CLI to external tools via Model Context Protocol (MCP).
Junie CLI uses the same MCP JSON configuration as
[Junie in JetBrains IDEs](Junie-IDE-plugin.md#mcp-configuration).

The `/mcp` slash command shows the [list of configured MCP servers](#list-configured-mcp-servers) and the
[MCP Installation Assistant](#mcp-installation-assistant) to guide you through
adding, editing, or troubleshooting configs for MCP servers.

[//]: # (TODO: differentiation between inactive and failed statuses is not clear)

## MCP Installation Assistant

Junie's MCP Installation Assistant is an AI helper that streamlines and simplifies the process of adding new MCP servers.
It guides you through adding MCP servers from a registry of pre-configured servers or from scratch.

When adding a server from the registry, Junie CLI automatically configures the correct command or URL and prompts the user for 
any required secrets or environment variables.

When adding a server from scratch, it searches the [official MCP registry](https://registry.modelcontextprotocol.io/)
for the proper server configuration, prompts for parameters, env variables, secrets, or API tokens if needed, adds the server
configuration to the `mcp.json` file, and verifies the server startup.

![](mcp_installation_assistant.png){width=680}

### Add an MCP server

1. Use the `/mcp` command to open the MCP server configuration screen.

2. Press `Ctrl+A` to open and search the list of pre-configured MCP servers. 

    If the MCP server you need is not on the list, press `Ctrl+A` once again and follow Installation Assistant's prompts 
to set up the server configuration from scratch.

3. Select the server installation scope:

    * *Project* — MCP server configs are stored in the `.junie/mcp/mcp.json` file at the root of your project. This file
      can be checked into version control and shared across all team members.
        > For project-scope installations, avoid sharing secrets or sensitive environment variables 
      > if the `.junie/mcp/mcp.json` file is committed to version control. 
      > {title="Warning"}

    * *User* — user-scope MCP configs are stored in `~/.junie/mcp/mcp.json` and available across all projects
      on your machine while remaining private to your user account.

4. Select the server connection type:

    * *Remote* — Connect to a hosted server via HTTP/HTTPS.

      Junie CLI connects to an MCP server hosted on a remote machine or service.

    * *Local* — Run on your machine (Docker, npx, or binary).

      Junie CLI starts an MCP server instance locally, e.g.
      using the `npx` command or via Docker.

### OAuth authorization

Remote MCP servers that require OAuth authorization are added to the list of configured servers with 
an **Authorization required** status. Use MCP Installation Assistant to set up OAuth authorization:

1. Select the server on the list to open its configuration menu.

2. Select **→ Authorize** and then follow the steps to login in the respective server's browser page that opens.

3. Verify that the server's status has changed to **Active**.

## Add an MCP server from JSON configuration

If you have a JSON configuration for an MCP server, you can add it manually directly to the `.junie/mcp/mcp.json` file 
at the project or user scope. 

The `mcp.json` file uses the following JSON structure:

```json
{
  "mcpServers": {
    "Context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp"],
      "env": {
        "ENV_VAR": "value"
      }
    },
    "RemoteServer": {
      "url": "https://mcp.example.com/v1",
      "headers": {
        "Authorization": "Bearer token"
      }
    }
  }
}
```
{collapsible="true" collapsed-title="mcp.json"}

Manually added configurations are imported to the list of MCP servers and enabled by default.
To verify that the server is available to Junie CLI and active, use the `/mcp` command.

## List configured MCP servers

To list all configured MCP servers, as well as disable/enable, modify,
or delete existing configurations, use the `/mcp` command. The list shows:

* MCP server name.
* Installation scope (project or user).
* Server status (Starting/Active/Inactive/Disabled/Failed/Authorization required).

> Servers that are neither *Active* nor *Disabled* can be either *Inactive* or *Failed*.
>
> The *Inactive* status indicates that the server is correctly configured and enabled but is not currently running.
>
> The *Failed* status indicates that an error occurred while attempting to connect to the server,
> the server cannot be started or crashes while running.
> This could be due to invalid configuration, authentication failure, missing dependencies, or server's runtime crash.
> {title="MCP server statuses"}

Configuration for MCP servers is stored in the `mcp.json` file at the following default locations:
* **Project scope**: `.junie/mcp/mcp.json` at the root of your project.
* **User scope**: `~/.junie/mcp/mcp.json` on your machine.

You can control where Junie searches for MCP configurations using the following command-line options:

| Option | Default | Description |
|---|---|---|
| `--mcp-default-locations` | `true` | Enable or disable adding MCP servers from default locations (per user / per project). |
| `--mcp-location <path>` | — | Additional folders where MCP servers should be found. Can be specified multiple times. |

## Enable or disable an MCP server

The MCP servers connected via MCP Installation Assistant or imported from the `mcp.json` file are enabled by default.

To disable a server, list all the configured servers with the `/mcp` command, select the necessary server,
and then select the **→ Disable** action. To enable a previously disabled server, use **→ Enable**.