import os
import re
import sys

# Pfad über Argument oder Standardwert
if len(sys.argv) < 2:
    print("Please provide the path to the Linux source code as an argument.")
    print("➡️  Example: python3 strip_help_blocks.py /home/input/linux")
    sys.exit(1)

srctree = sys.argv[1]

def should_stop(line):
    return re.match(r'^\s*(config|menu|choice|end(menu|choice)?|source|if|endif|comment|mainmenu|select|default|depends|prompt|bool|tristate|int|hex|string|menuconfig)', line)

def clean_kconfig_file(filepath):
    with open(filepath, 'r') as f:
        lines = f.readlines()

    cleaned = []
    skip = False

    for line in lines:
        if re.match(r'^\s*(help|---help---)\s*$', line):
            skip = True
            continue

        if skip:
            if should_stop(line):
                skip = False
                cleaned.append(line)
            continue

        cleaned.append(line)

    with open(filepath, 'w') as f:
        f.writelines(cleaned)

for root, _, files in os.walk(srctree):
    for name in files:
        if name == "Kconfig":
            path = os.path.join(root, name)
            print(f"🧹 Bereinige: {path}")
            clean_kconfig_file(path)

