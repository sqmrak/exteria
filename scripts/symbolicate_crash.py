#!/usr/bin/env python3
"""resolve exteria crash stacks against the executable from the same build."""

import argparse
import re
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", help="crash log copied from the device")
    parser.add_argument("binary", help="executable from the reported build")
    parser.add_argument("--arch", choices=("armv7", "arm64"), default="armv7")
    args = parser.parse_args()
    headers = subprocess.run(
        ["llvm-objdump", "--macho", "--private-headers", "--arch=" + args.arch, args.binary],
        check=True, capture_output=True, text=True,
    ).stdout
    match = re.search(r"\buuid\s+([0-9a-fA-F-]{36})", headers)
    if not match:
        raise ValueError("binary has no uuid for " + args.arch)
    uuid = match.group(1).replace("-", "").lower()
    current = None
    with open(args.log, encoding="utf-8", errors="replace") as log:
        for line in log:
            build = re.search(r"\bbuild\s+([0-9a-fA-F]{32})", line)
            if build:
                current = build.group(1).lower()
            print(line, end="")
            if not line.startswith("stack "):
                continue
            if current != uuid:
                print("  no symbols: build uuid does not match the binary")
                continue
            addresses = re.findall(r"0x[0-9a-fA-F]+", line)
            if not addresses:
                continue
            result = subprocess.run(
                ["llvm-addr2line", "--default-arch=" + args.arch, "-f", "-e", args.binary, *addresses],
                check=True, capture_output=True, text=True,
            ).stdout.splitlines()
            for index, address in enumerate(addresses):
                name, location = result[index * 2:index * 2 + 2]
                if name != "??":
                    print("  {} {} {}".format(address, name, location))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print("symbolication failed: {}".format(error), file=sys.stderr)
        sys.exit(1)
