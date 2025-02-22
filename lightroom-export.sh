#!/bin/zsh
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin/:$PATH"

# Determine the folder where this script is located
SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"

# The configuration file is located in the same folder as the script
CONFIG_FILE="$SCRIPT_DIR/lightroom-export.config"
if [ ! -f "$CONFIG_FILE" ]; then
    osascript -e "display dialog \"Configuration file lightroom-export.config not found in folder $SCRIPT_DIR.\" with title \"Error\" buttons {\"OK\"} default button \"OK\""
    exit 1
fi

# Read the configuration file line by line:
# Remove lines that are empty or consist only of whitespace,
# and lines that (after optional whitespace) start with '#'.
configPaths=("${(@f)$(sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "$CONFIG_FILE")}")
if [ ${#configPaths[@]} -eq 0 ]; then
    osascript -e "display dialog \"No target paths found in the configuration file.\" with title \"Error\" buttons {\"OK\"} default button \"OK\""
    exit 1
fi

# At least one filename must be provided as parameter
if [ "$#" -lt 1 ]; then
    osascript -e "display dialog \"No filename provided as parameter.\" with title \"Error\" buttons {\"OK\"} default button \"OK\""
    exit 1
fi

# Check if exiftool is installed
if ! command -v exiftool >/dev/null 2>&1; then
    osascript -e "display dialog \"ExifTool is not installed.\" with title \"Error\" buttons {\"OK\"} default button \"OK\""
    exit 1
fi

# Goal: Summary of moved files per target path
typeset -A summary

# Global list of processed files (only basenames)
processedFiles=()

# Array for all used target directories (unique)
usedTargets=()

# For each provided file
for sourceFile in "$@"; do
    # Determine the job identifier (first try IPTC, then XMP)
    jobField=$(exiftool -s -s -s -IPTC:OriginalTransmissionReference "$sourceFile")
    if [ -z "$jobField" ]; then
        jobField=$(exiftool -s -s -s -XMP:TransmissionReference "$sourceFile")
    fi
    if [ -z "$jobField" ]; then
        osascript -e "display dialog \"Job identifier could not be read for $sourceFile.\" with title \"Error\" buttons {\"OK\"} default button \"OK\""
        exit 1
    fi

    numTargets=${#configPaths[@]}
    # For each target path provided in the configuration file
    for (( i=1; i<=numTargets; i++ )); do
        targetBase="${configPaths[$i]}"
        # Check if the base target path exists and is writable
        if [ ! -d "$targetBase" ] || [ ! -w "$targetBase" ]; then
            osascript -e "display dialog \"Cannot access target path $targetBase.\" with title \"Error\" buttons {\"OK\"} default button \"OK\""
            exit 1
        fi

        fullTargetPath="$targetBase/$jobField"
        if [ ! -d "$fullTargetPath" ]; then
            mkdir -p "$fullTargetPath"
            if [ $? -ne 0 ]; then
                osascript -e "display dialog \"The directory $fullTargetPath could not be created.\" with title \"Error\" buttons {\"OK\"} default button \"OK\""
                exit 1
            fi
        fi

        baseName=$(basename "$sourceFile")
        destination="$fullTargetPath/$baseName"

        # For all target paths except the last one, copy the file; for the last, move it.
        if [ $i -lt $numTargets ]; then
            cp "$sourceFile" "$destination"
            if [ $? -ne 0 ]; then
                osascript -e "display dialog \"The file $sourceFile could not be copied to $fullTargetPath.\" with title \"Error\" buttons {\"OK\"} default button \"OK\""
                exit 1
            fi
        else
            mv "$sourceFile" "$destination"
            if [ $? -ne 0 ]; then
                osascript -e "display dialog \"The file $sourceFile could not be moved to $fullTargetPath.\" with title \"Error\" buttons {\"OK\"} default button \"OK\""
                exit 1
            fi
        fi

        # Add the file's basename to the summary for this target path
        key="$fullTargetPath"
        if [[ -n "${summary[$key]}" ]]; then
            summary[$key]="${summary[$key]}, $baseName"
        else
            summary[$key]="$baseName"
        fi

        # Save the target path in usedTargets if not already present
        if [[ ! " ${usedTargets[@]} " =~ " $fullTargetPath " ]]; then
            usedTargets+=("$fullTargetPath")
        fi
    done

    # Add the file's basename to the global list
    processedFiles+=("$baseName")
done

# Build the final message:
# List of processed files
filesText=""
for file in "${processedFiles[@]}"; do
    filesText+="$file\n"
done

# List of target directories
targetsText=""
for target in "${usedTargets[@]}"; do
    targetsText+="$target\n"
done

endMessage="Lightroom export completed.\n\nProcessed Files:\n$filesText\nTarget Directories:\n$targetsText"

osascript <<EOF
display dialog "$endMessage" with title "Export Summary" buttons {"OK"} default button "OK"
EOF