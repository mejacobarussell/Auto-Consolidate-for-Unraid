#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.
#VERSION="3.0.0"  Fix the space in folder names bug.
# consld8-auto - Fully Automated or Interactive Consolidation for unRAID (v2.2.0)
#VERSION="2.2.0"
# --- Version Notes ---
# v2.2.0: FIX - Comprehensive fix for folder names containing spaces.
#         - Replaced all brace-expanded disk loops (/mnt/{disk*,cache}) with a
#           helper function (get_disk_paths) that returns a pre-built array,
#           ensuring variable expansion with spaces is always safe.
#         - Replaced all 'find | while read' patterns with 'find -print0 | while
#           IFS= read -r -d ""' to safely handle spaces and special characters
#           in folder names throughout the script.
#         - Ensured all path variables used in commands are consistently quoted.
#
# v2.1.1: FIX - Corrected a syntax error (line 170) in the 'is_consolidated' 
#         function where the 'if' statement was not closed with 'fi', causing
#         the script to fail on execution.
#
# v2.1.0: ENHANCEMENT - Added flag -s <GB> to non-interactively set the minimum
#         free space Safety Buffer in Gigabytes, overriding the default. Input 
#         validation ensures a positive integer is provided.
#
# v2.0.0: MAJOR RELEASE - Added full support for non-interactive execution (Cron/Automation).
#         - New Flag: -L <path> to non-interactively set the base share path (e.g., /mnt/user/TVSHOWS).
#         - Logic Update: When both -a (Automatic Mode) and -L are provided, the script
#           now bypasses all interactive prompts (Share Selection, Safety Margin, and
#           Scan Verbosity), using script defaults for true non-interactive execution.
#
# v1.2.2: Fixed a color error in 'Progress Only' (Mode 3) scan output where the
#         ANSI reset code ('\033[0m') was printing literally due to incorrect
#         printf formatting. The progress line is now correctly formatted.
#
# v1.2.1: Implemented the 'Progress Only' (Mode 3) scan verbosity option for
#         Automatic Mode, which displays only a real-time folder count during
#         the scan phase, hiding detailed planning output.
#
# v1.1.0: Enhanced the Dry Run Clarity message in execute_move to explicitly
#         remind the user that the -f flag is required at script start to
#         perform actual file movement. Also corrected the 'shopt -s nullglob'
#         syntax in the script's header.
#
# v1.0.3: Minor bug fixes for handling base share paths with trailing slashes.
#
# v1.0.2: Minor logic updates and cleanup, ensuring better robustness in find/du commands.
#
# v1.0.1: Initial release with Interactive (-I) and Auto Planning (-a) modes.
# -------------------
# --- Configuration & Constants ---
# Default settings
DEFAULT_SAFETY_BUFFER_GB="200"
BASE_SHARE="/mnt/user/TVSHOWS"
# ---------------------------------
# --- ANSI Color Definitions ---
RESET='\033[0m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
# ------------------------------

# --- Helper: Build disk path array ---
# Populates a nameref array with all valid /mnt/disk* and /mnt/cache paths.
# Usage: get_disk_paths my_array
get_disk_paths() {
    local -n _out_array="$1"
    _out_array=()
    local d_path
    for d_path in /mnt/disk{1..99} /mnt/cache; do
        if [ -d "$d_path" ]; then
            _out_array+=("$d_path")
        fi
    done
}

