#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.
# consld8-auto - Fully Automated or Interactive Consolidation for unRAID (v1.2.0)
VERSION="1.2.0"

# --- Configuration & Constants ---
BASE_SHARE="/mnt/user/TVSHOWS"
# 200 GB minimum free space safety margin (in 1K blocks, as df/du output)
MIN_FREE_SPACE_KB=209715200
# ---------------------------------

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
consld8-auto v$VERSION

usage: consld8-auto [options:-h|-t|-f|-v|-a|-I]

This script has two modes:
1. Interactive Mode (Requires -I flag): Prompts for folder and disk selection.
2. Automatic Mode (Requires -a flag): Scans all folders and generates an optimized move plan.

options:
  -h      Display this usage information.
  -t      Perform a test run (Dry Run). No files will be moved.
  -f      Override test mode and force valid moves to be performed.
  -v      Print more information (recommended for auto mode).
  -a      *** Run in FULL AUTOMATIC PLANNING MODE ***
  -I      *** Run in INTERACTIVE MODE (Explicitly selected) ***

EOF
}

# Set shell options
shopt -s nullglob # FIX: Corrected syntax to enable nullglob option using '-s'
[ ${DEBUG:=0} -gt 0 ] && set -x

# --- Variables ---
verbose=1
dry_run=true      # Default to safety (Test mode)
auto_mode=false   # Default is set to false, but mode must be selected if no flag is provided
mode_set_by_arg=false # Tracks if -a or -I was provided
ACTIVE_MIN_FREE_KB="$MIN_FREE_SPACE_KB" # Variable to store the user-configured minimum free space
# -------------------

# --- Argument Parsing ---
while getopts "htfvaI" opt; do
  case "$opt" in
    h)
      usage
      exit 0
      ;;
    t) # Specify test mode
      dry_run=true
      ;;
    f) # Override test mode and force action
      dry_run=false
      ;;
    v)
      verbose=$((verbose + 1))
      ;;
    a) # Activate Automatic Mode
      auto_mode=true
      mode_set_by_arg=true # Only set to true if a mode (-a or -I) is explicitly provided
      ;;
    I) # Activate Interactive Mode (Explicitly selected)
      auto_mode=false
      mode_set_by_arg=true # Only set to true if a mode (-a or -I) is explicitly provided
      ;;
    *)
      printf "%b\n" "${YELLOW}Unknown option (ignored): -$OPTARG${RESET}" >&2
      ;;
  esac
done
shift $((OPTIND-1))

# --- Helper Functions ---

# Function to check if a share component is consolidated (exists on 1 or fewer disks)
# Argument 1: The share component path (e.g., TVSHOWS/ShowName)
is_consolidated() {
    local share_component="$1"
    local consolidated_disk_count=0
    
    # Loop through all possible source disks (including cache)
    for d_path in /mnt/{disk[1-9]{,[0-9]},cache}; do
        # Check if the folder path exists on this physical disk
        if [ -d "$d_path/$share_component" ]; then
            # Check if it contains files
            if [ -n "$(find "$d_path/$share_component" -mindepth 1 -type f 2>/dev/null | head -n 1)" ]; then
                consolidated_disk_count=$((consolidated_disk_count + 1))
            fi
        fi
    done
    
    if [ "$consolidated_disk_count" -le 1 ]; then
        return 0 # Consolidated (True)
    else
        return 1 # Not consolidated (False)
    fi
}

# Function to display fragmentation information for a selected folder
display_folder_fragmentation_info() {
    local share_component="$1"
    local total_size=0
    local fragment_count=0

    printf "%b\n" "${CYAN}--- Current Fragmentation Status ---${RESET}"
    
    # Loop through all possible source disks (including cache)
    for d_path in /mnt/{disk[1-9]{,[0-9]},cache}; do
        local disk_name="${d_path#/mnt/}"
        local full_path="$d_path/$share_component"
        
        if [ -d "$full_path" ]; then
            # Calculate size (in 1K blocks)
            local folder_size_kb=$(du -s "$full_path" 2>/dev/null | cut -f 1)
            
            # Only count and display if the folder actually contains data (size > 0)
            if [ -n "$folder_size_kb" ] && [ "$folder_size_kb" -gt 0 ]; then
                local formatted_size=$(numfmt --to=iec --from-unit=1K $folder_size_kb)
                printf "%b\n" "  -> ${GREEN}$disk_name${RESET} (${BLUE}$full_path${RESET}): ${YELLOW}$formatted_size${RESET}"
                total_size=$((total_size + folder_size_kb))
                fragment_count=$((fragment_count + 1))
            fi
        fi
    done
    
    if [ "$fragment_count" -eq 0 ]; then
        printf "%b\n" "${YELLOW}Folder appears empty or consolidated to a location not checked.${RESET}"
    else
        local formatted_total_size=$(numfmt --to=iec --from-unit=1K $total_size)
        printf "%b\n" "${CYAN}Total Size across $fragment_count fragments: ${YELLOW}$formatted_total_size${RESET}"
    fi
    printf "%b\n" "${CYAN}------------------------------------${RESET}"
    echo ""
}


