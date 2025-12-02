#!/bin/bash
#To prevent any single array disk hosting a selected share
#from falling below a defined free space threshold.
set -u # Treat unset variables as an error.
set -e # Exit immediately if a command exits with a non-zero status.

# unraid-share-balancer - Target Free Space Enforcement for User Shares
VERSION="1.1.3" # Updated version number for verbose skip message fix

# --- Configuration & Constants ---
# Default share name for display purposes only, the actual selection is dynamic
DEFAULT_SHARE_NAME="Any Share" 
# 500 GB target minimum free space (in 1K blocks, as df/du output)
TARGET_FREE_KB=524288000
# Safety margin for the DESTINATION disk (must remain above this AFTER the move)
DEST_SAFETY_MARGIN_KB=209715200 # 200 GB
# ---------------------------------

# --- ANSI Color Definitions ---
RESET='\033[0m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
# ------------------------------

# --- Variables ---
verbose=1
dry_run=true      # Default to safety (Test mode)
mode_set_by_arg=false
# -------------------

usage(){
cat << EOF
unraid-share-balancer v$VERSION

usage: unraid-share-balancer [options:-h|-t|-r|-v]

This script enforces a minimum free space of $(numfmt --to=iec --from-unit=1K $TARGET_FREE_KB) 
on all array disks that host a selected user share.
It moves the largest subfolders to the freest valid disk until the target is met.

options:
  -h      Display this usage information.
  -t      Perform a test run (Dry Run). No files will be moved. (Default mode)
  -r      Run Mode: Override test mode and force valid moves to be performed.
  -v      Print more information (recommended for detailed logging).

If neither -t nor -r is specified, the script will prompt for the operation mode.
The script will then prompt for which user share(s) to balance.

EOF
}

# --- Argument Parsing ---
while getopts "htrv" opt; do
  case "$opt" in
    h)
      usage
      exit 0
      ;;
    t) 
      dry_run=true
      mode_set_by_arg=true
      ;;
    r) # New flag for Run Mode (Force)
      dry_run=false
      mode_set_by_arg=true
      ;;
    v)
      verbose=$((verbose + 1))
      ;;
    *)
      printf "%b\n" "${YELLOW}Unknown option (ignored): -$OPTARG${RESET}" >&2
      ;;
  esac
done
shift $((OPTIND-1))

# --- Interactive Mode Selection ---
if [ "$mode_set_by_arg" = false ]; then
    printf "%b\n" "${CYAN}------------------------------------------------${RESET}"
    printf "%b\n" "${CYAN}      UnRAID Share Balancer Mode Selection      ${RESET}"
    printf "%b\n" "${CYAN}------------------------------------------------${RESET}"
    echo "No operation mode (-t or -r) was specified. Please select a mode to proceed."
    printf "%b\n" "  ${GREEN}1${RESET}) Test Mode (Dry Run): Plan moves, but DO NOT execute."
    printf "%b\n" "  ${RED}2${RESET}) Run Mode (Move): Plan and EXECUTE all necessary moves."
    echo ""

    # Construct colored prompt using printf -v
    main_prompt_str=""
    printf -v main_prompt_str "Select mode (%b or %b): " "${GREEN}1${RESET}" "${RED}2${RESET}"

    while true; do
        read -r -p "$main_prompt_str" MODE_SELECTION
        case "$MODE_SELECTION" in
            1)
                dry_run=true
                break
                ;;
            2)
                dry_run=false
                break
                ;;
            *)
                printf "%b\\n" "${RED}Invalid selection. Please enter 1 for Dry Run or 2 for Move Mode.${RESET}"
                ;;
        esac
    done
    echo ""
fi

