# Script prompts for source folder, then asks for Automatic or Interactive mode. Automatic requires the -f flag (./pai_consld8.sh -f).
# Using hte Auto and Force the flag -a -f will consold8 all files to drives where the share exists with the most data.
#The script moves all files including hidden files.
#
#Interactive mode can be started from comand line with -I (uppercase)
#
# -f (force is required to actually move files)
#
#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.
# consld8-auto - Fully Automated or Interactive Consolidation for unRAID

# --- Configuration & Constants ---
BASE_SHARE="/mnt/user/TVSHOWS"
# 200 GB minimum free space safety margin (in 1K blocks, as df/du output)
MIN_FREE_SPACE_KB=209715200
# ---------------------------------

usage(){
cat << EOF

usage: consld8-auto [options:-h|-t|-f|-v|-a|-I]

This script has two modes:
1. Interactive Mode (Default, or with -I): Prompts for folder and disk selection.
2. Automatic Mode (-a): Scans all folders and generates an optimized move plan.

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
shopt -s nullglob   # enable nullglob to remove words with no matching filenames
[ ${DEBUG:=0} -gt 0 ] && set -x

# --- Variables ---
verbose=1
dry_run=true      # Default to safety (Test mode)
auto_mode=false   # Default to interactive mode
mode_set_by_arg=false # New flag to track if mode was set by command-line argument

# --- Argument Parsing ---
while getopts "htfvaI" opt; do
  case "$opt" in
    h)
      usage
      exit 0
      ;;
    t) # Specify test mode
      dry_run=true
      mode_set_by_arg=true
      ;;
    f) # Override test mode and force action
      dry_run=false
      mode_set_by_arg=true
      ;;
    v)
      verbose=$((verbose + 1))
      ;;
    a) # Activate Automatic Mode
      auto_mode=true
      mode_set_by_arg=true
      ;;
    I) # Activate Interactive Mode (Explicitly selected)
      auto_mode=false
      mode_set_by_arg=true
      ;;
    *)
      echo "Unknown option (ignored): -$OPTARG" >&2
      ;;
  esac
done
shift $((OPTIND-1))

# --- Helper Functions ---

# Function to safely execute rsync move
execute_move() {
    local src_dir_name="$1"
    local dest_disk="$2"
    
    echo ">> Preparing to move '${src_dir_name}' to disk '$dest_disk'..."
    
    local dest_path="/mnt/$dest_disk/$src_dir_name"
    
    if [ "$dry_run" = true ]; then
        echo "   [DRY RUN] Would consolidate all fragments of '$src_dir_name' to '$dest_path'."
        echo "   [DRY RUN] Would use rsync to move and remove source files."
        return 0
    fi
    
    # Ensure destination directory exists on the target disk
    mkdir -p "$dest_path"

    # Loop through all possible source disks (including cache)
    for d in /mnt/{disk[1-9]{,[0-9]},cache}; do
        local source_path="$d/$src_dir_name"
        
        # Check if source directory exists AND it's not the destination disk
        if [ -d "$source_path" ] && [ "/mnt/$dest_disk" != "$d" ]; then
            [ $verbose -gt 0 ] && echo "   Merging data from $d..."

            # Use rsync to move contents (The safe move: copy and delete source)
            # The trailing slash on the source path means copy *contents* of the directory
            rsync -avh --remove-source-files "$source_path/" "$dest_path/"
            
            if [ $? -eq 0 ]; then
                # Clean up empty directories
                find "$source_path" -type d -empty -delete
                # Attempt to remove the share root on that disk if it's now empty
                rmdir "$source_path" 2>/dev/null || true
            else
                echo "   WARNING: Rsync failed from $source_path. Skipping cleanup." >&2
            fi
        fi
    done
    echo "Move execution complete for $src_dir_name."
}

# Function for manual path entry (used as a fallback/alternative)
configure_manual_base_share() {
    while true; do
        # Use the current BASE_SHARE as the default prompt value
        read -r -p "Enter the base share path (e.g., /mnt/user/TVSHOWS). Current: $BASE_SHARE: " NEW_BASE_SHARE_INPUT
        
        if [ -z "$NEW_BASE_SHARE_INPUT" ]; then
            echo "Using current base share: $BASE_SHARE"
            break
        fi
        
        # Check if the input path exists and is a directory
        if [ -d "$NEW_BASE_SHARE_INPUT" ]; then
            # Remove trailing slash if present
            BASE_SHARE="${NEW_BASE_SHARE_INPUT%/}"
            echo "Base Share set to: $BASE_SHARE"
            break
        else
            echo "Error: '$NEW_BASE_SHARE_INPUT' is not a valid directory. Please try again." >&2
        fi
    done
}