# Function to safely execute rsync move
execute_move() {
    local src_dir_name="$1"
    local dest_disk="$2"
    
    printf "%b\n" "${CYAN}>> Preparing to move '${src_dir_name}' to disk '$dest_disk'..."
    
    local dest_path="/mnt/$dest_disk/$src_dir_name"
    
    if [ "$dry_run" = true ]; then
        printf "%b\n" "   ${YELLOW}[DRY RUN] Would consolidate all fragments of '$src_dir_name' to '$dest_path'.${RESET}"
        printf "%b\n" "   ${YELLOW}[DRY RUN] Would use rsync to move and remove source files.${RESET}"
        return 0
    fi
    
    # Ensure destination directory exists on the target disk
    mkdir -p "$dest_path"

    # Loop through all possible source disks (including cache)
    for d in /mnt/{disk[1-9]{,[0-9]},cache}; do
        local source_path="$d/$src_dir_name"
        
        # Check if source directory exists AND it's not the destination disk
        if [ -d "$source_path" ] && [ "/mnt/$dest_disk" != "$d" ]; then
            [ $verbose -gt 0 ] && printf "%b\n" "   Merging data from ${BLUE}$d${RESET}..."

            # Use rsync to move contents (The safe move: copy and delete source)
            # The trailing slash on the source path means copy *contents* of the directory
            rsync -avh --remove-source-files "$source_path/" "$dest_path/"
            
            if [ $? -eq 0 ]; then
                # Clean up empty directories
                find "$source_path" -type d -empty -delete
                # Attempt to remove the share root on that disk if it's now empty
                rmdir "$source_path" 2>/dev/null || true
            else
                printf "%b\n" "${RED}   WARNING: Rsync failed from $source_path. Skipping cleanup.${RESET}" >&2
            fi
        fi
    done
    printf "%b\n" "${GREEN}Move execution complete for $src_dir_name.${RESET}"
}

# Function for manual path entry (used as a fallback/alternative)
configure_manual_base_share() {
    while true; do
        # FIX: Construct colored prompt using printf -v
        local prompt_str
        printf -v prompt_str "Enter the base share path (e.g., /mnt/user/TVSHOWS). Current: %b: " "${BLUE}$BASE_SHARE${RESET}"
        read -r -p "$prompt_str" NEW_BASE_SHARE_INPUT
        
        if [ -z "$NEW_BASE_SHARE_INPUT" ]; then
            printf "%b\n" "Using current base share: ${BLUE}$BASE_SHARE${RESET}"
            break
        fi # FIX: Closing 'if' block
        
        # Check if the input path exists and is a directory
        if [ -d "$NEW_BASE_SHARE_INPUT" ]; then
            # Remove trailing slash if present
            BASE_SHARE="${NEW_BASE_SHARE_INPUT%/}"
            printf "%b\n" "Base Share set to: ${BLUE}$BASE_SHARE${RESET}"
            break
        else
            printf "%b\n" "${RED}Error: '$NEW_BASE_SHARE_INPUT' is not a valid directory. Please try again.${RESET}" >&2
        fi
    done
}