usage(){
cat << EOF
consld8-auto v$VERSION
usage: consld8-auto [options:-h|-t|-f|-v|-a|-I|-L <path>|-s <GB>]
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
  -L <path> Set the base share path (e.g., /mnt/user/TVSHOWS) non-interactively. Example "consold8-autov3.sh -L /mnt/user//TVSHOWS -a -s 300 -v -f"
            REQUIRED for non-interactive cron execution with -a.
  -s <GB>   Sets the required minimum Safety Buffer in Gigabytes (GB). Overrides default (${DEFAULT_SAFETY_BUFFER_GB} GB).
EOF
}
# Set shell options
shopt -s nullglob
[ ${DEBUG:=0} -gt 0 ] && set -x
# --- Variables ---
verbose=1
dry_run=true      # Default to safety (Test mode)
auto_mode=false
mode_set_by_arg=false
share_set_by_arg=false
safety_set_by_arg=false
SAFETY_BUFFER_GB="${DEFAULT_SAFETY_BUFFER_GB}"
ACTIVE_MIN_FREE_KB=0
SCRIPT_VERSION="$VERSION"
# -------------------
# --- Argument Parsing ---
while getopts "htfvaIL:s:" opt; do
  case "$opt" in
    h)
      usage
      exit 0
      ;;
    t)
      dry_run=true
      ;;
    f)
      dry_run=false
      ;;
    v)
      verbose=$((verbose + 1))
      ;;
    a)
      auto_mode=true
      mode_set_by_arg=true
      ;;
    I)
      auto_mode=false
      mode_set_by_arg=true
      ;;
    L)
      if [ -d "$OPTARG" ]; then
          BASE_SHARE="${OPTARG%/}"
          share_set_by_arg=true
      else
          printf "%b\n" "${RED}Error: Path provided with -L ('$OPTARG') is not a valid directory. Exiting.${RESET}" >&2
          exit 1
      fi
      ;;
    s)
      if [[ "$OPTARG" =~ ^[0-9]+$ ]] && (( OPTARG > 0 )); then
          SAFETY_BUFFER_GB="$OPTARG"
          safety_set_by_arg=true
      else
          printf "%b\n" "${RED}Error: -s flag requires a positive integer value in Gigabytes. Exiting.${RESET}" >&2
          exit 1
      fi
      ;;
    *)
      printf "%b\n" "${YELLOW}Unknown option (ignored): -$OPTARG${RESET}" >&2
      ;;
  esac
done
shift $((OPTIND-1))

# --- Helper Functions ---

# Function to check if a share component is consolidated (exists on 1 or fewer disks)
# Argument 1: The share component path (e.g., TVSHOWS/ShowName) — may contain spaces
is_consolidated() {
    local share_component="$1"
    local consolidated_disk_count=0
    local disk_paths=()
    get_disk_paths disk_paths

    for d_path in "${disk_paths[@]}"; do
        if [ -d "$d_path/$share_component" ]; then
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
    local disk_paths=()
    get_disk_paths disk_paths

    printf "%b\n" "${CYAN}--- Current Fragmentation Status ---${RESET}"

    for d_path in "${disk_paths[@]}"; do
        local disk_name="${d_path#/mnt/}"
        local full_path="$d_path/$share_component"

        if [ -d "$full_path" ]; then
            local folder_size_kb
            folder_size_kb=$(du -s "$full_path" 2>/dev/null | cut -f 1)

            if [ -n "$folder_size_kb" ] && [ "$folder_size_kb" -gt 0 ]; then
                local formatted_size
                formatted_size=$(numfmt --to=iec --from-unit=1K "$folder_size_kb")
                printf "%b\n" "  -> ${GREEN}$disk_name${RESET} (${BLUE}$full_path${RESET}): ${YELLOW}$formatted_size${RESET}"
                total_size=$((total_size + folder_size_kb))
                fragment_count=$((fragment_count + 1))
            fi
        fi
    done

    if [ "$fragment_count" -eq 0 ]; then
        printf "%b\n" "${YELLOW}Folder appears empty or consolidated to a location not checked.${RESET}"
    else
        local formatted_total_size
        formatted_total_size=$(numfmt --to=iec --from-unit=1K "$total_size")
        printf "%b\n" "${CYAN}Total Size across $fragment_count fragments: ${YELLOW}$formatted_total_size${RESET}"
    fi
    printf "%b\n" "${CYAN}------------------------------------${RESET}"
    echo ""
}

