#!/bin/bash

# Path to the directory containing the UVL and unconstrained feature files
UVL_DIR="./linux/kclause"
# Path to the linux source tree
LINUX_SRC_DIR="."

# Ensure you're in the Linux source directory
cd "$LINUX_SRC_DIR" || { echo "Linux source directory not found!"; exit 1; }

# Loop through all .uvl files in the UVL directory
for uvl_file in "$UVL_DIR"/*[^hierarchy].uvl; do
    # Extract the version from the UVL filename (e.g., v2.6.24[x86].uvl -> v2.6.24)
    version=$(basename "$uvl_file" | sed -E 's/\[.*\]//; s/.uvl//')

    # Extract the architecture from the UVL filename (e.g., v2.6.24[x86].uvl -> x86)
    architecture=$(basename "$uvl_file" | sed -E 's/.*\[(.*)\].*/\1/')

    # Check out the corresponding Linux version using git
    git checkout -f "$version" || { echo "Failed to checkout version $version"; exit 1; }

    # Apply the Makefile patch
    wget -qO- https://raw.githubusercontent.com/ulfalizer/Kconfiglib/master/makefile.patch | patch -p1 || {
        echo "Failed to apply makefile patch"; exit 1;
    }
    echo "Makefile patch applied for version $version"

    # Extract the major version number (e.g., 2 from v2.6.24)
    major_version=$(echo "$version" | cut -d '.' -f 1 | sed 's/v//')

    if [[ "major_version" -lt 3 ]]; then
        sed -i '/^PHONY/a Kconfig := arch/$(SRCARCH)/Kconfig' scripts/kconfig/Makefile
    fi

    # If the major version is 6, delete line 4 from kernel/module/Kconfig
    if [[ "$major_version" -eq 6 ]]; then
        KCONFIG_FILE="$LINUX_SRC_DIR/kernel/module/Kconfig"
        if [[ -f "$KCONFIG_FILE" ]]; then
            sed -i 's/modules//g' "$KCONFIG_FILE" || { echo "Failed to delete 'modules' from $KCONFIG_FILE"; exit 1; }
            echo "Deleted 'modules' from $KCONFIG_FILE for version $version"
        else
            echo "Kconfig file not found at $KCONFIG_FILE for version $version"
            exit 1
        fi
    else
        KCONFIG_FILE="$LINUX_SRC_DIR/init/Kconfig"
        if [[ -f "$KCONFIG_FILE" ]]; then
            sed -E -i 's/^\s*(option\s+)?modules\s*$//g' "$KCONFIG_FILE" || { echo "Failed to delete 'modules' from $KCONFIG_FILE"; exit 1; }
            echo "Deleted 'modules' from $KCONFIG_FILE for version $version"
        else
            echo "Kconfig file not found at $KCONFIG_FILE for version $version"
            exit 1
        fi
        sed -i  's/;//g' "drivers/hwmon/Kconfig" #v2.6.26 - v2.6.36 11
        if [ "$version" = "v2.5.45" ]; then
            sed -i 's/TOPDIR/CURDIR/g' "scripts/kconfig/Makefile"
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
        fi
        if [ "$version" = "v2.5.46" ]; then
            sed -i 's/TOPDIR/CURDIR/g' "scripts/kconfig/Makefile"
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
        fi
        if [ "$version" = "v2.5.47" ]; then
            sed -i 's/TOPDIR/CURDIR/g' "scripts/kconfig/Makefile"
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
        fi
        if [ "$version" = "v2.5.48" ]; then
            sed -i 's/TOPDIR/CURDIR/g' "scripts/kconfig/Makefile"
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
        fi
        if [ "$version" = "v2.5.49" ]; then
            sed -i 's/TOPDIR/CURDIR/g' "scripts/kconfig/Makefile"
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
        fi
        if [ "$version" = "v2.5.50" ]; then
            sed -i 's/TOPDIR/CURDIR/g' "scripts/kconfig/Makefile"
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
        fi
        if [ "$version" = "v2.5.51" ]; then
            sed -i 's/TOPDIR/CURDIR/g' "scripts/kconfig/Makefile"
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
        fi

        if [ "$version" = "v2.5.52" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
        fi
        if [ "$version" = "v2.5.53" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
        fi
        if [ "$version" = "v2.5.54" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
        fi
        if [ "$version" = "v2.5.55" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
        fi
        if [ "$version" = "v2.5.56" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
        fi
        if [ "$version" = "v2.5.57" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
        fi
        if [ "$version" = "v2.5.58" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
            sed -i '9d' "drivers/char/Kconfig" #requires INPUT=y
        fi
        if [ "$version" = "v2.5.59" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
            sed -i '9d' "drivers/char/Kconfig"
        fi
        if [ "$version" = "v2.5.60" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
            sed -i '9d' "drivers/char/Kconfig"
        fi
        if [ "$version" = "v2.5.61" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
            sed -i '9d' "drivers/char/Kconfig"
        fi
        if [ "$version" = "v2.5.62" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
            sed -i '9d' "drivers/char/Kconfig"
        fi
        if [ "$version" = "v2.5.63" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
            sed -i '9d' "drivers/char/Kconfig"
        fi
        if [ "$version" = "v2.5.64" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
            sed -i '9d' "drivers/char/Kconfig"
        fi
        if [ "$version" = "v2.5.65" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
            sed -i '26d; 58d' "scripts/kconfig/Makefile"
            sed -i '9d' "drivers/char/Kconfig"
        fi
        if [ "$version" = "v2.5.66" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
            sed -i '26d; 58d' "scripts/kconfig/Makefile"
            sed -i '9d' "drivers/char/Kconfig"
        fi
        if [ "$version" = "v2.5.67" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
            sed -i '26d; 58d' "scripts/kconfig/Makefile"
            sed -i '9d' "drivers/char/Kconfig"
        fi
        if [ "$version" = "v2.5.68" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
            sed -i '26d; 58d' "scripts/kconfig/Makefile"
            sed -i '9d' "drivers/char/Kconfig"
        fi
        if [ "$version" = "v2.5.69" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
            sed -i '26d; 58d' "scripts/kconfig/Makefile"
            sed -i '9d' "drivers/char/Kconfig"
        fi
        if [ "$version" = "v2.5.70" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
            sed -i '26d; 58d' "scripts/kconfig/Makefile"
            sed -i '9d' "drivers/char/Kconfig"
        fi
        if [ "$version" = "v2.5.71" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
            sed -i '26d; 58d' "scripts/kconfig/Makefile"
            sed -i '9d' "drivers/char/Kconfig"
        fi
        if [ "$version" = "v2.5.72" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
            sed -i '26d; 58d' "scripts/kconfig/Makefile"
            sed -i '9d' "drivers/char/Kconfig"
        fi
        if [ "$version" = "v2.5.73" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
            sed -i '26d; 58d' "scripts/kconfig/Makefile"
            sed -i '9d' "drivers/char/Kconfig"
        fi
        if [ "$version" = "v2.5.74" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
            sed -i '26d; 58d' "scripts/kconfig/Makefile"
            sed -i '9d' "drivers/char/Kconfig"
        fi
        if [ "$version" = "v2.5.75" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
            sed -i '26d; 58d' "scripts/kconfig/Makefile"
            sed -i '9d' "drivers/char/Kconfig"
        fi
        if [ "$version" = "v2.6.0" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
            sed -i '273d; 274d' "drivers/net/wireless/Kconfig"
            sed -i '433s/\bdepends\b/& on/' "drivers/serial/Kconfig"
            sed -i '877s/\bdepends\b/& on/' "fs/Kconfig"
        fi
        if [ "$version" = "v2.6.1" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
            sed -i '273d; 274d' "drivers/net/wireless/Kconfig"
            sed -i '433s/\bdepends\b/& on/' "drivers/serial/Kconfig"
            sed -i '877s/\bdepends\b/& on/' "fs/Kconfig"
            sed -i '881s/\bdepends\b/& on/' "fs/Kconfig"
        fi
        if [ "$version" = "v2.6.2" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
            sed -i '273d; 274d' "drivers/net/wireless/Kconfig"
            sed -i '433s/\bdepends\b/& on/' "drivers/serial/Kconfig"
            sed -i '881s/\bdepends\b/& on/' "fs/Kconfig"
        fi
        if [ "$version" = "v2.6.3" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
            sed -i '227d; 228d' "drivers/net/wireless/Kconfig"
            sed -i '433s/\bdepends\b/& on/' "drivers/serial/Kconfig"
            sed -i '893s/\bdepends\b/& on/' "fs/Kconfig"
        fi
        if [ "$version" = "v2.6.4" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
            sed -i '485s/\bdepends\b/& on/' "drivers/serial/Kconfig"
            sed -i '869s/\bdepends\b/& on/' "fs/Kconfig"
        fi
        if [ "$version" = "v2.6.5" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
            sed -i '459s/\bdepends\b/& on/' "drivers/serial/Kconfig"
            sed -i '869s/\bdepends\b/& on/' "fs/Kconfig"
        fi
        if [ "$version" = "v2.6.6" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
            sed -i '512s/\bdepends\b/& on/' "drivers/serial/Kconfig"
            sed -i '896s/\bdepends\b/& on/' "fs/Kconfig"
        fi
        if [ "$version" = "v2.6.7" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
            sed -i '513s/\bdepends\b/& on/' "drivers/serial/Kconfig"
            sed -i '930s/\bdepends\b/& on/' "fs/Kconfig"
        fi
        if [ "$version" = "v2.6.8" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
            sed -i '505s/\bdepends\b/& on/' "drivers/serial/Kconfig"
            sed -i '921s/\bdepends\b/& on/' "fs/Kconfig"
        fi
        if [ "$version" = "v2.6.9" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
            sed -i '505s/\bdepends\b/& on/' "drivers/serial/Kconfig"
            sed -i '924s/\bdepends\b/& on/' "fs/Kconfig"
            sed -i '26s/\bdepends\b/& on/' "lib/Kconfig.debug"
        fi
        if [ "$version" = "v2.6.10" ]; then
            sed -i 's/\xb4//g' "drivers/mtd/maps/Kconfig"
            sed -i '528s/\bdepends\b/& on/' "drivers/serial/Kconfig"
            sed -i '956s/\bdepends\b/& on/' "fs/Kconfig"
            sed -i '26s/\bdepends\b/& on/' "lib/Kconfig.debug"
        fi
        if [ "$version" = "v2.6.11" ]; then
            sed -i '541s/\bdepends\b/& on/; 797s/\bdepends\b/& on/' "drivers/serial/Kconfig"
            sed -i '851s/\bdepends\b/& on/' "fs/Kconfig"
        fi
        if [ "$version" = "v2.6.12" ]; then
            sed -i '95s/://' "net/ipv4/Kconfig"
            sed -i '541s/\bdepends\b/& on/; 797s/\bdepends\b/& on/' "drivers/serial/Kconfig"
            sed -i '845s/\bdepends\b/& on/' "drivers/char/Kconfig"
            sed -i '851s/\bdepends\b/& on/' "fs/Kconfig"
        fi
        if [ "$version" = "v2.6.13" ]; then
            sed -i '577s/\bdepends\b/& on/' "drivers/serial/Kconfig"
            sed -i '833s/\bdepends\b/& on/' "drivers/serial/Kconfig"
            sed -i '845s/\bdepends\b/& on/' "drivers/char/Kconfig"
            sed -i '843s/\bdepends\b/& on/' "fs/Kconfig"
        fi
        if [ "$version" = "v2.6.14" ]; then
            sed -i '577s/\bdepends\b/& on/' "drivers/serial/Kconfig"
            sed -i '833s/\bdepends\b/& on/' "drivers/serial/Kconfig"
            sed -i '845s/\bdepends\b/& on/' "drivers/char/Kconfig"
            sed -i '813s/\bdepends\b/& on/' "fs/Kconfig"
        fi
        if [ "$version" = "v2.6.15" ]; then
            sed -i '813s/\bdepends\b/& on/' "drivers/ide/Kconfig"
            sed -i '585s/\bdepends\b/& on/' "drivers/serial/Kconfig"
            sed -i '841s/\bdepends\b/& on/' "drivers/serial/Kconfig"
            sed -i '845s/\bdepends\b/& on/' "drivers/char/Kconfig"
            sed -i '813s/\bdepends\b/& on/' "fs/Kconfig"
        fi
        if [ "$version" = "v2.6.16" ]; then
            sed -i '227s/\bdepends\b/& on/' "init/Kconfig"
            sed -i '806s/\bdepends\b/& on/' "drivers/ide/Kconfig"
            sed -i '606s/\bdepends\b/& on/' "drivers/serial/Kconfig"
            sed -i '862s/\bdepends\b/& on/' "drivers/serial/Kconfig"
            sed -i '853s/\bdepends\b/& on/' "drivers/char/Kconfig"
            sed -i '843s/\bdepends\b/& on/' "fs/Kconfig"
        fi
        if [ "$version" = "v2.6.17" ]; then
            sed -i '238s/\bdepends\b/& on/' "init/Kconfig"
            sed -i '806s/\bdepends\b/& on/' "drivers/ide/Kconfig"
            sed -i '632s/\bdepends\b/& on/' "drivers/serial/Kconfig"
            sed -i '873s/\bdepends\b/& on/' "drivers/serial/Kconfig"
            sed -i '867s/\bdepends\b/& on/' "drivers/char/Kconfig"
            sed -i '15s/\bdepends\b/& on/; 24s/\bdepends\b/& on/; 31s/\bdepends\b/& on/; 38s/\bdepends\b/& on/; 45s/\bdepends\b/& on/; 54s/\bdepends\b/& on/; 70s/\bdepends\b/& on/; 78s/\bdepends\b/& on/; 85s/\bdepends\b/& on/' "drivers/leds/Kconfig"
            sed -i '1d' "drivers/rtc/Kconfig"
            sed -i '844s/\bdepends\b/& on/' "fs/Kconfig"
        fi
        if [ "$version" = "v2.6.18" ]; then
            sed -i '800s/\bdepends\b/& on/' "drivers/ide/Kconfig"
            sed -i '636s/\bdepends\b/& on/' "drivers/serial/Kconfig"
            sed -i '877s/\bdepends\b/& on/' "drivers/serial/Kconfig"
            sed -i '871s/\bdepends\b/& on/' "drivers/char/Kconfig"
            sed -i '3s/\bdepends\b/& on/' "sound/aoa/fabrics/Kconfig"
            sed -i '15s/\bdepends\b/& on/; 24s/\bdepends\b/& on/; 31s/\bdepends\b/& on/; 38s/\bdepends\b/& on/; 45s/\bdepends\b/& on/; 54s/\bdepends\b/& on/; 68s/\bdepends\b/& on/; 78s/\bdepends\b/& on/; 83s/\bdepends\b/& on/; 91s/\bdepends\b/& on/ ; 98s/\bdepends\b/& on/; 105s/\bdepends\b/& on/' "drivers/leds/Kconfig"
            sed -i '1d' "drivers/rtc/Kconfig"
            sed -i '867s/\bdepends\b/& on/' "fs/Kconfig"
        fi
        if [ "$version" = "v2.6.19" ]; then
            sed -i '799s/\bdepends\b/& on/' "drivers/ide/Kconfig"
            sed -i '637s/\bdepends\b/& on/' "drivers/serial/Kconfig"
            sed -i '883s/\bdepends\b/& on/' "drivers/serial/Kconfig"
            sed -i '855s/\bdepends\b/& on/' "drivers/char/Kconfig"
            sed -i '3s/\bdepends\b/& on/' "sound/aoa/fabrics/Kconfig"
            sed -i '15s/\bdepends\b/& on/; 24s/\bdepends\b/& on/; 31s/\bdepends\b/& on/; 38s/\bdepends\b/& on/; 45s/\bdepends\b/& on/; 54s/\bdepends\b/& on/; 68s/\bdepends\b/& on/; 78s/\bdepends\b/& on/; 83s/\bdepends\b/& on/; 91s/\bdepends\b/& on/; 98s/\bdepends\b/& on/; 105s/\bdepends\b/& on/' "drivers/leds/Kconfig"
            sed -i '1d' "drivers/rtc/Kconfig"
            sed -i '1011s/\bdepends\b/& on/' "fs/Kconfig"
        fi
        if [ "$version" = "v2.6.20" ]; then
            sed -i '1d' "drivers/rtc/Kconfig"
        fi
        if [ "$version" = "v2.6.21" ]; then
            sed -i 's/\xa0//g' "scripts/kconfig/Makefile"
            sed -i 's/\xa0//g' "drivers/usb/net/Kconfig"
            sed -i '87s/\bdepends\b/& on/' "drivers/leds/Kconfig"
        fi
        if [ "$version" = "v2.6.22" ]; then
            sed -i '150s/\bdepends\b/& on/' "drivers/input/misc/Kconfig"
            sed -i '88s/\bdepends\b/& on/' "drivers/leds/Kconfig"
        fi
        if [ "$version" = "v2.6.23" ]; then
            sed -i '22s/\bdepends\b/& on/' "drivers/telephony/Kconfig"
            sed -i '155s/\bdepends\b/& on/' "drivers/input/misc/Kconfig"
            sed -i '86s/\bdepends\b/& on/' "drivers/leds/Kconfig"
        fi
        if [ "$version" = "v2.6.32" ] || [ "$version" = "v2.6.33" ] || [ "$version" = "v2.6.34" ] || [ "$version" = "v2.6.35" ] || [ "$version" = "v2.6.36" ] || [ "$version" = "v2.6.37" ] || [ "$version" = "v2.6.38" ] || [ "$version" = "v2.6.39" ]; then
            sed -i '7d' "scripts/kconfig/Makefile"
        fi
        if [ "$version" = "v3.0" ]; then
            sed -i '1d' "drivers/staging/iio/light/Kconfig"
        fi
        if [ "$version" = "v3.10" ] || [ "$version" = "v3.11" ] || [ "$version" = "v3.7" ] || [ "$version" = "v3.8" ] || [ "$version" = "v3.9" ]; then
            sed -i '20d' "drivers/media/usb/stk1160/Kconfig"
        fi
        if [ "$version" = "v3.19" ]; then
            sed -i ':a;N;$!ba;s/\\\\\n\t\t//g' "sound/soc/intel/Kconfig"
        fi
        if [ "$version" = "v3.6" ] || [ "$version" = "v3.7" ] || [ "$version" = "v3.8" ] || [ "$version" = "v3.9" ]; then
            sed -i 's/+//' "sound/soc/ux500/Kconfig"
        fi
        if [ "$version" = "v4.18" ]; then
            sed -i 's/\xa0//g' "./net/netfilter/ipvs/Kconfig"
        fi
        if [ "$version" = "v5.12" ]; then
            sed -n '28,58p' "scripts/kconfig/Makefile" >> temp.txt
            sed -i '28,58d' "scripts/kconfig/Makefile"
            sed -i '24r temp.txt' "scripts/kconfig/Makefile"
            rm temp.txt
        fi
    fi

    # Call the Python script with the UVL file as an argument
    if [ "$major_version" -gt 3 ]; then
        make ARCH=$architecture SRCARCH=$architecture scriptconfig SCRIPT=construct-hierarchy.py SCRIPT_ARG="$uvl_file"
    else
        make -f ./scripts/kconfig/Makefile ARCH=$architecture SRCARCH=$architecture scriptconfig SCRIPT=construct-hierarchy.py SCRIPT_ARG="$uvl_file"
    fi

    # Undo changes before checking out the next branch
    git reset --hard

done
