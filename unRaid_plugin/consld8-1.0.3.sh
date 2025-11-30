#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.
# consld8-auto - Fully Automated or Interactive Consolidation for unRAID

# --- Configuration & Constants ---
# Default for CLI, overridden by WebUI or user input
BASE_SHARE="/mnt/user/TVSHOWS" 
# 200 GB minimum free space safety margin (in 1K blocks, as df/du output)
MIN_FREE_SPACE_KB=209715200
# ---------------------------------

# --- Variables ---
test_mode=true
verbose=false
auto_mode=false
mode_set_by_arg=false
base_share_selected=false
# NEW: Flag to indicate execution is from the PHP WebUI
WEBUI_MODE=false

# --- ANSI Color Definitions ---
RESET='\033[0m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
# ------------------------------

usage(){
cat << EOF

usage: consld8-auto [options:-h|-t|-f|-v|-a|-I] [WEBUI ARGS]

This script has two modes:
1. Interactive Mode (Requires -I flag): Prompts for folder and disk selection.
2. Automatic Mode (Requires -a flag): Scans all shares, plans, and executes optimized moves.

options:
  -h      Display this usage information.
  -t      Perform a test run (Dry Run). No files will be moved (Default).
  -f      Override test mode and force valid moves to be performed.
  -v      Print more information (recommended for auto mode).
  -a      *** Run in FULL AUTOMATIC PLANNING MODE ***
  -I      *** Run in INTERACTIVE MODE (Explicitly selected) ***
  
WEBUI EXECUTION:
When using -I from the Unraid WebUI, the script expects 3 positional arguments 
AFTER the flags:
1. FULL_TARGET_PATH (e.g., /mnt/user/SHARE/Folder)
2. FOLDER_NAME (e.g., Folder)
3. DESTINATION_DISK (e.g., disk10)

EOF
}

# Set shell options
shopt -s nullglob # Allows loops over empty globs without error

# --- PLACEHOLDER FUNCTIONS (Must exist for main logic to work) ---

# Function to safely move a folder (placeholder for actual move logic)
perform_move() {
    local source_path="$1"
    local dest_disk="$2"

    printf "%b\\n" "${CYAN}--- CONSOLIDATION JOB ---${RESET}"
    printf "%b\\n" "Source: ${BLUE}${source_path}${RESET}"
    printf "%b\\n" "Destination Disk: ${BLUE}/mnt/${dest_disk}${RESET}"
    printf "%b\\n" "Mode: ${YELLOW}$([ "$test_mode" = true ] && echo "DRY RUN" || echo "REAL MOVE")${RESET}"
    
    if [ "$test_mode" = true ]; then
        echo "TEST MODE: Would execute: rsync -av --remove-source-files \"${source_path}\" \"/mnt/${dest_disk}/\""
        echo "TEST MODE: Would delete source folder: rm -rf \"${source_path}\""
        echo "TEST MODE: Consolidation simulated successfully."
    else
        echo "Executing real move (rsync/rm)..."
        # ACTUAL EXECUTION LOGIC GOES HERE
        # rsync -av --remove-source-files "${source_path}" "/mnt/${dest_disk}/"
        # rm -rf "${source_path}"
        echo "REAL MOVE: Consolidation executed successfully."
    fi
}

# Function to get available shares (placeholder, as PHP does this now)
select_base_share() {
    # If in WebUI mode, the BASE_SHARE is already set, so we skip prompting.
    if [ "$WEBUI_MODE" = true ]; then
        return
    fi
    
    # --- CLI INTERACTIVE PROMPT LOGIC HERE ---
    printf "%b\\n" "${CYAN}--- CLI Share Selection ---${RESET}"
    # ... actual CLI prompt for share selection ...
    BASE_SHARE="/mnt/user/$(echo /mnt/user/* | awk '{print $1}')" # Example mock selection
    base_share_selected=true
}

