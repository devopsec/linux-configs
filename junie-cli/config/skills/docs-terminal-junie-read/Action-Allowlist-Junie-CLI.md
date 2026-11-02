# Add commands to Action Allowlist

If [brave mode](Junie-CLI-usage.md#brave-mode) is not explicitly enabled, Junie will ask for user approval before 
running terminal commands, MCP tools, and other [types of actions](Action-Allowlist.md#types-of-action-allowlist-rules) 
that are considered to be sensitive by the coding agent.

You can manually add or remove allowed commands by editing the `~/.junie/allowlist.json` file.

There are three types of actions that can be allowed with the `allowlist.json` file:

* `fileEditing` – Editing files outside the project directory where Junie CLI is launched; editing build scripts outside 
    or inside the project directory.
* `executables` – Running terminal commands, including execution of tests, running apps, or build actions.
* `mcpTools` – Usage of Model Context Protocol (MCP) tools.
* `readOutsideProject` – Reading files outside the current project directory where Junie CLI is launched.

An example `allowlist.json` file looks as follows:

```json
{
  "defaultBehavior": "ask",
  "allowReadonlyCommands": true,
  "rules": {
    "fileEditing": {
      "rules": [
        {
          "prefix": "src/main/kotlin/", // The path is relative to the current project directory. For absolute paths, start with `/`.
          "action": "allow"
        }
      ]
    },
    "executables": {
      "rules": [
        {
          "prefix": "git",
          "action": "allow"
        },
        {
          "pattern": "grep **",
          "action": "allow"
        },
        {
          "pattern": "npm [iur]*",
          "action": "ask"
        }
      ]
    },
    "mcpTools": {
      "rules": [
        {
          "prefix": "github-server:",
          "action": "allow"
        }
      ]
    },
    "readOutsideProject": {
      "rules": [
        { 
          "pattern": "/etc/**", 
          "action": "ask"
        }
      ]
    }
  }
}
```

Each rule must specify either a `prefix` or a `pattern`, along with an `action` (`allow` or `ask`).
Select the appropriate action type and edit its `rules` array:

| Field     | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
|-----------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `prefix`  | Set a literal string to match all commands that start with it. <br><br>For example, indicating a `git` prefix allows all `git` commands (`git status`, `git commit`, `git push`, etc.)                                                                                                                                                                                                                                                                                                                                                      |
| `pattern` | Set a pattern using wildcard characters (Glob syntax): <list><li>`*` – Matches zero or more arbitrary characters, except for the path separator `/`.</li><li>`**` – Matches zero or more arbitrary characters, including the path separator `/`.</li><li>`?` – Matches exactly one arbitrary character, except for the path separator `/`.</li><li>`[abc]` – Matches any single character from the characters listed in brackets.</li><li>`[!abc]` – Matches any single character except for the characters listed in brackets.</li></list> |
| `action`  | The action to take for the command. Possible values: <list><li>`allow` – Execute automatically without user approval.</li><li>`ask`– Prompt for user approval before execution.</li></list>                                                                                                                                                                                                                                                                                                                                                 |
{width=800}

Rules are evaluated top to bottom, with the first match taking precedence. Thus, in the following example, `npm install`
will ask for permission, but `npm test` will be allowed automatically:

```json
{                                                                                                                                                                                                             
     "rules": [                                                                                                                                                                                                  
       {                                                                                                                                                                                                         
         "pattern": "npm install *",                                                                                                                                                                              
         "action": "ask"                                                                                                                                                                                         
       },                                                                                                                                                                                                        
       {                                                                                                                                                                                                         
         "prefix": "npm",                                                                                                                                                                                        
         "action": "allow"                                                                                                                                                                                       
       }                                                                                                                                                                                                         
     ]                                                                                                                                                                                                           
   }
```