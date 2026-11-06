"""
Usage:
    uv run list_secrets.py [OPTIONS]

Options:
    -s, --show-secret        Include the actual secret password/token in the JSON output

Examples:
    # List all secrets (secret values hidden by default)
    uv run list_secrets.py

    # List all secrets and reveal their plaintext values
    uv run list_secrets.py --show-secret

    # Pipe into jq to further filter results
    uv run list_secrets.py | jq '.[] | select(.attributes.service == "github")'
    uv run list_secrets.py | jq '.[] | {label: .label, user: .attributes.username}'
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
    parser = argparse.ArgumentParser(description="List all system keyring secrets.")
    parser.add_argument("-s", "--show-secret", action="store_true", help="Include the plaintext secret value in output")

    args = parser.parse_args()

    try:
        # Connect to the D-Bus Secret Service session
        connection = secretstorage.dbus_init()
        collection = secretstorage.get_default_collection(connection)

        if collection.is_locked():
            print("Default collection is locked. Attempting to unlock...", file=sys.stderr)
            collection.unlock()

        results = []
        for item in collection.get_all_items():
            label = item.get_label() or ""
            attributes = item.get_attributes()

            # Fetch secret value only if requested via --show-secret
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

        # Output as clean JSON
        print(json.dumps(results, indent=2))

    except Exception as e:
        print(f"Error connecting to Secret Service: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
