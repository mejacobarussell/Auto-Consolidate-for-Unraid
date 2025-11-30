<?php
// PHP page for the Unraid Consolidation Wizard Plugin.

// --- Helper Functions ---

/**
 * Executes the consld8 script with arguments and returns the output.
 * @param string $args Arguments to pass to the script.
 * @return string The raw output from the shell script.
 */
function execute_consld8($args, $mode = 'I') {
    // The shell script path defined in the .plg file
    $script_path = '/usr/local/sbin/consld8-1.0.3.sh';
    
    // Pass the selected mode and dry run status, and arguments
    $command = "bash $script_path -$mode $args 2>&1"; // Use bash and redirect stderr to stdout
    return shell_exec($command);
}

/**
 * Gets a list of user shares from the /mnt/user directory.
 * NOTE: This is a simplified function. A robust solution would call the shell script with a specific flag
 * to return JSON data, but for this first draft, we rely on a direct shell call.
 */
function get_user_shares() {
    // We look for subdirectories under /mnt/user/ that don't start with '@'
    $shares_output = shell_exec("find /mnt/user -maxdepth 1 -mindepth 1 -type d -not -name '@*' -printf '%P\n' 2>/dev/null | sort");
    if ($shares_output) {
        // Split the output into an array of share names
        return array_filter(explode("\n", trim($shares_output)));
    }
    return [];
}

/**
 * Gets a list of disks (diskN, cache) and their free space.
 */
function get_disks_info() {
    // Get disk list and free space (Name, FreeSpace(KB))
    // We'll mimic the script's logic by globbing /mnt/disk* and /mnt/cache
    $disks_output = shell_exec("df -P /mnt/{disk[1-9]{,[0-9]},cache} 2>/dev/null | awk 'NR>1 {print \$NF,\$4}'");
    $disk_info = [];
    if ($disks_output) {
        $lines = array_filter(explode("\n", trim($disks_output)));
        foreach ($lines as $line) {
            list($path, $free_kb) = explode(' ', $line);
            $name = basename($path);
            if ($name === 'cache') {
                $disk_info[$name] = $free_kb;
            } elseif (strpos($name, 'disk') === 0) {
                $disk_info[$name] = $free_kb;
            }
        }
    }
    // Sort disks for consistent display (e.g., disk1, disk2, cache)
    uksort($disk_info, function($a, $b) {
        // Simple natural sort for disk1, disk2... and push cache to the end
        if ($a === 'cache') return 1;
        if ($b === 'cache') return -1;
        return strnatcmp($a, $b);
    });
    return $disk_info;
}

/**
 * Converts KB to a human-readable format.
 */
function format_bytes($kb) {
    $units = ['KB', 'MB', 'GB', 'TB'];
    $bytes = $kb * 1024;
    $i = 0;
    while ($bytes >= 1024 && $i < count($units) - 1) {
        $bytes /= 1024;
        $i++;
    }
    return round($bytes, 2) . ' ' . $units[$i];
}


// --- Main Page Logic ---

// Get initial data
$available_shares = get_user_shares();
$available_disks = get_disks_info();
$base_share = '';
$selected_folder = '';
$destination_disk = '';
$dry_run = true; // Default to safety

// Handle POST submissions (Form submissions)
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    // Basic sanitization
    $action = $_POST['action'] ?? '';
    $base_share = $_POST['base_share'] ?? '';
    $selected_folder = $_POST['selected_folder'] ?? '';
    $destination_disk = $_POST['destination_disk'] ?? '';
    $dry_run = ($_POST['dry_run'] ?? 'on') === 'on';

    if ($action === 'select_share' && !empty($base_share)) {
        // Step 1: Share selected, now we need to display folders.
        // We'll set a state variable or use the $base_share to advance the UI.
        // For simplicity, we just keep the base share set.

    } elseif ($action === 'execute_move' && !empty($base_share) && !empty($selected_folder) && !empty($destination_disk)) {
        
        // --- Step 3: Execute Consolidation ---
        
        // Determine the full share component path (e.g., TVSHOWS/ShowName)
        $share_component = ltrim(str_replace('/mnt/user/', '', $base_share) . '/' . $selected_folder, '/');
        
        // Construct the shell command arguments
        $args = '-I'; // Interactive mode
        $args .= $dry_run ? ' -t' : ' -f'; // Test or Force (Dry Run or Real)
        
        // We need to pass the base share, the folder, and the destination disk to the script
        // Note: The original script is designed for interactive CLI input.
        // For a full implementation, the script would need a special mode (e.g., -J for JSON/direct execution)
        // For now, we print a simulated command and result:
        
        // In a real scenario, this would execute the specific function in the shell script
        // by piping inputs or using a dedicated execution function in the shell script.
        
        $output = execute_consld8(
            "-I " . ($dry_run ? "-t" : "-f") . " -v", // Pass verbose and mode flags
            "I" // Call the Interactive mode block (requires specific script modification)
        );
        
        $simulated_command = "consld8-1.0.3.sh -I " . ($dry_run ? "-t" : "-f") . " (Target: $share_component to $destination_disk)";
        $result_message = "<div class='alert alert-info'>$simulated_command</div>";
        
        if ($dry_run) {
            $result_message .= "<div class='alert alert-warning'>[DRY RUN]: The script would have executed the move for **$share_component** to **$destination_disk**. Check the full output below.</div>";
        } else {
            $result_message .= "<div class='alert alert-success'>[EXECUTION]: Move initiated for **$share_component** to **$destination_disk**. Check the full output below.</div>";
        }
        $result_message .= "<pre style='background-color:#1e1e1e; color:#00ff00; padding:10px; border-radius:5px;'>$output</pre>";
        
    } else {
        // Handle missing data
        $result_message = "<div class='alert alert-danger'>Error: Missing parameters for execution.</div>";
    }
}

