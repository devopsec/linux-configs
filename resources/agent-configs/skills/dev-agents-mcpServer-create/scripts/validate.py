#!/usr/bin/env python3
"""
MCP Server Validator
Automates quality and safety checks for MCP server implementations.
"""

import sys
import os
import re
from pathlib import Path

def check_python_server(path: Path):
    issues = []
    content = path.read_text()
    
    # Check naming
    if not re.search(r'mcp\s*=\s*FastMCP\(["\']\w+_mcp["\']\)', content):
        issues.append("[WARNING] Server name might not follow the {service}_mcp convention in FastMCP initialization.")
    
    # Check for hardcoded keys
    if re.search(r'API_KEY\s*=\s*["\'][\w-]{10,}["\']', content):
        issues.append("[CRITICAL] Potential hardcoded API key detected!")
    
    # Check for dangerous patterns
    if "shell=True" in content:
        issues.append("[CRITICAL] Use of shell=True in subprocess calls is dangerous.")
    
    # Check tool annotations
    tools = re.findall(r'@mcp\.tool\(.*?\)', content, re.DOTALL)
    for tool in tools:
        if "destructiveHint" not in tool:
            issues.append(f"[WARNING] Tool decorator missing destructiveHint: {tool.strip()}")
        if "readOnlyHint" not in tool:
            issues.append(f"[WARNING] Tool decorator missing readOnlyHint: {tool.strip()}")

    return issues

def check_typescript_server(path: Path):
    issues = []
    content = path.read_text()
    
    # Check naming
    if not re.search(r'name:\s*["\']\w+-mcp-server["\']', content):
        issues.append("[WARNING] Server name might not follow the {service}-mcp-server convention.")
        
    # Check for hardcoded keys
    if re.search(r'apiKey\s*:\s*["\'][\w-]{10,}["\']', content, re.IGNORECASE):
        issues.append("[CRITICAL] Potential hardcoded API key detected!")

    # Check for deprecated APIs
    if "server.tool(" in content or "setRequestHandler" in content:
        issues.append("[WARNING] Use of deprecated MCP APIs detected. Use server.registerTool() instead.")

    # Check tool registration
    tools = re.findall(r'server\.registerTool\(.*?\)', content, re.DOTALL)
    for tool in tools:
        if "destructiveHint" not in tool:
            issues.append(f"[WARNING] Tool registration missing destructiveHint: {tool[:50]}...")
            
    return issues

def main():
    if len(sys.argv) < 2:
        print("Usage: python validate.py <path_to_server_file_or_dir>")
        sys.exit(1)
        
    target = Path(sys.argv[1])
    all_issues = []
    
    if target.is_file():
        files = [target]
    else:
        files = list(target.rglob("*.py")) + list(target.rglob("*.ts"))
        
    for f in files:
        print(f"Checking {f}...")
        if f.suffix == ".py":
            all_issues.extend(check_python_server(f))
        elif f.suffix == ".ts":
            all_issues.extend(check_typescript_server(f))
            
    if not all_issues:
        print("\n✅ No major issues found! MCP server follows basic standards.")
    else:
        print("\nFound the following issues:")
        for issue in all_issues:
            print(f"  {issue}")
            
    sys.exit(1 if any("[CRITICAL]" in i for i in all_issues) else 0)

if __name__ == "__main__":
    main()