# New function to select one or more shares to balance
select_target_shares() {
    # >>> START FIX: Redirect all interactive output to STDERR (>&2) to prevent capture by command substitution.
    printf "%b\n" "${CYAN}------------------------------------------------${RESET}" >&2
    printf "%b\n" "${CYAN}     UnRAID Share Selection (Step 2/2)          ${RESET}" >&2
    printf "%b\n" "${CYAN}------------------------------------------------${RESET}" >&2

    # Get a list of all non-hidden user shares (excluding .*)
    local IFS=$'\n' 
    local SHARE_LIST=($(find /mnt/user/ -maxdepth 1 -mindepth 1 -type d -not -name ".\*" -printf '%P\n' | sort))
    local IFS=$' '
    
    if [ ${#SHARE_LIST[@]} -eq 0 ]; then
        printf "%b\n" "${RED}ERROR: No user shares found in /mnt/user/. Exiting.${RESET}" >&2
        return 1
    fi

    echo "Available User Shares to Balance:" >&2
    local count=1
    for share in "${SHARE_LIST[@]}"; do
        printf "  %b) %s\n" "${GREEN}$count${RESET}" "$share" >&2
        count=$((count + 1))
    done
    
    echo "" >&2
    echo "Enter the number(s) of the share(s) you wish to balance, separated by spaces (e.g., 1 3 4):" >&2
    
    local selected_shares=()
    while true; do
        # read -p automatically writes the prompt to the terminal
        read -r -p "Share selection: " SHARE_SELECTION_INPUT
        
        # Split input by spaces and validate
        selected_shares=()
        local valid_input=true
        
        for num in $SHARE_SELECTION_INPUT; do
            if ! [[ "$num" =~ ^[0-9]+$ ]]; then
                valid_input=false
                break
            fi
            if [ "$num" -ge 1 ] && [ "$num" -le ${#SHARE_LIST[@]} ]; then
                # Map the input number to the actual share name
                selected_shares+=("${SHARE_LIST[$((num - 1))]}")
            else
                valid_input=false
                break
            fi
        done
        
        if [ "$valid_input" = true ] && [ ${#selected_shares[@]} -gt 0 ]; then
            printf "%b\n" "${GREEN}Selected shares: ${selected_shares[*]}${RESET}" >&2
            break
        else
            printf "%b\n" "${RED}Invalid selection. Please enter valid number(s) separated by spaces.${RESET}" >&2
        fi
    done
    
    # Export the array to STDOUT for the main execution logic to capture
    echo "${selected_shares[@]}" 
    return 0
} # <<< END FIX

# Function to get the current free space in 1K blocks for a disk
# Argument 1: The disk name (e.g., 'disk1')
get_disk_free_kb() {
    local disk_name="$1"
    local d_path="/mnt/$disk_name"
    # df -P ensures POSIX output format, awk '{ print $4 }' gets the 1K-block free space
    local current_free=$(df -P "$d_path" 2>/dev/null | tail -1 | awk '{ print $4 }')
    
    if ! [[ "$current_free" =~ ^[0-9]+$ ]]; then
        echo 0
    else
        echo "$current_free"
    fi
}

# Function to find the best destination disk for a given move size
# Argument 1: Size of the folder to move (in KB)
# Argument 2: Reference array of disk free space (DISK_FREE)
# Argument 3: The target share name (e.g., 'TVSHOWS')
# Output: Disk name (e.g., 'disk3') or empty string if no valid destination found
find_best_destination() {
    local move_size_kb="$1"
    local -n disk_free_ref="$2" # Reference to the associative array
    local target_share_name="$3"
    local best_disk=""
    local max_free=0

    # Dynamically find all disks (disk1, disk2, ..., disk10, etc.)
    for disk_name in $(ls /mnt | grep -E '^disk[0-9]+$'); do
        local disk_path="/mnt/$disk_name"
        local current_free="${disk_free_ref[$disk_name]:-0}" # Get current projected free space
        
        # 1. Must host the target share (e.g., TVSHOWS)
        if [ ! -d "$disk_path/$target_share_name" ]; then
            [ $verbose -gt 1 ] && printf "   [Dest Check]: %s does not contain /%s. Skip.\n" "$disk_name" "$target_share_name"
            continue
        fi

        # 2. Must pass the safety margin after the move
        local projected_free=$((current_free - move_size_kb))
        
        if [ "$projected_free" -lt "$DEST_SAFETY_MARGIN_KB" ]; then
            [ $verbose -gt 1 ] && printf "   [Dest Check]: %s fails safety margin. Projected Free: %s KB. Skip.\n" "$disk_name" "$projected_free"
            continue
        fi

        # 3. Optimization: Find the disk with the MOST current free space
        if [ "$current_free" -gt "$max_free" ]; then
            max_free="$current_free"
            best_disk="$disk_name"
        fi
    done

    echo "$best_disk"
}

# Function to safely execute rsync move
# Argument 1: The full path to the source folder on the physical disk (e.g., /mnt/disk1/ShareName/ShowName)
# Argument 2: The destination disk name (e.g., 'disk5')
# Argument 3: The target share name (e.g., 'TVSHOWS')
execute_move() {
    local source_full_path="$1"
    local dest_disk="$2"
    local target_share_name="$3"
    
    # Extract the ShowName (e.g., 'ShowName')
    local show_name="${source_full_path##*/}"
    
    # Construct the destination path (e.g., /mnt/disk5/ShareName/ShowName)
    local dest_path="/mnt/$dest_disk/$target_share_name/$show_name"
    
    printf "%b\n" "${CYAN}>> Moving '${show_name}' from ${source_full_path#/mnt/} to ${dest_disk}/${target_share_name}${RESET}"

    if [ "$dry_run" = true ]; then
        [ $verbose -gt 0 ] && printf "%b\n" "   ${YELLOW}[DRY RUN] Would move to '$dest_path'.${RESET}"
        return 0
    fi
    
    # Ensure destination directory exists on the target disk
    mkdir -p "$dest_path"

    # Use rsync to move contents (copy and delete source)
    # -a: archive mode (preserves permissions, ownership, etc.)
    # -v: verbose
    # -h: human-readable numbers
    # --remove-source-files: deletes files in source after successful transfer
    rsync -avh --remove-source-files "$source_full_path/" "$dest_path/"
    
    if [ $? -eq 0 ]; then
        # Clean up empty directories: start with deep folders and work up
        find "$source_full_path" -type d -empty -delete
        # Attempt to remove the share root on that disk if it's now empty (unlikely but safe)
        rmdir "$source_full_path" 2>/dev/null || true
        printf "%b\n" "${GREEN}   Move successful.${RESET}"
    else
        printf "%b\n" "${RED}   WARNING: Rsync failed. Cleanup skipped.${RESET}" >&2
    fi
}


# --- Main Logic (now accepts target share name as argument) ---
# The main balancing logic is now encapsulated to process one share at a time.
disk_balancer() {
    local TARGET_SHARE_NAME="$1"
    
    printf "\n%b\n" "${CYAN}=======================================================${RESET}"
    printf "%b\n" "${CYAN}     Starting BALANCING for share: ${BLUE}$TARGET_SHARE_NAME${RESET}"
    printf "%b\n" "${CYAN}=======================================================${RESET}"
    printf "%b\n" "Target Min Free: ${BLUE}$(numfmt --to=iec --from-unit=1K $TARGET_FREE_KB)${RESET}"
    printf "%b\n" "Destination Safety Margin: ${BLUE}$(numfmt --to=iec --from-unit=1K $DEST_SAFETY_MARGIN_KB)${RESET}"
    
    if [ "$dry_run" = true ]; then
        printf "%b\n" ">> MODE: ${YELLOW}DRY RUN (Planning Only, no files will move)${RESET}"
    else
        printf "%b\n" ">> MODE: ${RED}RUN MODE (Files WILL be moved)${RESET}"
    fi
    echo ""

    declare -A DISK_FREE          # Associative array to store current projected free space
    declare -a EVACUATION_DISKS=() # Array of disks that are below the target free space
    
    # =====================================================================
    # STEP 1: IDENTIFY DISKS AND EVACUATION TARGETS
    # =====================================================================
    
    printf "%b\n" "1. Scanning disks for free space and share location..."
    # Dynamically find all disks (disk1, disk2, ..., disk10, etc.)
    for disk_name in $(ls /mnt | grep -E '^disk[0-9]+$'); do
        local disk_path="/mnt/$disk_name"

        # Check if disk exists and contains the share
        if [ -d "$disk_path/$TARGET_SHARE_NAME" ]; then
            DFREE=$(get_disk_free_kb "$disk_name")
            DISK_FREE["$disk_name"]="$DFREE"
            
            local free_iec=$(numfmt --to=iec --from-unit=1K $DFREE)
            
            if [ "$DFREE" -lt "$TARGET_FREE_KB" ]; then
                EVACUATION_DISKS+=("$disk_name")
                printf "  ${RED}>> %s: Free=%s (BELOW TARGET)${RESET}\n" "$disk_name" "$free_iec"
            else
                printf "  ${GREEN}>> %s: Free=%s (OK)${RESET}\n" "$disk_name" "$free_iec"
            fi
        fi
    done

    if [ ${#EVACUATION_DISKS[@]} -eq 0 ]; then
        printf "\n%b\n" "${GREEN}No disks hosting $TARGET_SHARE_NAME are below the $(numfmt --to=iec --from-unit=1K $TARGET_FREE_KB) target. Nothing to do for this share.${RESET}"
        return 0
    fi
    
    # =====================================================================
    # STEP 2: CREATE AND EXECUTE MOVE PLAN
    # =====================================================================
    
    printf "\n%b\n" "2. Creating move plan for ${#EVACUATION_DISKS[@]} disks..."

    local total_moved_kb=0
    local move_count=0

    # Sort disks by how full they are (lowest free space first)
    IFS=$'\n' EVACUATION_DISKS=($(for d in "${EVACUATION_DISKS[@]}"; do echo "${DISK_FREE[$d]}|$d"; done | sort -n))
    unset IFS

    for disk_entry in "${EVACUATION_DISKS[@]}"; do
        # Extract disk name from sorted entry
        local source_disk="${disk_entry##*|}"
        local source_path="/mnt/$source_disk/$TARGET_SHARE_NAME"
        
        # Recalculate the free space based on current projected state
        local DFREE="${DISK_FREE[$source_disk]:-0}"
        
        # Calculate the required amount to move
        local REQUIRED_MOVE_KB=$((TARGET_FREE_KB - DFREE))
        
        if [ "$REQUIRED_MOVE_KB" -le 0 ]; then
            printf "   ${GREEN}%s already meets the target. Skip.${RESET}\n" "$source_disk"
            continue
        fi

        printf "\n%b\n" "${YELLOW}Processing ${source_disk} (Needs to move $(numfmt --to=iec --from-unit=1K $REQUIRED_MOVE_KB))${RESET}"
        
        local current_moved_kb=0

        # Find all subfolders (TV show folders) on this disk, sorted by size (largest first)
        local IFS=$'\n' 
        # Note: We are using du -k --max-depth=1 "$source_path" | sort -rn | grep -v "$source_path$"
        # This approach assumes subfolders of the share are the items to move (e.g., ShowName)
        local CANDIDATES=($(du -k --max-depth=1 "$source_path" | sort -rn | grep -v "$source_path$"))
        local IFS=$' '
        
        for candidate in "${CANDIDATES[@]}"; do
            local folder_size_kb=$(echo "$candidate" | awk '{print $1}')
            local folder_full_path=$(echo "$candidate" | awk '{print $2}')
            local show_name="${folder_full_path##*/}"

            # Ensure we don't try to move the share root directory itself if the path matches exactly
            if [ "$folder_full_path" = "$source_path" ]; then
                continue
            fi
            
            # Only move if we still need to evacuate data
            if [ "$current_moved_kb" -ge "$REQUIRED_MOVE_KB" ]; then
                break
            fi
            
            # Find the best valid destination disk
            local dest_disk=$(find_best_destination "$folder_size_kb" DISK_FREE "$TARGET_SHARE_NAME")

            if [ -n "$dest_disk" ] && [ "$dest_disk" != "$source_disk" ]; then
                
                # Update tracking variables
                move_count=$((move_count + 1))
                current_moved_kb=$((current_moved_kb + folder_size_kb))
                total_moved_kb=$((total_moved_kb + folder_size_kb))

                # Update the projected free space for both source and destination disks
                # FIX: Use parameter expansion (:-0) to prevent "unbound variable" error under set -u
                DISK_FREE["$source_disk"]=$((${DISK_FREE["$source_disk"]:-0} + folder_size_kb))
                DISK_FREE["$dest_disk"]=$((${DISK_FREE["$dest_disk"]:-0} - folder_size_kb))

                printf "  ${BLUE}[PLAN %d]: Move %s (%s) from %s to %s.${RESET}\n" \
                    "$move_count" \
                    "$show_name" \
                    "$(numfmt --to=iec --from-unit=1K $folder_size_kb)" \
                    "$source_disk" \
                    "$dest_disk"

                # Execute the move if not in dry run mode
                execute_move "$folder_full_path" "$dest_disk" "$TARGET_SHARE_NAME"
            else
                # Only show skip message in verbose mode (e.g., -v)
                [ $verbose -gt 1 ] && printf "  ${YELLOW}[SKIP]: %s (%s) - No valid destination disk found.${RESET}\n" \
                    "$show_name" \
                    "$(numfmt --to=iec --from-unit=1K $folder_size_kb)"
            fi
        done
        
        # Print final status for the source disk after moves
        local final_dfree_iec=$(numfmt --to=iec --from-unit=1K ${DISK_FREE["$source_disk"]})
        printf "  ${GREEN}Status on %s: Moved %s. Projected Final Free: %s${RESET}\n" \
            "$source_disk" \
            "$(numfmt --to=iec --from-unit=1K $current_moved_kb)" \
            "$final_dfree_iec"
    done

    # =====================================================================
    # STEP 3: FINAL REPORT
    # =====================================================================
    echo ""
    printf "%b\n" "${CYAN}--------------------------------------------------------${RESET}"
    printf "%b\n" "${GREEN}BALANCING COMPLETED FOR SHARE: $TARGET_SHARE_NAME${RESET}"
    printf "%b\n" "Total Folders Moved (Planned): ${BLUE}$move_count${RESET}"
    printf "%b\n" "Total Data Moved (Planned): ${BLUE}$(numfmt --to=iec --from-unit=1K $total_moved_kb)${RESET}"
    printf "%b\n" "${CYAN}--------------------------------------------------------${RESET}"
    
    if [ "$dry_run" = true ]; then
        printf "%b\n" "${YELLOW}This was a DRY RUN. Rerun with -r or select option 2 to execute these moves.${RESET}"
    fi
}

# --- Main Execution Flow ---
main() {
    # 1. Select the target shares interactively
    local SHARES_TO_BALANCE_STR
    SHARES_TO_BALANCE_STR=$(select_target_shares)
    
    if [ $? -ne 0 ] || [ -z "$SHARES_TO_BALANCE_STR" ]; then
        printf "%b\n" "${RED}No shares selected. Exiting.${RESET}" >&2
        exit 1
    fi

    # Convert the space-separated string back into an array
    local SHARES_TO_BALANCE=($SHARES_TO_BALANCE_STR)
    
    # 2. Iterate over all selected shares and run the balancer logic
    for share in "${SHARES_TO_BALANCE[@]}"; do
        disk_balancer "$share"
    done
    
    printf "\n%b\n" "${GREEN}ALL SELECTED SHARE BALANCING COMPLETE!${RESET}"
}

main