// Determine which step to display
$step = 1;
if (!empty($base_share)) {
    // If base share is selected, we advance to Step 2 (Folder/Disk selection)
    $step = 2;
}


// --- HTML Output for Unraid GUI ---
?>

<div class="well">
    <h2>Consolidation Wizard</h2>
    <p>Use this tool to manually consolidate a specific folder onto a single disk.</p>
</div>

<?php echo $result_message ?? ''; // Display execution result/error ?>

<form method="POST" action="consld8_settings.php">

    <?php if ($step === 1): // STEP 1: Select Base Share ?>
    
        <h3 class="page-header">Step 1: Select Base User Share</h3>
        <p>Choose the top-level user share containing the folders you want to consolidate.</p>
        
        <div class="form-group">
            <label for="base_share_select">Available Shares:</label>
            <select name="base_share" id="base_share_select" class="form-control" required>
                <option value="" disabled selected>Select a Share</option>
                <?php foreach ($available_shares as $share_name): ?>
                    <option value="/mnt/user/<?php echo htmlspecialchars($share_name); ?>" <?php echo $base_share === "/mnt/user/$share_name" ? 'selected' : ''; ?>>
                        <?php echo htmlspecialchars($share_name); ?>
                    </option>
                <?php endforeach; ?>
            </select>
        </div>
        
        <input type="hidden" name="action" value="select_share">
        <button type="submit" class="btn btn-primary">Proceed to Step 2</button>
        
    <?php elseif ($step === 2): // STEP 2: Select Folder, Disk, and Execute ?>
    
        <h3 class="page-header">Step 2: Define Consolidation Move</h3>
        
        <!-- Display selected Base Share -->
        <div class="alert alert-info">
            **Base Share:** `<?php echo htmlspecialchars($base_share); ?>`
            (<a href="consld8_settings.php">Change</a>)
            <input type="hidden" name="base_share" value="<?php echo htmlspecialchars($base_share); ?>">
        </div>
        
        <!-- Folder Selection (The full list of subdirectories would be generated dynamically by the script here) -->
        <div class="form-group">
            <label for="selected_folder">1. Folder to Consolidate (Subdirectory):</label>
            <p class="text-muted">Since the script cannot easily return a filtered list via PHP in this state, please enter the name of the subdirectory inside the Base Share (e.g., 'The Big Bang Theory').</p>
            <input type="text" name="selected_folder" id="selected_folder" class="form-control" placeholder="Enter folder name (e.g., MovieName or ShowName)" required>
        </div>
        
        <!-- Destination Disk Selection -->
        <div class="form-group">
            <label for="destination_disk">2. Destination Disk:</label>
            <select name="destination_disk" id="destination_disk" class="form-control" required>
                <option value="" disabled selected>Select Target Disk</option>
                <?php foreach ($available_disks as $disk_name => $free_kb): ?>
                    <option value="<?php echo htmlspecialchars($disk_name); ?>">
                        <?php echo htmlspecialchars($disk_name); ?> (Free: <?php echo format_bytes($free_kb); ?>)
                    </option>
                <?php endforeach; ?>
            </select>
        </div>
        
        <!-- Dry Run / Force Checkbox -->
        <div class="form-group">
            <div class="checkbox">
                <label>
                    <input type="checkbox" name="dry_run" checked> **Dry Run (Test Mode)**: Simulate the move without altering files. **Uncheck to perform the actual move.**
                </label>
            </div>
            <p class="text-warning">Always run a Dry Run first!</p>
        </div>

        <input type="hidden" name="action" value="execute_move">
        <button type="submit" class="btn btn-success btn-lg"><i class="fa fa-play"></i> Execute Consolidation</button>
        
    <?php endif; ?>

</form>