# --- Share Selection Logic (New) ---
select_base_share() {
    echo "------------------------------------------------"
    echo "      Select Base Share for Consolidation       "
    echo "------------------------------------------------"
    
    # Scan for top-level user shares in /mnt/user/
    local shares=()
    # Find all top-level directories under /mnt/user/ that are not system files or the root itself
    mapfile -t shares < <(find /mnt/user -maxdepth 1 -mindepth 1 -type d -not -name '@*' -printf '%P\n' 2>/dev/null | sort)

    if [ ${#shares[@]} -eq 0 ]; then
        echo "WARNING: No user shares found in /mnt/user/. Proceeding with manual input."
        # Fallback to manual input if no shares are found
        configure_manual_base_share
        return 0
    fi
    
    echo "Available Shares in /mnt/user/:"
    local i=1
    for share_name in "${shares[@]}"; do
        echo "  $i) $share_name"
        i=$((i + 1))
    done
    echo "  L) Enter a custom path manually."
    
    while true; do
        read -r -p "Enter number of share or 'L' for custom path: " SELECTION
        
        # Check for Manual Input
        if [[ "$SELECTION" == "L" || "$SELECTION" == "l" ]]; then
            configure_manual_base_share
            break
        fi

        # Check for numbered selection
        if [[ "$SELECTION" =~ ^[0-9]+$ ]] && [ "$SELECTION" -ge 1 ] && [ "$SELECTION" -le ${#shares[@]} ]; then
            SELECTED_SHARE_NAME="${shares[$((SELECTION - 1))]}"
            BASE_SHARE="/mnt/user/$SELECTED_SHARE_NAME"
            echo "Base Share set to: $BASE_SHARE"
            break
        else
            echo "Invalid selection. Please enter a number between 1 and ${#shares[@]}, or 'L'." >&2
        fi
    done
    echo ""
}


# --- Interactive Mode Logic ---

interactive_consolidation() {
    echo "------------------------------------------------"
    echo "    UnRAID Consolidation Script (Interactive)   "
    echo "------------------------------------------------"
    
    if [ "$dry_run" = true ]; then
        echo ">> MODE: DRY RUN (Test mode). Add -f to execute moves."
    else
        echo ">> MODE: FORCE (Execution mode). Files WILL be moved."
    fi
    echo ""

    # 1. Select Share/Folder
    
    echo "DEBUG: Scanning for subfolders in $BASE_SHARE..."
    # Get all subdirectories of the base share (e.g., TVSHOWS/Show1, TVSHOWS/Show2)
    mapfile -t FOLDERS < <(find "$BASE_SHARE" -mindepth 1 -maxdepth 1 -type d -printf '%P\n' | sort)

    if [ ${#FOLDERS[@]} -eq 0 ]; then
        echo "ERROR: No subdirectories found in $BASE_SHARE. Exiting." >&2
        exit 1
    fi

    echo "Available Folders in '$BASE_SHARE' to consolidate:"
    local i=1
    for folder in "${FOLDERS[@]}"; do
        # Calculate size for display purposes
        local folder_path="$BASE_SHARE/$folder"
        local folder_size_kb=$(du -s "$folder_path" | cut -f 1)
        local formatted_size=$(numfmt --to=iec --from-unit=1K $folder_size_kb)
        echo "  $i) $folder (Size: $formatted_size)"
        i=$((i + 1))
    done

    while true; do
        read -r -p "Enter the number of the folder to consolidate: " FOLDER_NUM
        if [[ "$FOLDER_NUM" =~ ^[0-9]+$ ]] && [ "$FOLDER_NUM" -ge 1 ] && [ "$FOLDER_NUM" -le ${#FOLDERS[@]} ]; then
            SELECTED_FOLDER="${FOLDERS[$((FOLDER_NUM - 1))]}"
            # The full share component path (e.g., TVSHOWS/ShowName)
            SHARE_COMPONENT="${BASE_SHARE#/mnt/user/}/$SELECTED_FOLDER"
            break
        else
            echo "Invalid selection. Please enter a number between 1 and ${#FOLDERS[@]}."
        fi
    done

    echo "Selected Folder: $SELECTED_FOLDER"
    echo ""

    # 2. Select Destination Disk
    
    echo "DEBUG: Discovering disks in /mnt/{disk*,cache}..."
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
        echo "ERROR: No disks or cache drives found in /mnt (looking for /mnt/disk* or /mnt/cache). Cannot proceed." >&2
        return 1
    fi
    
    echo "Available Destination Disks:"
    i=1
    for disk in "${DISKS[@]}"; do
        local disk_path="/mnt/$disk"
        # CRITICAL FIX: Robustly get the Available blocks
        local current_free=$(df -P "$disk_path" 2>/dev/null | tail -1 | awk '{ print $4 }')
        local formatted_free=$(numfmt --to=iec --from-unit=1K "${current_free:-0}")
        echo "  $i) $disk (Free: $formatted_free)"
        i=$((i + 1))
    done

    while true; do
        read -r -p "Enter the number of the destination disk: " DISK_NUM
        if [[ "$DISK_NUM" =~ ^[0-9]+$ ]] && [ "$DISK_NUM" -ge 1 ] && [ "$DISK_NUM" -le ${#DISKS[@]} ]; then
            SELECTED_DISK="${DISKS[$((DISK_NUM - 1))]}"
            break
        else
            echo "Invalid selection. Please enter a number between 1 and ${#DISKS[@]}."
        fi
    done

    echo "Selected Destination Disk: $SELECTED_DISK"
    echo ""
    
    # 3. Confirmation and Execution

    if [ "$dry_run" = true ]; then
        local confirmation_message="DRY RUN enabled."
    else
        local confirmation_message="This will MOVE all files. THIS CANNOT BE UNDONE."
    fi

    echo "--- CONFIRMATION ---"
    echo "Folder to Consolidate: $SELECTED_FOLDER (Full Path: $SHARE_COMPONENT)"
    echo "Target Destination Disk: $SELECTED_DISK (/mnt/$SELECTED_DISK/$SHARE_COMPONENT)"
    echo "$confirmation_message"
    echo "--------------------"

    while true; do
        read -r -p "Proceed with consolidation? (yes/no): " CONFIRM
        case "$CONFIRM" in
            [Yy][Ee][Ss])
                execute_move "$SHARE_COMPONENT" "$SELECTED_DISK"
                return 0
                ;;
            [Nn][Oo])
                echo "Consolidation cancelled by user."
                return 1
                ;;
            *)
                echo "Please answer 'yes' or 'no'."
                ;;
        esac
    done
}


# --- Core Logic for Automated Planning (Fixed the 'end' syntax) ---

auto_plan_and_execute() {
    echo "--------------------------------------------------------"
    echo "  Starting FULL AUTOMATED CONSOLIDATION PLANNER         "
    echo "--------------------------------------------------------"
    echo "Base Share: $BASE_SHARE"
    echo "Safety Margin: $(numfmt --to=iec --from-unit=1K $MIN_FREE_SPACE_KB) minimum free space"
    
    if [ "$dry_run" = true ]; then
        echo ">> MODE: DRY RUN (Planning Only, no files will move)"
    else
        echo ">> MODE: FORCE (Files WILL be moved)"
    fi
    echo ""

    # Declare associative arrays to track disk state during planning
    declare -A DISK_FREE
    declare -A DISK_SHARE_USAGE
    
    # 1. Initialize Disk Free Space and Share Usage for all disks
    echo "Scanning initial disk state..."
    echo "DEBUG: Discovering disks in /mnt/{disk*,cache} and fetching free space..."
    for d_path in /mnt/{disk[1-9]{,[0-9]},cache}; do
        disk_name="${d_path#/mnt/}"
        
        # CRITICAL FIX: Robustly get the Available blocks using df -P
        current_free=$(df -P "$d_path" | tail -1 | awk '{ print $4 }')
        
        # Check if current_free is empty or non-numeric (setting to 0 if invalid)
        if ! [[ "$current_free" =~ ^[0-9]+$ ]]; then
            current_free=0
            echo "  WARNING: Failed to read free space for $disk_name. Assuming 0KB free."
        fi
        
        DISK_FREE["$disk_name"]="$current_free"

        # Calculate share usage (DUSAGE) for the entire BASE_SHARE on this disk
        # Use find to accurately get the path relative to /mnt/user/
        share_path_relative="${BASE_SHARE#/mnt/user/}"
        
        if [ -d "$d_path/$share_path_relative" ]; then
            current_share_usage=$(du -s "$d_path/$share_path_relative" | cut -f 1)
        else
            current_share_usage=0
        fi
        DISK_SHARE_USAGE["$disk_name"]="$current_share_usage"
        
        [ $verbose -gt 1 ] && echo "  $disk_name: Free=$(numfmt --to=iec --from-unit=1K ${DISK_FREE[$disk_name]}), ShareUsed=$(numfmt --to=iec --from-unit=1K ${DISK_SHARE_USAGE[$disk_name]})"
    done
    
    # Array to hold the final execution plan
    PLAN_ARRAY=()
    
    # 2. Iterate through all subdirectories and create the plan
    echo ""
    echo "Generating Consolidation Plan..."
    
    # Loop through subdirectories of the base share (e.g., TVSHOWS/Show1, TVSHOWS/Show2)
    while IFS= read -r full_src_path; do
        
        share_component="${full_src_path#/mnt/user/}" # TVSHOWS/ShowName
        if [ -z "$share_component" ]; then continue; fi
        
        folder_name="${full_src_path##*/}" # Just the folder name (e.g., ShowName)
        folder_size=$(du -s "$full_src_path" | cut -f 1)
        
        if [ "$folder_size" -lt 10 ]; then continue; fi

        # --- NEW LOGIC: Check if folder is already consolidated ---
        CONSOLIDATED_DISK_COUNT=0
        for d_path in /mnt/{disk[1-9]{,[0-9]},cache}; do
            # Check if the folder path exists on this physical disk
            if [ -d "$d_path/$share_component" ]; then
                
                # *** FIX FOR BROKEN PIPE ERROR ***
                # Check if it contains files by capturing the output of find | head
                if [ -n "$(find "$d_path/$share_component" -mindepth 1 -type f 2>/dev/null | head -n 1)" ]; then
                     CONSOLIDATED_DISK_COUNT=$((CONSOLIDATED_DISK_COUNT + 1))
                fi
                # --- END FIX ---
            fi
        done

        if [ "$CONSOLIDATED_DISK_COUNT" -le 1 ]; then
            echo "  [SKIP]: '${share_component}' (Size: $(numfmt --to=iec --from-unit=1K $folder_size)) - Already consolidated to $CONSOLIDATED_DISK_COUNT disk(s). Skipping calculation."
            continue
        fi
        # --- END NEW LOGIC ---

        # Tracking variables for the new priority logic
        MAX_FILE_COUNT=-1
        MAX_FREE_SPACE=-1
        BEST_DEST_DISK=""
        
        # Get total usage of the entire share across all disks
        TOTAL_SHARE_SIZE=0
        for disk_name in "${!DISK_SHARE_USAGE[@]}"; do
              TOTAL_SHARE_SIZE=$((TOTAL_SHARE_SIZE + DISK_SHARE_USAGE[$disk_name]))
        done

        # 2a. Find the best destination disk using new File Count > Free Space priority
        for d_path in /mnt/{disk[1-9]{,[0-9]},cache}; do
            disk_name="${d_path#/mnt/}"
            
            # --- 1. Calculate Required Space (Cost) ---
            # Current usage of this folder on this specific disk
            if [ -d "$d_path/$share_component" ]; then
                current_folder_on_disk_size=$(du -s "$d_path/$share_component" | cut -f 1)
            else
                current_folder_on_disk_size=0
            fi

            # ODUSAGE: Total size to move *to* this disk (Total Share Size - current usage on this disk)
            ODUSAGE=$((TOTAL_SHARE_SIZE - DISK_SHARE_USAGE[$disk_name])) 

            # REQUIRED_SPACE: Net space required on this disk
            REQUIRED_SPACE=$((ODUSAGE - current_folder_on_disk_size))
            if [ "$REQUIRED_SPACE" -lt 0 ]; then REQUIRED_SPACE=0; fi
            
            # --- 2. Safety Check (Must pass this to be considered) ---
            DFREE="${DISK_FREE[$disk_name]}"
            if [ "$((DFREE - REQUIRED_SPACE))" -lt "$MIN_FREE_SPACE_KB" ]; then
                [ $verbose -gt 2 ] && echo "    $disk_name FAILED safety check. Free: $(numfmt --to=iec --from-unit=1K $DFREE) vs Needed: $(numfmt --to=iec --from-unit=1K $REQUIRED_SPACE). Skipping."
                continue # Skip to next disk
            fi
            
            # --- 3. Optimization Metrics (Only for valid candidates) ---
            CURRENT_FREE_SPACE="$DFREE"
            CURRENT_FOLDER_PATH="$d_path/$share_component"

            # Count files for the current folder on this disk
            if [ -d "$CURRENT_FOLDER_PATH" ]; then
                CURRENT_FILE_COUNT=$(find "$CURRENT_FOLDER_PATH" -type f 2>/dev/null | wc -l)
            else
                CURRENT_FILE_COUNT=0
            fi
            
            # --- 4. Decision Logic (Prioritization) ---
            
            # If no disk has been chosen yet, choose this one.
            if [ -z "$BEST_DEST_DISK" ]; then
                BEST_DEST_DISK="$disk_name"
                MAX_FILE_COUNT="$CURRENT_FILE_COUNT"
                MAX_FREE_SPACE="$CURRENT_FREE_SPACE"
                continue
            fi
            
            # Primary Check: Does this candidate have MORE files than the current BEST?
            if [ "$CURRENT_FILE_COUNT" -gt "$MAX_FILE_COUNT" ]; then
                BEST_DEST_DISK="$disk_name"
                MAX_FILE_COUNT="$CURRENT_FILE_COUNT"
                MAX_FREE_SPACE="$CURRENT_FREE_SPACE"
                continue
            fi
            
            # Secondary Check (Tie-breaker): If file counts are equal, does this candidate have MORE free space?
            if [ "$CURRENT_FILE_COUNT" -eq "$MAX_FILE_COUNT" ] && [ "$CURRENT_FREE_SPACE" -gt "$MAX_FREE_SPACE" ]; then
                BEST_DEST_DISK="$disk_name"
                MAX_FILE_COUNT="$CURRENT_FILE_COUNT"
                MAX_FREE_SPACE="$CURRENT_FREE_SPACE"
            fi
        done # End disk loop
        
        # 2b. Finalize move for this folder
        if [ -n "$BEST_DEST_DISK" ]; then
            # Record the move in the plan
            PLAN_ARRAY+=("$share_component|$BEST_DEST_DISK")
            
            # Print plan item
            echo "  [PLAN]: Consolidate '${share_component}' -> $BEST_DEST_DISK (Priority: Files=$MAX_FILE_COUNT, Free=$(numfmt --to=iec --from-unit=1K $MAX_FREE_SPACE)) (Size: $(numfmt --to=iec --from-unit=1K $folder_size))"

        else
            echo "  [SKIP]: '${share_component}' (Size: $(numfmt --to=iec --from-unit=1K $folder_size)) - No disk meets the $(numfmt --to=iec --from-unit=1K $MIN_FREE_SPACE_KB) safety margin requirement."
        fi

    done < <(find "$BASE_SHARE" -mindepth 1 -maxdepth 1 -type d) # Find all subdirectories

    # 3. Execute the Plan (Unchanged logic from here)
    echo ""
    echo "--------------------------------------------------------"
    if [ "${#PLAN_ARRAY[@]}" -eq 0 ]; then
        echo "The plan is empty. No moves required or possible."
        return 0
    fi
    
    if [ "$dry_run" = true ]; then
        echo "PLAN COMPLETE. Rerun with -f to execute moves."
        return 0
    fi
    
    echo "Executing Plan..."
    
    for plan_item in "${PLAN_ARRAY[@]}"; do
        SRCDIR="${plan_item%|*}"        
        DESTDISK="${plan_item#*|}"      
        
        execute_move "$SRCDIR" "$DESTDISK"
        
        echo "Move complete for $SRCDIR."
    done

    echo "ALL MOVES COMPLETE."
}

# --- Main Execution Flow ---

# 0. Prompt for the base share by scanning /mnt/user/
select_base_share

if [ "$mode_set_by_arg" = false ]; then
    echo "------------------------------------------------"
    echo "       UnRAID Consolidation Mode Selection      "
    echo "------------------------------------------------"
    echo "1) Interactive Mode: Select folder and destination disk manually."
    echo "2) Automatic Mode: Scan all shares, plan, and execute optimized moves."
    echo ""

    while true; do
        read -r -p "Select mode (1 or 2): " MODE_SELECTION
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
                echo "Invalid selection. Please enter 1 for Interactive or 2 for Automatic."
                ;;
        esac
    done
    echo ""
fi


if [ "$auto_mode" = true ]; then
    auto_plan_and_execute
else
    interactive_consolidation
fi