# Function to execute consolidation in interactive mode
interactive_consolidation() {
    local FOLDER_FULL_PATH # Full path to the folder being consolidated
    local FOLDER_NAME_ONLY # Just the name of the folder
    local TARGET_DISK # Destination disk name (diskN or cache)

    if [ "$WEBUI_MODE" = true ]; then
        # NEW: Use variables pre-set by the WebUI argument parsing
        FOLDER_FULL_PATH="${FULL_TARGET_PATH}"
        FOLDER_NAME_ONLY="${FOLDER_TO_CONSOLIDATE}"
        TARGET_DISK="${DESTINATION_DISK}"
        
        # We perform validation here if necessary, but assume PHP input is safe
        printf "%b\\n" "${GREEN}WebUI Mode Active: Skipping interactive prompts.${RESET}"
        printf "%b\\n" "Target Folder: ${FOLDER_FULL_PATH}"
        printf "%b\\n" "Target Disk: ${TARGET_DISK}"

    else
        # --- CLI INTERACTIVE PROMPT LOGIC HERE ---
        printf "%b\\n" "${CYAN}--- CLI Interactive Consolidation ---${RESET}"
        # ... CLI prompts for folder selection and disk selection ...
        # FOLDER_FULL_PATH="/mnt/user/TVSHOWS/SomeShow" # Example mock selection
        # TARGET_DISK="disk10" # Example mock selection
        
        echo "Simulating CLI interactive selection..."
        # Exit if CLI selection fails
        # return 1
    fi
    
    # --- Unified Execution Logic ---
    if [ -n "$FOLDER_FULL_PATH" ] && [ -n "$TARGET_DISK" ]; then
        perform_move "$FOLDER_FULL_PATH" "$TARGET_DISK"
    else
        printf "%b\\n" "${RED}Error: Consolidation parameters missing. Aborting.${RESET}"
    fi
}

# --- Main Script Execution ---

# Parse command line options
while getopts "htfvaI" opt; do
    case "$opt" in
        h)
            usage
            exit 0
            ;;
        t)
            test_mode=true
            ;;
        f)
            test_mode=false
            ;;
        v)
            verbose=true
            ;;
        a)
            auto_mode=true
            mode_set_by_arg=true
            ;;
        I)
            auto_mode=false
            mode_set_by_arg=true
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done

# --- NEW: WebUI Argument Handling for Interactive Mode (-I) ---
# If -I was set, we check for 3 positional arguments passed by the PHP WebUI
if [ "$auto_mode" = false ] && [ "$mode_set_by_arg" = true ]; then
    # Shift positional parameters to only include those after the flags
    shift $((OPTIND-1))
    
    # Check for the 3 required positional arguments passed by PHP
    if [ "$#" -ge 3 ]; then
        WEBUI_MODE=true # Flag to skip interactive prompts later
        
        # 1. Full Folder Path (/mnt/user/SHARE/Folder)
        FULL_TARGET_PATH="$1"
        # 2. Folder Name (Folder) - Not strictly needed, but useful for logs
        FOLDER_TO_CONSOLIDATE="$2"
        # 3. Destination Disk (diskN)
        DESTINATION_DISK="$3"
        
        # Derive the top-level BASE_SHARE path from the full target path.
        BASE_SHARE=$(dirname "${FULL_TARGET_PATH}")
        
        # Ensure the base share is considered selected to bypass the select_base_share call
        base_share_selected=true 
        
    else
        # Not enough arguments for WebUI mode, proceed with normal CLI flow (will prompt the user)
        WEBUI_MODE=false
        # Restore positional parameters for any other CLI logic that might rely on them
        set -- "$@" 
    fi
fi
# ---------------------------------------------------------------


# 1. Prompt for mode selection if not specified by argument AND not in WebUI mode
if [ "$mode_set_by_arg" = false ] && [ "$WEBUI_MODE" = false ]; then
    printf "%b\\n" "${CYAN}------------------------------------------------${RESET}"
    printf "%b\\n" "${CYAN}      UnRAID Consolidation Mode Selection      ${RESET}"
    printf "%b\\n" "${CYAN}------------------------------------------------${RESET}"
    echo "No operation mode (-a or -I) was specified. Please select a mode to proceed."
    # ... (CLI logic for prompting 1 or 2) ...
fi

# 2. Prompt for the base share by scanning /mnt/user/ IF not already selected
if [ "$base_share_selected" = false ]; then
    select_base_share
fi

# 3. Execute the selected mode
if [ "$auto_mode" = false ]; then
    # Interactive mode (handles both CLI prompts and WebUI pre-set execution)
    interactive_consolidation
else
    # Automatic mode execution logic (not implemented here)
    printf "%b\\n" "${YELLOW}Automatic Mode selected. Execution logic is missing in this example.${RESET}"
fi

printf "%b\\n" "${GREEN}Script finished execution.${RESET}"