# Function to safely execute rsync move
execute_move() {
    local src_dir_name="$1"
    local dest_disk="$2"
    local disk_paths=()
    get_disk_paths disk_paths

    printf "%b\n" "${CYAN}>> Preparing to move '${src_dir_name}' to disk '$dest_disk'...${RESET}"

    local dest_path="/mnt/$dest_disk/$src_dir_name"

    if [ "$dry_run" = true ]; then
        printf "%b\n" "   ${YELLOW}[DRY RUN] Would consolidate all fragments of '$src_dir_name' to '$dest_path'.${RESET}"
        printf "%b\n" "   ${YELLOW}[DRY RUN] Would use rsync to move and remove source files. Use the -f flag at script start to perform actual moves.${RESET}"
        return 0
    fi

    mkdir -p "$dest_path"

    for d in "${disk_paths[@]}"; do
        local source_path="$d/$src_dir_name"

        if [ -d "$source_path" ] && [ "/mnt/$dest_disk" != "$d" ]; then
            [ $verbose -gt 0 ] && printf "%b\n" "   Merging data from ${BLUE}$d${RESET}..."
            # Trailing slash on source copies *contents* of the directory
            rsync -avh --remove-source-files "$source_path/" "$dest_path/"

            if [ $? -eq 0 ]; then
                find "$source_path" -type d -empty -delete
                rmdir "$source_path" 2>/dev/null || true
            else
                printf "%b\n" "${RED}   WARNING: Rsync failed from '$source_path'. Skipping cleanup.${RESET}" >&2
            fi
        fi
    done
    printf "%b\n" "${GREEN}Move execution complete for '$src_dir_name'.${RESET}"
}

# Function for manual path entry
configure_manual_base_share() {
    while true; do
        local prompt_str
        printf -v prompt_str "Enter the base share path (e.g., /mnt/user/TVSHOWS). Current: %b: " "${BLUE}$BASE_SHARE${RESET}"
        read -r -p "$prompt_str" NEW_BASE_SHARE_INPUT

        if [ -z "$NEW_BASE_SHARE_INPUT" ]; then
            printf "%b\n" "Using current base share: ${BLUE}$BASE_SHARE${RESET}"
            break
        fi

        if [ -d "$NEW_BASE_SHARE_INPUT" ]; then
            BASE_SHARE="${NEW_BASE_SHARE_INPUT%/}"
            printf "%b\n" "Base Share set to: ${BLUE}$BASE_SHARE${RESET}"
            break
        else
            printf "%b\n" "${RED}Error: '$NEW_BASE_SHARE_INPUT' is not a valid directory. Please try again.${RESET}" >&2
        fi
    done
}

