"""
Usage:
    uv run search_secrets.py [QUERY] [OPTIONS]

Options:
    -e, --exact              Perform an exact match on the label instead of a substring
    -a, --attribute KEY=VAL  Filter by a specific attribute (e.g., service=github)
    -s, --show-secret        Include the actual secret password/token in the JSON output

Examples:
    # Default substring search on label (secret values hidden by default)
    uv run search_secrets.py token

    # Substring search on label and reveal the secret value
    uv run search_secrets.py token --show-secret

    # Exact match on label
    uv run search_secrets.py "GitHub Token" --exact

    # Search strictly by a keyring attribute
    uv run search_secrets.py --attribute service=github

    # Combine label substring search and attribute filtering
    uv run search_secrets.py api --attribute service=aws

    # Pipe into jq to further filter results
    uv run search_secrets.py token | jq '.[] | {label: .label, user: .attributes.username, host: .attributes.host}'
"""

# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "secretstorage",
# ]
# ///

import argparse
import json
import sys
import secretstorage


def main():
    parser = argparse.ArgumentParser(description="Search and filter system keyring secrets.")
    parser.add_argument("query", nargs="?", help="Substring to search for in the secret label")
    parser.add_argument("-e", "--exact", action="store_true", help="Perform an exact match on the label")
    parser.add_argument("-a", "--attribute", help="Filter by attribute in KEY=VALUE format (e.g., service=github)")
    parser.add_argument("-s", "--show-secret", action="store_true", help="Include the plaintext secret value in output")
    
    args = parser.parse_args()

    # Validate that at least one search criterion is provided
    if not args.query and not args.attribute:
        print("Error: Please provide either a search query, an attribute filter, or both.", file=sys.stderr)
        parser.print_help(sys.stderr)
        sys.exit(1)

    # Parse attribute filter if provided
    attr_key, attr_val = None, None
    if args.attribute:
        if "=" not in args.attribute:
            print("Error: Attribute must be in KEY=VALUE format (e.g., service=github).", file=sys.stderr)
            sys.exit(1)
        attr_key, attr_val = args.attribute.split("=", 1)

    try:
        connection = secretstorage.dbus_init()
        collection = secretstorage.get_default_collection(connection)

        if collection.is_locked():
            print("Default collection is locked. Attempting to unlock...", file=sys.stderr)
            collection.unlock()

        results = []
        for item in collection.get_all_items():
            label = item.get_label() or ""
            attributes = item.get_attributes()

            # Filter by attribute if specified
            if attr_key:
                if attributes.get(attr_key) != attr_val:
                    continue

            # Filter by label query if specified
            if args.query:
                if args.exact:
                    if label != args.query:
                        continue
                else:
                    if args.query.lower() not in label.lower():
                        continue

            # Fetch secret value only if requested
            secret_value = None
            if args.show_secret:
                try:
                    secret_bytes = item.get_secret()
                    if secret_bytes:
                        secret_value = secret_bytes.decode("utf-8")
                except Exception:
                    pass

            entry = {
                "label": label,
                "attributes": attributes,
            }
            
            if args.show_secret:
                entry["secret"] = secret_value

            results.append(entry)

        print(json.dumps(results, indent=2))

    except Exception as e:
        print(f"Error connecting to Secret Service: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
