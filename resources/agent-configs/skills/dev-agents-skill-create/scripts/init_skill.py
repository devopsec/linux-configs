#!/usr/bin/env python3
"""
Skill Initializer - Creates a new skill from template.
Adapted for NumberSentry repo and Junie CLI.
"""

import argparse
import re
import sys
from pathlib import Path

# Naming convention segments as per current SKILL.md
FUNCTIONAL_AREAS = {"vcs", "dev", "docs", "sec", "gfx", "web", "misc", "infra"}
ACTIONS = {"create", "review", "merge", "read", "update", "manage", "maintain", "administer", "process"}

MAX_SKILL_NAME_LENGTH = 64
ALLOWED_RESOURCES = {"scripts", "references", "assets", "templates", "checklists"}

SKILL_TEMPLATE = """---
name: {skill_name}
description: "TODO: Provide a clear and concise trigger description. What task does this skill support? When should it be activated?"
---

# {skill_title}

## Overview

[TODO: 1-2 sentences explaining what this skill enables]

## Workflow

1. **[Step 1]** - Describe the first action
2. **[Step 2]** - Describe the next action

## Guidelines

- [Guideline 1]
- [Guideline 2]

## Examples

[Include code samples, patterns, or realistic user requests]
"""

AGENT_MD_TEMPLATE = """# {agent_name} Specifics for {skill_title}

## Context & Tuning
[TODO: Research and document how {agent_name} should specifically handle this skill. 
Consider {agent_name}'s architecture, available tools, and UI constraints.]

## Instructions Overrides
[TODO: Any instructions that differ from the main SKILL.md]

## Performance Notes
[TODO: Tips for improving {agent_name}'s performance with this skill]
"""

def normalize_skill_name(skill_name):
    """Normalize a skill name to lowercase hyphen-case."""
    normalized = skill_name.strip().lower()
    normalized = re.sub(r"[^a-z0-9]+", "-", normalized)
    normalized = normalized.strip("-")
    normalized = re.sub(r"-{2,}", "-", normalized)
    return normalized

def title_case_skill_name(skill_name):
    """Convert hyphenated skill name to Title Case for display."""
    return " ".join(word.capitalize() for word in skill_name.split("-"))

def validate_naming_convention(skill_name):
    """Checks if the skill name follows the project BNF."""
    parts = skill_name.split("-")
    if len(parts) < 4:
        return False, "Skill name must follow <AREA>-<PLATFORM>-<TARGET>-<ACTION> structure."
    area = parts[0]
    action = parts[-1]
    if area not in FUNCTIONAL_AREAS:
        print(f"Note: Functional area '{area}' is not in the common list: {sorted(FUNCTIONAL_AREAS)}")
    if action not in ACTIONS:
        print(f"Note: Action '{action}' is not in the common list: {sorted(ACTIONS)}")
    return True, ""

def create_resource_dirs(skill_dir, resources):
    for resource in resources:
        resource_dir = skill_dir / resource
        resource_dir.mkdir(exist_ok=True)
        print(f"[OK] Created {resource}/")

def init_skill(skill_name, path, resources, agents):
    """Initialize a new skill directory."""
    skill_dir = Path(path).resolve() / skill_name

    if skill_dir.exists():
        print(f"[ERROR] Skill directory already exists: {skill_dir}")
        return None

    try:
        skill_dir.mkdir(parents=True, exist_ok=False)
        print(f"[OK] Created skill directory: {skill_dir}")
    except Exception as e:
        print(f"[ERROR] Error creating directory: {e}")
        return None

    skill_title = title_case_skill_name(skill_name)
    skill_content = SKILL_TEMPLATE.format(skill_name=skill_name, skill_title=skill_title)

    skill_md_path = skill_dir / "SKILL.md"
    try:
        skill_md_path.write_text(skill_content)
        print("[OK] Created SKILL.md")
    except Exception as e:
        print(f"[ERROR] Error creating SKILL.md: {e}")
        return None

    # Create agent-specific markdown documentation
    if agents:
        agents_dir = skill_dir / "agents"
        agents_dir.mkdir(exist_ok=True)
        for agent in agents:
            agent_md = agents_dir / f"{agent}.md"
            agent_display = "Junie CLI" if agent.lower() == "junie" else agent.capitalize()
            agent_md.write_text(AGENT_MD_TEMPLATE.format(
                agent_name=agent_display, 
                skill_title=skill_title
            ))
            print(f"[OK] Created agents/{agent}.md (Markdown documentation)")

    if resources:
        create_resource_dirs(skill_dir, resources)

    print(f"\n[OK] Skill '{skill_name}' initialized successfully at {skill_dir}")
    print("\nNext steps:")
    print("1. Edit SKILL.md to complete the TODO items and update the trigger description.")
    print("2. Research and complete the agent-specific documentation in agents/ folder.")
    print("3. Add resources to scripts/, references/, and assets/ as needed.")
    print("4. Run the validator when ready to check the skill structure and safety:")
    print(f"   python3 .agents/skills/dev-agents-skill-create/scripts/validate.py {skill_dir}")
    
    print("\nIMPORTANT: Agent-specific documentation is now in Markdown.")
    print("You MUST perform due diligence and research agent-specific architecture and configurations.")
    return skill_dir

def main():
    parser = argparse.ArgumentParser(description="Create a new skill directory with a SKILL.md template.")
    parser.add_argument("skill_name", help="Skill name (normalized to hyphen-case)")
    parser.add_argument("--path", default=".agents/skills", help="Output directory for the skill")
    parser.add_argument("--resources", default="scripts,references", help="Comma-separated list of directories to create")
    parser.add_argument("--agents", default="junie,claude", help="Comma-separated list of agents to generate docs for")
    args = parser.parse_args()

    skill_name = normalize_skill_name(args.skill_name)
    if not skill_name:
        print("[ERROR] Invalid skill name.")
        sys.exit(1)
        
    valid, msg = validate_naming_convention(skill_name)
    if not valid:
        print(f"[WARNING] {msg}")

    resources = [r.strip() for r in args.resources.split(",") if r.strip()]
    agents = [a.strip() for a in args.agents.split(",") if a.strip()]

    result = init_skill(skill_name, args.path, resources, agents)
    if not result:
        sys.exit(1)

if __name__ == "__main__":
    main()