# --- Share Selection Logic (New) ---
select_base_share() {
    printf "%b\n" "${CYAN}------------------------------------------------${RESET}"
    printf "%b\n" "${CYAN}       Select Base Share for Consolidation       ${RESET}"
    printf "%b\n" "${CYAN}------------------------------------------------${RESET}"
    
    # Scan for top-level user shares in /mnt/user/
    local shares=()
    # Find all top-level directories under /mnt/user/ that are not system files or the root itself
    mapfile -t shares < <(find /mnt/user -maxdepth 1 -mindepth 1 -type d -not -name '@*' -printf '%P\n' 2>/dev/null | sort)

    if [ ${#shares[@]} -eq 0 ]; then
        printf "%b\n" "${YELLOW}WARNING: No user shares found in /mnt/user/. Proceeding with manual input.${RESET}"
        # Fallback to manual input if no shares are found
        configure_manual_base_share
        return 0
    fi
    
    echo "Available Shares in /mnt/user/:"
    local i=1
    for share_name in "${shares[@]}"; do
        printf "%b\n" "  ${GREEN}$i${RESET}) $share_name"
        i=$((i + 1))
    done
    printf "%b\n" "  ${GREEN}L${RESET}) Enter a custom path manually."
    
    while true; do
        # FIX: Construct colored prompt using printf -v
        local prompt_str
        printf -v prompt_str "Enter number of share or 'L' for custom path: "
        read -r -p "$prompt_str" SELECTION
        
        # Check for Manual Input
        if [[ "$SELECTION" == "L" || "$SELECTION" == "l" ]]; then
            configure_manual_base_share
            break
        fi

        # Check for numbered selection
        if [[ "$SELECTION" =~ ^[0-9]+$ ]] && [ "$SELECTION" -ge 1 ] && [ "$SELECTION" -le ${#shares[@]} ]; then
            SELECTED_SHARE_NAME="${shares[$((SELECTION - 1))]}"
            BASE_SHARE="/mnt/user/$SELECTED_SHARE_NAME"
            printf "%b\n" "Base Share set to: ${BLUE}$BASE_SHARE${RESET}"
            break
        else
            printf "%b\n" "${RED}Invalid selection. Please enter a number between 1 and ${#shares[@]}, or 'L'.${RESET}" >&2
        # FIX: Removed stray '*/' which caused the EOF error
        fi
    done
    echo ""
}


# --- Interactive Mode Logic ---

interactive_consolidation() {
    printf "%b\n" "${CYAN}------------------------------------------------${RESET}"
    printf "%b\n" "${CYAN}     UnRAID Consolidation Script (Interactive)   ${RESET}"
    printf "%b\n" "${CYAN}------------------------------------------------${RESET}"
    
    if [ "$dry_run" = true ]; then
        printf "%b\n" ">> MODE: ${YELLOW}DRY RUN (Test mode). Add -f to execute moves.${RESET}"
    else
        printf "%b\n" ">> MODE: ${GREEN}FORCE (Execution mode). Files WILL be moved.${RESET}"
    fi
    echo ""
    
    # 1. Consolidation Filter Selection
    local filter_consolidated=false
    
    printf "%b\n" "${CYAN}--- Folder Filtering ---${RESET}"
    echo "Do you want to exclude folders that are already consolidated (only on one disk)?"
    printf "%b\n" "  ${GREEN}1${RESET}) Yes, only show fragmented folders (Recommended)."
    printf "%b\n" "  ${GREEN}2${RESET}) No, show all folders (Consolidated and Fragmented)."
    
    while true; do
        local prompt_str
        printf -v prompt_str "Select filter option (%b or %b): " "${GREEN}1${RESET}" "${GREEN}2${RESET}"
        read -r -p "$prompt_str" FILTER_SELECTION
        case "$FILTER_SELECTION" in
            1)
                filter_consolidated=true
                printf "%b\n" "${YELLOW}Filter set: Only Fragmented folders will be listed.${RESET}"
                break
                ;;
            2)
                filter_consolidated=false
                printf "%b\n" "${YELLOW}Filter set: All folders will be listed.${RESET}"
                break
                ;;
            *)
                printf "%b\n" "${RED}Invalid selection. Please enter 1 or 2.${RESET}"
                ;;
        esac
    done
    echo ""

    # 2. Select Share/Folder
    
    printf "%b\n" "DEBUG: Scanning for subfolders in ${BLUE}$BASE_SHARE${RESET}..."
    
    local all_folders=()
    local filtered_folders=()

    # Get all subdirectories of the base share (e.g., TVSHOWS/Show1, TVSHOWS/Show2)
    # MODIFICATION: Exclude .trash, .recycle, .Recycle directories.
    mapfile -t all_folders < <(find "$BASE_SHARE" -mindepth 1 -maxdepth 1 -type d \
        -not -name '.trash' \
        -not -name '.recycle' \
        -not -name '.Recycle' \
        -printf '%P\n' | sort)

    if [ ${#all_folders[@]} -eq 0 ]; then
        printf "%b\n" "${RED}ERROR: No subdirectories found in $BASE_SHARE. Exiting.${RESET}" >&2
        exit 1
    fi

    # Apply Filtering
    for folder_name in "${all_folders[@]}"; do
        # The full share component path (e.g., TVSHOWS/ShowName)
        local share_component="${BASE_SHARE#/mnt/user/}/$folder_name"
        
        if [ "$filter_consolidated" = true ]; then
            # If the filter is ON, we only include UNCONSOLIDATED folders (return code 1)
            if ! is_consolidated "$share_component"; then
                filtered_folders+=("$folder_name")
            fi
        else
            # If the filter is OFF, include everything
            filtered_folders+=("$folder_name")
        fi
    done
    
    # Update FOLDERS array to the filtered list
    local FOLDERS=("${filtered_folders[@]}")

    if [ ${#FOLDERS[@]} -eq 0 ]; then
        printf "%b\n" "${GREEN}Success!${RESET} ${YELLOW}Based on your filter, all shares are consolidated or empty. No folders listed for action.${RESET}"
        return 0
    fi
    
    
    printf "%b\n" "Available Folders in '${BLUE}$BASE_SHARE${RESET}' to consolidate:"
    local i=1
    for folder in "${FOLDERS[@]}"; do
        # Calculate size for display purposes
        local folder_path="$BASE_SHARE/$folder"
        local folder_size_kb=$(du -s "$folder_path" | cut -f 1)
        local formatted_size=$(numfmt --to=iec --from-unit=1K $folder_size_kb)
        printf "%b\n" "  ${GREEN}$i${RESET}) $folder (Size: ${BLUE}$formatted_size${RESET})"
        i=$((i + 1))
    done

    while true; do
        # FIX: Construct colored prompt using printf -v
        local prompt_str
        printf -v prompt_str "Enter the number of the folder to consolidate: "
        read -r -p "$prompt_str" FOLDER_NUM
        if [[ "$FOLDER_NUM" =~ ^[0-9]+$ ]] && [ "$FOLDER_NUM" -ge 1 ] && [ "$FOLDER_NUM" -le ${#FOLDERS[@]} ]; then
            SELECTED_FOLDER="${FOLDERS[$((FOLDER_NUM - 1))]}"
            # The full share component path (e.g., TVSHOWS/ShowName)
            SHARE_COMPONENT="${BASE_SHARE#/mnt/user/}/$SELECTED_FOLDER"
            break
        else
            printf "%b\n" "${RED}Invalid selection. Please enter a number between 1 and ${#FOLDERS[@]}.${RESET}"
        fi
    done

    printf "%b\n" "Selected Folder: ${BLUE}$SELECTED_FOLDER${RESET}"
    echo ""
    
    # 2a. NEW STEP: Show Fragmentation Info
    display_folder_fragmentation_info "$SHARE_COMPONENT"

    # 3. Select Destination Disk
    
    printf "%b\n" "DEBUG: Discovering disks in /mnt/{disk*,cache}..."
    # Get all available physical disks and cache using robust globbing (FIX)
    local disk_names=()
    for d in /mnt/{disk[1-9]{,[0-9]},cache}; do
        if [ -d "$d" ]; then
            # Add the disk name (e.g., "disk1", "cache") to the array
            disk_names+=("${d#/mnt/}")
        fi
    done
    # Sort the list and populate the DISKS array
    mapfile -t DISKS < <(printf "%s\n" "${disk_names[@]}" | sort)

    # ADDED: Graceful exit if no disks are found
    if [ ${#DISKS[@]} -eq 0 ]; then
        printf "%b\n" "${RED}ERROR: No disks or cache drives found in /mnt (looking for /mnt/disk* or /mnt/cache). Cannot proceed.${RESET}" >&2
        return 1
    fi
    
    echo "Available Destination Disks:"
    i=1
    for disk in "${DISKS[@]}"; do
        local disk_path="/mnt/$disk"
        # CRITICAL FIX: Robustly get the Available blocks
        local current_free=$(df -P "$disk_path" 2>/dev/null | tail -1 | awk '{ print $4 }')
        local formatted_free=$(numfmt --to=iec --from-unit=1K "${current_free:-0}")
        printf "%b\n" "  ${GREEN}$i${RESET}) $disk (Free: ${BLUE}$formatted_free${RESET})"
        i=$((i + 1))
    done

    while true; do
        # FIX: Construct colored prompt using printf -v
        local prompt_str
        printf -v prompt_str "Enter the number of the destination disk: "
        read -r -p "$prompt_str" DISK_NUM
        if [[ "$DISK_NUM" =~ ^[0-9]+$ ]] && [ "$DISK_NUM" -ge 1 ] && [ "$DISK_NUM" -le ${#DISKS[@]} ]; then
            SELECTED_DISK="${DISKS[$((DISK_NUM - 1))]}"
            break
        else
            printf "%b\n" "${RED}Invalid selection. Please enter a number between 1 and ${#DISKS[@]}.${RESET}"
        fi
    done

    printf "%b\n" "Selected Destination Disk: ${BLUE}$SELECTED_DISK${RESET}"
    echo ""
    
    # 4. Confirmation and Execution

    if [ "$dry_run" = true ]; then
        local confirmation_message="${YELLOW}DRY RUN enabled.${RESET}"
    else
        local confirmation_message="${RED}This will MOVE all files. THIS CANNOT BE UNDONE.${RESET}"
    fi

    printf "%b\n" "${CYAN}--- CONFIRMATION ---${RESET}"
    printf "%b\n" "Folder to Consolidate: ${BLUE}$SELECTED_FOLDER${RESET} (Full Path: ${BLUE}$SHARE_COMPONENT${RESET})"
    printf "%b\n" "Target Destination Disk: ${BLUE}$SELECTED_DISK${RESET} (/mnt/$SELECTED_DISK/$SHARE_COMPONENT)"
    printf "%b\n" "$confirmation_message"
    printf "%b\n" "${CYAN}--------------------${RESET}"

    while true; do
        # FIX: Construct colored prompt using printf -v and guide the user for Enter key
        local prompt_str
        printf -v prompt_str "Proceed with consolidation? (%b/yes to confirm, no to cancel): " "${GREEN}Enter${RESET}"
        read -r -p "$prompt_str" CONFIRM
        # Check for empty string (Enter), or explicit 'y'/'yes'
        case "$CONFIRM" in
            ""|[Yy]|[Yy][Ee][Ss]) # Matches empty string (Enter), Y, y, Yes, yes
                execute_move "$SHARE_COMPONENT" "$SELECTED_DISK"
                if [ "$dry_run" = true ]; then
                    # The prompt after dry run is removed
                    :
                fi
                return 0
                ;;
            [Nn]|[Nn][Oo]) # Matches N, n, No, no
                printf "%b\n" "${YELLOW}Consolidation cancelled by user.${RESET}"
                return 1
                ;;
            *)
                printf "%b\n" "${RED}Invalid input. Please answer 'yes', 'no', or press Enter to confirm.${RESET}"
                ;;
        esac
    done
}


# Function to prompt the user for the minimum free space safety margin in GB
prompt_for_min_free_space() {
    local default_gb=$((MIN_FREE_SPACE_KB / 1024 / 1024)) # Default in GB (200)
    
    printf "%b\n" "${CYAN}--- Safety Margin Configuration ---${RESET}"
    # FIX: Replaced echo with printf "%b\n" to correctly interpret ANSI color codes
    printf "%b\n" "The current default minimum free space safety margin is ${BLUE}${default_gb} GB${RESET}."
    printf "%b\n" "This script will ensure the destination disk has at least this much free space AFTER the move."
    
    while true; do
        local prompt_str
        printf -v prompt_str "Enter a new minimum free space amount (in GB) or press Enter to use the default of %b GB: " "${GREEN}${default_gb}${RESET}"
        read -r -p "$prompt_str" USER_INPUT_GB
        
        if [ -z "$USER_INPUT_GB" ]; then
            ACTIVE_MIN_FREE_KB="$MIN_FREE_SPACE_KB"
            printf "%b\n" "Using default safety margin: ${BLUE}$(numfmt --to=iec --from-unit=1K $ACTIVE_MIN_FREE_KB)${RESET}"
            return 0
        fi

        # Input validation: must be a positive integer
        # Note: Uses POSIX ERE syntax for regex matching in bash [[ ... =~ ... ]]
        if [[ "$USER_INPUT_GB" =~ ^[1-9][0-9]*$ ]]; then
            # Convert GB to 1K blocks (KB)
            # KB = GB * 1024 * 1024
            ACTIVE_MIN_FREE_KB=$((USER_INPUT_GB * 1024 * 1024))
            printf "%b\n" "Safety margin set to: ${BLUE}$(numfmt --to=iec --from-unit=1K $ACTIVE_MIN_FREE_KB)${RESET}"
            return 0
        else
            printf "%b\n" "${RED}Invalid input. Please enter a positive whole number for GB or press Enter.${RESET}" >&2
        fi
    done
}


# --- Core Logic for Automated Planning (Refactored for Tiered Fallback) ---

auto_plan_and_execute() {
    printf "%b\n" "${CYAN}--------------------------------------------------------${RESET}"
    printf "%b\n" "${CYAN}     Starting FULL AUTOMATED CONSOLIDATION PLANNER        ${RESET}"
    printf "%b\n" "${CYAN}--------------------------------------------------------${RESET}"
    
    # NEW: Prompt for minimum free space before proceeding with the scan
    prompt_for_min_free_space

    printf "%b\n" "Base Share: ${BLUE}$BASE_SHARE${RESET}"
    printf "%b\n" "Safety Margin: ${BLUE}$(numfmt --to=iec --from-unit=1K $ACTIVE_MIN_FREE_KB)${RESET} minimum free space"
    
    if [ "$dry_run" = true ]; then
        printf "%b\n" ">> MODE: ${YELLOW}DRY RUN (Planning Only, no files will move)${RESET}"
    else
        printf "%b\n" ">> MODE: ${GREEN}FORCE (Files WILL be moved)${RESET}"
    fi
    echo ""

    # =====================================================================
    # NEW STEP 1: CONSOLIDATED FOLDER DISPLAY PROMPT
    # =====================================================================
    local show_consolidated_skips=false
    
    printf "%b\n" "${CYAN}--- Scan Verbosity ---${RESET}"
    echo "Do you want to display folders that are already consolidated and will be skipped?"
    printf "%b\n" "  ${GREEN}1${RESET}) Yes, show detailed skip messages (More verbose)."
    printf "%b\n" "  ${GREEN}2${RESET}) No, hide skip messages (Less verbose/default)."
    
    while true; do
        local prompt_str
        printf -v prompt_str "Select display option (%b or %b): " "${GREEN}1${RESET}" "${GREEN}2${RESET}"
        read -r -p "$prompt_str" DISPLAY_SELECTION
        case "$DISPLAY_SELECTION" in
            1)
                show_consolidated_skips=true
                printf "%b\n" "${YELLOW}Scan set: Skipped (Consolidated) folders will be detailed.${RESET}"
                break
                ;;
            2)
                show_consolidated_skips=false
                printf "%b\n" "${YELLOW}Scan set: Skipped (Consolidated) folders will be hidden from output.${RESET}"
                break
                ;;
            *)
                printf "%b\n" "${RED}Invalid selection. Please enter 1 or 2.${RESET}"
                ;;
        esac
    done
    echo ""
    # =====================================================================

    # Declare associative arrays to track disk state during planning
    declare -A DISK_FREE
    declare -A DISK_SHARE_USAGE
    
    # 1. Initialize Disk Free Space and Share Usage for all disks
    echo "Scanning initial disk state..."
    printf "%b\n" "DEBUG: Discovering disks in /mnt/{disk*,cache} and fetching free space..."
    for d_path in /mnt/{disk[1-9]{,[0-9]},cache}; do
        disk_name="${d_path#/mnt/}"
        
        # CRITICAL FIX: Robustly get the Available blocks using df -P
        current_free=$(df -P "$d_path" 2>/dev/null | tail -1 | awk '{ print $4 }')
        
        # Check if current_free is empty or non-numeric (setting to 0 if invalid)
        if ! [[ "$current_free" =~ ^[0-9]+$ ]]; then
            current_free=0
            printf "%b\n" "${YELLOW}  WARNING: Failed to read free space for $disk_name. Assuming 0KB free.${RESET}"
        fi
        
        DISK_FREE["$disk_name"]="$current_free"

        # Calculate share usage (DUSAGE) for the entire BASE_SHARE on this disk
        # Use find to accurately get the path relative to /mnt/user/
        share_path_relative="${BASE_SHARE#/mnt/user/}"
        
        if [ -d "$d_path/$share_path_relative" ]; then
            current_share_usage=$(du -s "$d_path/$share_path_relative" 2>/dev/null | cut -f 1)
        else
            current_share_usage=0
        fi
        DISK_SHARE_USAGE["$disk_name"]="$current_share_usage"
        
        [ $verbose -gt 1 ] && printf "%b\n" "  $disk_name: Free=${BLUE}$(numfmt --to=iec --from-unit=1K ${DISK_FREE[$disk_name]})${RESET}, ShareUsed=${BLUE}$(numfmt --to=iec --from-unit=1K ${DISK_SHARE_USAGE[$disk_name]})${RESET}"
    done
    
    # Array to hold the final execution plan
    PLAN_ARRAY=()
    
    # 2. Iterate through all subdirectories and create the plan
    echo ""
    echo "Generating Consolidation Plan (Prioritizing File Count > Free Space Fallback)..."
    
    # Temporary file to store candidates for sorting
    local TEMP_CANDIDATES
    TEMP_CANDIDATES=$(mktemp)
    
    # Loop through subdirectories of the base share (e.g., TVSHOWS/Show1, TVSHOWS/Show2)
    # MODIFICATION: Exclude .trash, .recycle, .Recycle directories from the find output.
    while IFS= read -r full_src_path; do
        
        share_component="${full_src_path#/mnt/user/}" # e.g., TVSHOWS/ShowName
        if [ -z "$share_component" ]; then continue; fi # <--- FIX: Changed 'endif' to 'fi'
        
        folder_name="${full_src_path##*/}" # Just the folder name (e.g., ShowName)
        folder_size=$(du -s "$full_src_path" 2>/dev/null | cut -f 1)
        
        if [ "$folder_size" -lt 10 ]; then continue; fi

        # --- Check if folder is already consolidated ---
        if is_consolidated "$share_component"; then
            if [ "$show_consolidated_skips" = true ]; then
                printf "%b\n" "${YELLOW}  [SKIP]: '${share_component}' (Size: $(numfmt --to=iec --from-unit=1K $folder_size)) - Already consolidated. Skipping calculation.${RESET}"
            fi
            continue
        fi
        # --- END Check ---

        # Get total size of all fragments for this specific folder (NOT the entire share)
        # This is used for logging/planning output
        TOTAL_FOLDER_SIZE=0
        for d_path in /mnt/{disk[1-9]{,[0-9]},cache}; do
            if [ -d "$d_path/$share_component" ]; then
                current_folder_on_disk_size=$(du -s "$d_path/$share_component" 2>/dev/null | cut -f 1)
                TOTAL_FOLDER_SIZE=$((TOTAL_FOLDER_SIZE + current_folder_on_disk_size))
            fi
        done
        # Sanity check for size: if no fragments found with size, skip.
        if [ "$TOTAL_FOLDER_SIZE" -eq 0 ]; then
              printf "%b\n" "${YELLOW}  [SKIP]: '${share_component}' - No file fragments found. Skipping.${RESET}"
              continue
        fi
        
        # Reset candidate file
        > "$TEMP_CANDIDATES"
        
        # 2a. Iterate through all disks to find valid candidates
        for d_path in /mnt/{disk[1-9]{,[0-9]},cache}; do
            disk_name="${d_path#/mnt/}"
            
            # --- 1. Calculate Required Space (Cost) ---
            
            # Size of the current folder fragment on this specific disk
            if [ -d "$d_path/$share_component" ]; then
                current_folder_on_disk_size=$(du -s "$d_path/$share_component" 2>/dev/null | cut -f 1)
            else
                current_folder_on_disk_size=0
            fi

            # REQUIRED_SPACE: Total size of all fragments (TOTAL_FOLDER_SIZE) minus the size already on this disk.
            # This is the net space needed to move all other fragments here.
            REQUIRED_SPACE=$((TOTAL_FOLDER_SIZE - current_folder_on_disk_size))
            if [ "$REQUIRED_SPACE" -lt 0 ]; then REQUIRED_SPACE=0; fi
            
            # --- 2. Safety Check (Must pass this to be considered) ---
            DFREE="${DISK_FREE[$disk_name]}"
            
            # Check if Free Space after move meets the minimum safety margin
            if [ "$((DFREE - REQUIRED_SPACE))" -lt "$ACTIVE_MIN_FREE_KB" ]; then
                [ $verbose -gt 2 ] && printf "%b\n" "    ${YELLOW}$disk_name FAILED safety check. Free: $(numfmt --to=iec --from-unit=1K $DFREE) vs Needed: $(numfmt --to=iec --from-unit=1K $REQUIRED_SPACE). Skipping disk.${RESET}"
                continue # Skip to next disk
            fi
            
            # --- 3. Optimization Metrics (Only for valid candidates) ---
            CURRENT_FREE_SPACE="$DFREE"
            CURRENT_FOLDER_PATH="$d_path/$share_component"

            # Count files for the current folder fragment on this disk
            if [ -d "$CURRENT_FOLDER_PATH" ]; then
                CURRENT_FILE_COUNT=$(find "$CURRENT_FOLDER_PATH" -type f 2>/dev/null | wc -l)
            else
                CURRENT_FILE_COUNT=0
            fi
            
            # Store disk metrics for later sorting: FileCount,FreeSpace,DiskName
            printf "%s,%s,%s\n" "$CURRENT_FILE_COUNT" "$CURRENT_FREE_SPACE" "$disk_name" >> "$TEMP_CANDIDATES"
            
            [ $verbose -gt 2 ] && printf "%b\n" "    ${GREEN}$disk_name PASSED. Metrics: Files=$CURRENT_FILE_COUNT, Free=$(numfmt --to=iec --from-unit=1K $CURRENT_FREE_SPACE)${RESET}"

        done # End disk loop
        
        # 2b. Select the best destination disk from the candidates
        BEST_DEST_DISK=""
        
        if [ -s "$TEMP_CANDIDATES" ]; then
            # Sort the candidates:
            # 1. Primary: Sort by File Count (Field 1) - Numeric, Reverse (Highest first)
            # 2. Secondary: Sort by Free Space (Field 2) - Numeric, Reverse (Highest first, for tie-breaking)
            TOP_CANDIDATE=$(sort -t, -k1,1nr -k2,2nr "$TEMP_CANDIDATES" | head -n 1)
            
            # Extract metrics from the top candidate
            BEST_DEST_DISK=$(echo "$TOP_CANDIDATE" | cut -d, -f3)
            MAX_FILE_COUNT=$(echo "$TOP_CANDIDATE" | cut -d, -f1)
            MAX_FREE_SPACE=$(echo "$TOP_CANDIDATE" | cut -d, -f2)

            # Record the move in the plan
            PLAN_ARRAY+=("$share_component|$BEST_DEST_DISK")
            
            # Print plan item
            printf "%b\n" "  ${GREEN}[PLAN]: Consolidate '${share_component}' -> ${BLUE}$BEST_DEST_DISK${RESET} (Size: $(numfmt --to=iec --from-unit=1K $TOTAL_FOLDER_SIZE))"
            printf "%b\n" "             Priority: Files=${BLUE}$MAX_FILE_COUNT${RESET}, Free=$(numfmt --to=iec --from-unit=1K $MAX_FREE_SPACE)${RESET}"

        else
            # Use ACTIVE_MIN_FREE_KB here
            printf "%b\n" "${RED}  [SKIP]: '${share_component}' (Size: $(numfmt --to=iec --from-unit=1K $TOTAL_FOLDER_SIZE)) - No disk meets the $(numfmt --to=iec --from-unit=1K $ACTIVE_MIN_FREE_KB) safety margin requirement.${RESET}"
        fi

    done < <(find "$BASE_SHARE" -mindepth 1 -maxdepth 1 -type d \
        -not -name '.trash' \
        -not -name '.recycle' \
        -not -name '.Recycle') # Find all subdirectories
    
    # Cleanup temporary file
    rm -f "$TEMP_CANDIDATES"

    # 3. Execute the Plan (WITH PROGRESS INDICATOR)
    echo ""
    printf "%b\n" "${CYAN}--------------------------------------------------------${RESET}"
    if [ "${#PLAN_ARRAY[@]}" -eq 0 ]; then
        printf "%b\n" "${YELLOW}The plan is empty. No moves required or possible.${RESET}"
        return 0
    fi
    
    if [ "$dry_run" = true ]; then
        printf "%b\n" "${YELLOW}PLAN COMPLETE. Rerun with -f to execute moves.${RESET}"
        return 0
    fi
    
    printf "%b\n" "${CYAN}Executing Plan...${RESET}"
    
    # --- ADDITIONS FOR PROGRESS INDICATOR START ---
    local TOTAL_MOVES=${#PLAN_ARRAY[@]}
    local CURRENT_MOVE_INDEX=1
    
    # Display the total number of items to move
    printf "%b\n" "${CYAN}Total Folders to Move: ${BLUE}$TOTAL_MOVES${RESET}${RESET}"
    
    for plan_item in "${PLAN_ARRAY[@]}"; do
        SRCDIR="${plan_item%|*}"        
        DESTDISK="${plan_item#*|}"      
        
        # Display the current move progress
        printf "\n%b\n" "${CYAN}--------------------------------------------------------${RESET}"
        printf "%b\n" "${CYAN}[PROGRESS: ${CURRENT_MOVE_INDEX}/${TOTAL_MOVES}] Moving '${SRCDIR}' to '${DESTDISK}'${RESET}"
        printf "%b\n" "${CYAN}--------------------------------------------------------${RESET}"

        execute_move "$SRCDIR" "$DESTDISK"
        
        printf "%b\n" "${GREEN}Move complete for $SRCDIR.${RESET}"
        
        CURRENT_MOVE_INDEX=$((CURRENT_MOVE_INDEX + 1))
    done
    # --- ADDITIONS FOR PROGRESS INDICATOR END ---

    printf "%b\n" "${GREEN}ALL MOVES COMPLETE.${RESET}"
}

# --- Main Execution Flow ---

# 1. Determine operation mode (Auto or Interactive)
# This block now runs first if no mode flag was supplied.
if [ "$mode_set_by_arg" = false ]; then
    printf "%b\n" "${CYAN}------------------------------------------------${RESET}"
    printf "%b\n" "${CYAN}      UnRAID Consolidation Mode Selection      ${RESET}"
    printf "%b\n" "${CYAN}------------------------------------------------${RESET}"
    echo "No operation mode (-a or -I) was specified. Please select a mode to proceed."
    printf "%b\n" "  ${GREEN}1${RESET}) Interactive Mode: Select folder and destination disk manually."
    printf "%b\n" "  ${GREEN}2${RESET}) Automatic Mode: Scan all shares, plan, and execute optimized moves."
    echo ""

    # FIX: Construct colored prompt using printf -v
    main_prompt_str=""
    printf -v main_prompt_str "Select mode (%b or %b): " "${GREEN}1${RESET}" "${GREEN}2${RESET}"

    while true; do
        read -r -p "$main_prompt_str" MODE_SELECTION
        case "$MODE_SELECTION" in
            1)
                auto_mode=false
                break
                ;;
            2)
                auto_mode=true
                break
                ;;
            *)
                printf "%b\n" "${RED}Invalid selection. Please enter 1 for Interactive or 2 for Automatic.${RESET}"
                ;;
        esac
    done
    echo ""
fi

# 2. Prompt for the base share by scanning /mnt/user/
select_base_share

# 3. Execute the selected mode
if [ "$auto_mode" = true ]; then
    auto_plan_and_execute
else
    interactive_consolidation
fi