# --- Share Selection Logic ---
select_base_share() {
    printf "%b\n" "${CYAN}------------------------------------------------${RESET}"
    printf "%b\n" "${CYAN}       Select Base Share for Consolidation       ${RESET}"
    printf "%b\n" "${CYAN}------------------------------------------------${RESET}"

    local shares=()
    # FIX: Use -print0 / read -d '' to safely handle share names with spaces
    while IFS= read -r -d '' share_name; do
        shares+=("$share_name")
    done < <(find /mnt/user -maxdepth 1 -mindepth 1 -type d -not -name '@*' -printf '%P\0' 2>/dev/null | sort -z)

    if [ ${#shares[@]} -eq 0 ]; then
        printf "%b\n" "${YELLOW}WARNING: No user shares found in /mnt/user/. Proceeding with manual input.${RESET}"
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
        local prompt_str
        printf -v prompt_str "Enter number of share or 'L' for custom path: "
        read -r -p "$prompt_str" SELECTION

        if [[ "$SELECTION" == "L" || "$SELECTION" == "l" ]]; then
            configure_manual_base_share
            break
        fi
        if [[ "$SELECTION" =~ ^[0-9]+$ ]] && [ "$SELECTION" -ge 1 ] && [ "$SELECTION" -le ${#shares[@]} ]; then
            SELECTED_SHARE_NAME="${shares[$((SELECTION - 1))]}"
            BASE_SHARE="/mnt/user/$SELECTED_SHARE_NAME"
            printf "%b\n" "Base Share set to: ${BLUE}$BASE_SHARE${RESET}"
            break
        else
            printf "%b\n" "${RED}Invalid selection. Please enter a number between 1 and ${#shares[@]}, or 'L'.${RESET}" >&2
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

    printf "%b\n" "DEBUG: Scanning for subfolders in ${BLUE}$BASE_SHARE${RESET}..."

    local all_folders=()
    local filtered_folders=()

    # FIX: Use -print0 / read -d '' to safely handle folder names with spaces
    while IFS= read -r -d '' folder_name; do
        all_folders+=("$folder_name")
    done < <(find "$BASE_SHARE" -mindepth 1 -maxdepth 1 -type d \
        -not -name '.trash' \
        -not -name '.recycle' \
        -not -name '.Recycle' \
        -printf '%P\0' | sort -z)

    if [ ${#all_folders[@]} -eq 0 ]; then
        printf "%b\n" "${RED}ERROR: No subdirectories found in '$BASE_SHARE'. Exiting.${RESET}" >&2
        exit 1
    fi

    for folder_name in "${all_folders[@]}"; do
        local share_component="${BASE_SHARE#/mnt/user/}/$folder_name"

        if [ "$filter_consolidated" = true ]; then
            if ! is_consolidated "$share_component"; then
                filtered_folders+=("$folder_name")
            fi
        else
            filtered_folders+=("$folder_name")
        fi
    done

    local FOLDERS=("${filtered_folders[@]}")
    if [ ${#FOLDERS[@]} -eq 0 ]; then
        printf "%b\n" "${GREEN}Success!${RESET} ${YELLOW}Based on your filter, all shares are consolidated or empty. No folders listed for action.${RESET}"
        return 0
    fi

    printf "%b\n" "Available Folders in '${BLUE}$BASE_SHARE${RESET}' to consolidate:"
    local i=1
    for folder in "${FOLDERS[@]}"; do
        local folder_path="$BASE_SHARE/$folder"
        local folder_size_kb
        folder_size_kb=$(du -s "$folder_path" | cut -f 1)
        local formatted_size
        formatted_size=$(numfmt --to=iec --from-unit=1K "$folder_size_kb")
        printf "%b\n" "  ${GREEN}$i${RESET}) $folder (Size: ${BLUE}$formatted_size${RESET})"
        i=$((i + 1))
    done

    while true; do
        local prompt_str
        printf -v prompt_str "Enter the number of the folder to consolidate: "
        read -r -p "$prompt_str" FOLDER_NUM
        if [[ "$FOLDER_NUM" =~ ^[0-9]+$ ]] && [ "$FOLDER_NUM" -ge 1 ] && [ "$FOLDER_NUM" -le ${#FOLDERS[@]} ]; then
            SELECTED_FOLDER="${FOLDERS[$((FOLDER_NUM - 1))]}"
            SHARE_COMPONENT="${BASE_SHARE#/mnt/user/}/$SELECTED_FOLDER"
            break
        else
            printf "%b\n" "${RED}Invalid selection. Please enter a number between 1 and ${#FOLDERS[@]}.${RESET}"
        fi
    done
    printf "%b\n" "Selected Folder: ${BLUE}$SELECTED_FOLDER${RESET}"
    echo ""

    display_folder_fragmentation_info "$SHARE_COMPONENT"

    printf "%b\n" "DEBUG: Discovering disks in /mnt/{disk*,cache}..."
    local disk_paths=()
    get_disk_paths disk_paths

    local disk_names=()
    for d in "${disk_paths[@]}"; do
        disk_names+=("${d#/mnt/}")
    done
    mapfile -t DISKS < <(printf "%s\n" "${disk_names[@]}" | sort)

    if [ ${#DISKS[@]} -eq 0 ]; then
        printf "%b\n" "${RED}ERROR: No disks or cache drives found in /mnt. Cannot proceed.${RESET}" >&2
        return 1
    fi

    echo "Available Destination Disks:"
    i=1
    for disk in "${DISKS[@]}"; do
        local disk_path="/mnt/$disk"
        local current_free
        current_free=$(df -P "$disk_path" 2>/dev/null | tail -1 | awk '{ print $4 }')
        local formatted_free
        formatted_free=$(numfmt --to=iec --from-unit=1K "${current_free:-0}")
        printf "%b\n" "  ${GREEN}$i${RESET}) $disk (Free: ${BLUE}$formatted_free${RESET})"
        i=$((i + 1))
    done

    while true; do
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
        local prompt_str
        printf -v prompt_str "Proceed with consolidation? (%b/yes to confirm, no to cancel): " "${GREEN}Enter${RESET}"
        read -r -p "$prompt_str" CONFIRM
        case "$CONFIRM" in
            ""|[Yy]|[Yy][Ee][Ss])
                execute_move "$SHARE_COMPONENT" "$SELECTED_DISK"
                return 0
                ;;
            [Nn]|[Nn][Oo])
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
    local default_gb="$SAFETY_BUFFER_GB"

    printf "%b\n" "${CYAN}--- Safety Margin Configuration ---${RESET}"
    printf "%b\n" "The current default minimum free space safety margin is ${BLUE}${default_gb} GB${RESET}."
    printf "%b\n" "This script will ensure the destination disk has at least this much free space AFTER the move."

    while true; do
        local prompt_str
        printf -v prompt_str "Enter a new minimum free space amount (in GB) or press Enter to use the default of %b GB: " "${GREEN}${default_gb}${RESET}"
        read -r -p "$prompt_str" USER_INPUT_GB

        if [ -z "$USER_INPUT_GB" ]; then
            printf "%b\n" "Using current safety margin: ${BLUE}${SAFETY_BUFFER_GB} GB${RESET}"
            return 0
        fi
        if [[ "$USER_INPUT_GB" =~ ^[1-9][0-9]*$ ]]; then
            SAFETY_BUFFER_GB="$USER_INPUT_GB"
            printf "%b\n" "Safety margin set to: ${BLUE}${SAFETY_BUFFER_GB} GB${RESET}"
            return 0
        else
            printf "%b\n" "${RED}Invalid input. Please enter a positive whole number for GB or press Enter.${RESET}" >&2
        fi
    done
}

# --- Core Logic for Automated Planning ---
auto_plan_and_execute() {
    printf "%b\n" "${CYAN}--------------------------------------------------------${RESET}"
    printf "%b\n" "${CYAN}     Starting FULL AUTOMATED CONSOLIDATION PLANNER        ${RESET}"
    printf "%b\n" "${CYAN}--------------------------------------------------------${RESET}"

    local fully_automated_cron=false
    if [ "$auto_mode" = true ] && [ "$share_set_by_arg" = true ]; then
        fully_automated_cron=true
    fi

    # 1. Safety Margin Configuration
    if [ "$fully_automated_cron" = false ] && [ "$safety_set_by_arg" = false ]; then
        prompt_for_min_free_space
    else
        if [ "$safety_set_by_arg" = true ]; then
            printf "%b\n" "${YELLOW}Non-Interactive Mode: Using safety margin set by -s: ${BLUE}${SAFETY_BUFFER_GB} GB${RESET}"
        else
            printf "%b\n" "${YELLOW}Non-Interactive Mode: Using default safety margin: ${BLUE}${SAFETY_BUFFER_GB} GB${RESET}"
        fi
    fi

    ACTIVE_MIN_FREE_KB=$((SAFETY_BUFFER_GB * 1024 * 1024))
    printf "%b\n" "Base Share: ${BLUE}$BASE_SHARE${RESET}"
    printf "%b\n" "Safety Margin: ${BLUE}$(numfmt --to=iec --from-unit=1K $ACTIVE_MIN_FREE_KB)${RESET} minimum free space"

    if [ "$dry_run" = true ]; then
        printf "%b\n" ">> MODE: ${YELLOW}DRY RUN (Planning Only, no files will move)${RESET}"
    else
        printf "%b\n" ">> MODE: ${GREEN}FORCE (Files WILL be moved)${RESET}"
    fi
    echo ""

    # 2. Scan Verbosity Configuration
    local scan_verbosity_mode=2

    if [ "$fully_automated_cron" = false ]; then
        printf "%b\n" "${CYAN}--- Scan Verbosity ---${RESET}"
        echo "How much detail do you want to see during the scanning and planning phase?"
        printf "%b\n" "  ${GREEN}1${RESET}) Verbose: Show detailed skip messages AND the full consolidation plan as it is generated."
        printf "%b\n" "  ${GREEN}2${RESET}) Minimal: Hide skip messages, but show the full consolidation plan as it is generated (Default)."
        printf "%b\n" "  ${GREEN}3${RESET}) Progress Only: Show a real-time folder count, but hide all plan output."

        while true; do
            local prompt_str
            printf -v prompt_str "Select display option (%b, %b, or %b): " "${GREEN}1${RESET}" "${GREEN}2${RESET}" "${GREEN}3${RESET}"
            read -r -p "$prompt_str" DISPLAY_SELECTION
            case "$DISPLAY_SELECTION" in
                1) scan_verbosity_mode=1; printf "%b\n" "${YELLOW}Scan set: Verbose mode.${RESET}"; break ;;
                2) scan_verbosity_mode=2; printf "%b\n" "${YELLOW}Scan set: Minimal mode.${RESET}"; break ;;
                3) scan_verbosity_mode=3; printf "%b\n" "${YELLOW}Scan set: Progress Only mode.${RESET}"; break ;;
                *) printf "%b\n" "${RED}Invalid selection. Please enter 1, 2, or 3.${RESET}" ;;
            esac
        done
        echo ""
    else
        printf "%b\n" "${YELLOW}Non-Interactive Mode: Scan verbosity set to Minimal (Mode 2).${RESET}"
    fi

    # 3. Build disk list once — reused throughout
    local disk_paths=()
    get_disk_paths disk_paths

    declare -A DISK_FREE
    declare -A DISK_SHARE_USAGE

    echo "Scanning initial disk state..."
    printf "%b\n" "DEBUG: Discovering disks and fetching free space..."
    for d_path in "${disk_paths[@]}"; do
        local disk_name="${d_path#/mnt/}"
        local current_free
        current_free=$(df -P "$d_path" 2>/dev/null | tail -1 | awk '{ print $4 }')

        if ! [[ "$current_free" =~ ^[0-9]+$ ]]; then
            current_free=0
            printf "%b\n" "${YELLOW}  WARNING: Failed to read free space for $disk_name. Assuming 0KB free.${RESET}"
        fi

        DISK_FREE["$disk_name"]="$current_free"

        local share_path_relative="${BASE_SHARE#/mnt/user/}"
        local current_share_usage=0
        if [ -d "$d_path/$share_path_relative" ]; then
            current_share_usage=$(du -s "$d_path/$share_path_relative" 2>/dev/null | cut -f 1)
        fi
        DISK_SHARE_USAGE["$disk_name"]="${current_share_usage:-0}"

        [ $verbose -gt 1 ] && printf "%b\n" "  $disk_name: Free=${BLUE}$(numfmt --to=iec --from-unit=1K ${DISK_FREE[$disk_name]})${RESET}, ShareUsed=${BLUE}$(numfmt --to=iec --from-unit=1K ${DISK_SHARE_USAGE[$disk_name]})${RESET}"
    done

    PLAN_ARRAY=()

    echo ""
    echo "Generating Consolidation Plan (Prioritizing File Count > Free Space Fallback)..."

    local TEMP_CANDIDATES
    TEMP_CANDIDATES=$(mktemp)

    local FOLDER_COUNTER=0

    # FIX: Use -print0 / read -d '' so folder names with spaces are handled correctly
    while IFS= read -r -d '' full_src_path; do

        FOLDER_COUNTER=$((FOLDER_COUNTER + 1))
        local share_component="${full_src_path#/mnt/user/}"   # e.g., TVSHOWS/Show Name
        if [ -z "$share_component" ]; then continue; fi

        local folder_size
        folder_size=$(du -s "$full_src_path" 2>/dev/null | cut -f 1)

        if [ "${folder_size:-0}" -lt 10 ]; then
            [ "$scan_verbosity_mode" -eq 3 ] && printf "\r%b" "${CYAN}Processing folders: ${BLUE}$FOLDER_COUNTER${RESET}"
            continue
        fi

        # --- Check if folder is already consolidated ---
        if is_consolidated "$share_component"; then
            if [ "$scan_verbosity_mode" -eq 1 ]; then
                printf "%b\n" "${YELLOW}  [SKIP]: '${share_component}' (Size: $(numfmt --to=iec --from-unit=1K $folder_size)) - Already consolidated.${RESET}"
            elif [ "$scan_verbosity_mode" -eq 3 ]; then
                printf "\r%b" "${CYAN}Processing folders: ${BLUE}$FOLDER_COUNTER${RESET}"
            fi
            continue
        fi

        # Get total size across all disk fragments for this folder
        local TOTAL_FOLDER_SIZE=0
        for d_path in "${disk_paths[@]}"; do
            if [ -d "$d_path/$share_component" ]; then
                local frag_size
                frag_size=$(du -s "$d_path/$share_component" 2>/dev/null | cut -f 1)
                TOTAL_FOLDER_SIZE=$((TOTAL_FOLDER_SIZE + ${frag_size:-0}))
            fi
        done

        if [ "$TOTAL_FOLDER_SIZE" -eq 0 ]; then
            if [ "$scan_verbosity_mode" -ne 3 ]; then
                printf "%b\n" "${RED}  [SKIP]: '${share_component}' - No file fragments found. Skipping.${RESET}"
            else
                printf "\r%b" "${CYAN}Processing folders: ${BLUE}$FOLDER_COUNTER${RESET}"
            fi
            continue
        fi

        > "$TEMP_CANDIDATES"

        for d_path in "${disk_paths[@]}"; do
            local disk_name="${d_path#/mnt/}"

            local current_folder_on_disk_size=0
            if [ -d "$d_path/$share_component" ]; then
                current_folder_on_disk_size=$(du -s "$d_path/$share_component" 2>/dev/null | cut -f 1)
            fi

            local REQUIRED_SPACE=$((TOTAL_FOLDER_SIZE - ${current_folder_on_disk_size:-0}))
            if [ "$REQUIRED_SPACE" -lt 0 ]; then REQUIRED_SPACE=0; fi

            local DFREE="${DISK_FREE[$disk_name]}"

            if [ "$((DFREE - REQUIRED_SPACE))" -lt "$ACTIVE_MIN_FREE_KB" ]; then
                [ $verbose -gt 2 ] && printf "%b\n" "    ${YELLOW}$disk_name FAILED safety check.${RESET}"
                continue
            fi

            local CURRENT_FILE_COUNT=0
            if [ -d "$d_path/$share_component" ]; then
                CURRENT_FILE_COUNT=$(find "$d_path/$share_component" -type f 2>/dev/null | wc -l)
            fi

            printf "%s,%s,%s\n" "$CURRENT_FILE_COUNT" "$DFREE" "$disk_name" >> "$TEMP_CANDIDATES"

            [ $verbose -gt 2 ] && printf "%b\n" "    ${GREEN}$disk_name PASSED. Files=$CURRENT_FILE_COUNT, Free=$(numfmt --to=iec --from-unit=1K $DFREE)${RESET}"
        done

        local BEST_DEST_DISK=""
        if [ -s "$TEMP_CANDIDATES" ]; then
            local TOP_CANDIDATE
            TOP_CANDIDATE=$(sort -t, -k1,1nr -k2,2nr "$TEMP_CANDIDATES" | head -n 1)
            BEST_DEST_DISK=$(echo "$TOP_CANDIDATE" | cut -d, -f3)
            local MAX_FILE_COUNT MAX_FREE_SPACE
            MAX_FILE_COUNT=$(echo "$TOP_CANDIDATE" | cut -d, -f1)
            MAX_FREE_SPACE=$(echo "$TOP_CANDIDATE" | cut -d, -f2)

            # FIX: Use | as delimiter in plan array entries — safe even if share_component has spaces
            PLAN_ARRAY+=("$share_component|$BEST_DEST_DISK")

            if [ "$scan_verbosity_mode" -ne 3 ]; then
                printf "%b\n" "  ${GREEN}[PLAN]: Consolidate '${share_component}' -> ${BLUE}$BEST_DEST_DISK${RESET} (Size: $(numfmt --to=iec --from-unit=1K $TOTAL_FOLDER_SIZE))"
                printf "%b\n" "             Priority: Files=${BLUE}$MAX_FILE_COUNT${RESET}, Free=$(numfmt --to=iec --from-unit=1K $MAX_FREE_SPACE)${RESET}"
            else
                printf "\r%b" "${CYAN}Processing folders: ${BLUE}$FOLDER_COUNTER${RESET}"
            fi
        else
            if [ "$scan_verbosity_mode" -ne 3 ]; then
                printf "%b\n" "${RED}  [SKIP]: '${share_component}' (Size: $(numfmt --to=iec --from-unit=1K $TOTAL_FOLDER_SIZE)) - No disk meets the safety margin.${RESET}"
            else
                printf "\r%b" "${CYAN}Processing folders: ${BLUE}$FOLDER_COUNTER${RESET}"
            fi
        fi

    done < <(find "$BASE_SHARE" -mindepth 1 -maxdepth 1 -type d \
        -not -name '.trash' \
        -not -name '.recycle' \
        -not -name '.Recycle' \
        -print0)

    [ "$scan_verbosity_mode" -eq 3 ] && printf "\n"

    rm -f "$TEMP_CANDIDATES"

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

    local TOTAL_MOVES=${#PLAN_ARRAY[@]}
    local CURRENT_MOVE_INDEX=1

    printf "%b\n" "${CYAN}Total Folders to Move: ${BLUE}$TOTAL_MOVES${RESET}"

    for plan_item in "${PLAN_ARRAY[@]}"; do
        # FIX: Split on | so spaces in SRCDIR are preserved correctly
        local SRCDIR="${plan_item%|*}"
        local DESTDISK="${plan_item#*|}"

        printf "\n%b\n" "${CYAN}--------------------------------------------------------${RESET}"
        printf "%b\n" "${CYAN}[PROGRESS: ${CURRENT_MOVE_INDEX}/${TOTAL_MOVES}] Moving '${SRCDIR}' to '${DESTDISK}'${RESET}"
        printf "%b\n" "${CYAN}--------------------------------------------------------${RESET}"
        execute_move "$SRCDIR" "$DESTDISK"

        printf "%b\n" "${GREEN}Move complete for '$SRCDIR'.${RESET}"
        CURRENT_MOVE_INDEX=$((CURRENT_MOVE_INDEX + 1))
    done

    printf "%b\n" "${GREEN}ALL MOVES COMPLETE.${RESET}"
}

# --- Main Execution Flow ---
if [ "$mode_set_by_arg" = false ] && [ "$share_set_by_arg" = false ]; then
    printf "%b\n" "${CYAN}------------------------------------------------${RESET}"
    printf "%b\n" "${CYAN}      UnRAID Consolidation Mode Selection      ${RESET}"
    printf "%b\n" "${CYAN}------------------------------------------------${RESET}"
    echo "No operation mode (-a or -I) was specified. Please select a mode to proceed."
    printf "%b\n" "  ${GREEN}1${RESET}) Interactive Mode: Select folder and destination disk manually."
    printf "%b\n" "  ${GREEN}2${RESET}) Automatic Mode: Scan all shares, plan, and execute optimized moves."
    echo ""
    main_prompt_str=""
    printf -v main_prompt_str "Select mode (%b or %b): " "${GREEN}1${RESET}" "${GREEN}2${RESET}"
    while true; do
        read -r -p "$main_prompt_str" MODE_SELECTION
        case "$MODE_SELECTION" in
            1) auto_mode=false; break ;;
            2) auto_mode=true;  break ;;
            *) printf "%b\n" "${RED}Invalid selection. Please enter 1 for Interactive or 2 for Automatic.${RESET}" ;;
        esac
    done < /dev/tty
    echo ""
fi

if [ "$share_set_by_arg" = false ]; then
    select_base_share
else
    printf "%b\n" "${CYAN}Base Share set non-interactively: ${BLUE}$BASE_SHARE${RESET}"
fi

if [ "$auto_mode" = true ]; then
    auto_plan_and_execute
else
    interactive_consolidation
fi
