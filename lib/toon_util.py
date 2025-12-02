#!/usr/bin/env python3
"""
TOON utility for The Council of Legends
Provides encode/decode between JSON and TOON formats

Usage:
  ./lib/toon_util.py encode <json_file> [output_file]  - Convert JSON to TOON
  ./lib/toon_util.py decode <toon_file> [output_file]  - Convert TOON to JSON
  ./lib/toon_util.py read <toon_file> [field]          - Read TOON file, optionally extract field
  ./lib/toon_util.py get <toon_file> <field>           - Get specific field value (for bash scripts)
"""

import sys
import json
import os

# Add venv to path if needed
venv_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), '.venv', 'lib')
for p in os.listdir(venv_path) if os.path.exists(venv_path) else []:
    site_packages = os.path.join(venv_path, p, 'site-packages')
    if os.path.exists(site_packages) and site_packages not in sys.path:
        sys.path.insert(0, site_packages)

from toon import encode as toon_encode, decode as toon_decode


def encode_file(json_path: str, output_path: str = None) -> str:
    """Convert JSON file to TOON format"""
    with open(json_path, 'r') as f:
        data = json.load(f)

    toon_str = toon_encode(data)

    if output_path:
        with open(output_path, 'w') as f:
            f.write(toon_str)
        return f"Wrote {output_path}"
    else:
        return toon_str


def decode_file(toon_path: str, output_path: str = None) -> str:
    """Convert TOON file to JSON format"""
    with open(toon_path, 'r') as f:
        toon_str = f.read()

    data = toon_decode(toon_str)
    json_str = json.dumps(data, indent=2)

    if output_path:
        with open(output_path, 'w') as f:
            f.write(json_str)
        return f"Wrote {output_path}"
    else:
        return json_str


def read_toon(toon_path: str, field: str = None) -> str:
    """Read TOON file and optionally extract a specific field"""
    with open(toon_path, 'r') as f:
        toon_str = f.read()

    data = toon_decode(toon_str)

    if field:
        # Support nested fields like "style.tone"
        parts = field.split('.')
        value = data
        for part in parts:
            if isinstance(value, dict):
                value = value.get(part)
            elif isinstance(value, list) and part.isdigit():
                value = value[int(part)]
            else:
                value = None
                break

        if isinstance(value, (dict, list)):
            return json.dumps(value)
        elif value is not None:
            return str(value)
        else:
            return ""
    else:
        return json.dumps(data, indent=2)


def get_field(toon_path: str, field: str) -> str:
    """Get a specific field value - optimized for bash script usage"""
    return read_toon(toon_path, field)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)

    command = sys.argv[1]

    if command == 'encode':
        json_path = sys.argv[2]
        output_path = sys.argv[3] if len(sys.argv) > 3 else None
        print(encode_file(json_path, output_path))

    elif command == 'decode':
        toon_path = sys.argv[2]
        output_path = sys.argv[3] if len(sys.argv) > 3 else None
        print(decode_file(toon_path, output_path))

    elif command == 'read':
        toon_path = sys.argv[2]
        field = sys.argv[3] if len(sys.argv) > 3 else None
        print(read_toon(toon_path, field))

    elif command == 'get':
        if len(sys.argv) < 4:
            print("Usage: toon_util.py get <toon_file> <field>", file=sys.stderr)
            sys.exit(1)
        toon_path = sys.argv[2]
        field = sys.argv[3]
        print(get_field(toon_path, field))

    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        print(__doc__)
        sys.exit(1)


if __name__ == '__main__':
    main()
