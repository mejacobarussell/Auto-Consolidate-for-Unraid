<?php

// --- Configuration ---
// Path to your bash script
$scriptPath = '/path/to/your/consld8-1.0.3.sh';

// Directory to store the script output/log. Make sure this is writable by the web server user.
// Using /tmp/ is generally safe, but you might want to adjust this for Unraid logs.
$logFile = '/tmp/consld8_execution.log'; 

// --- Execution Logic ---
$message = '';
$error = '';
$command = '';

// Check if the script file exists and is executable
if (!is_executable($scriptPath)) {
    $error = "ERROR: The script '$scriptPath' does not exist or is not executable. Please verify the \$scriptPath variable.";
} else if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    
    // Determine the arguments based on the selected mode
    $mode = $_POST['mode'] ?? 'dry_run';
    $args = '';
    
    // Set up the arguments for the consld8 script
    // -a: Automatic Mode (Non-interactive planning)
    // -v: Verbose output (Recommended for automatic mode)
    if ($mode === 'force_move') {
        // -f: Force move (Override dry run)
        $args = '-a -f -v'; 
        $message_title = 'FORCE MOVE';
    } else {
        // -t: Test run (Dry Run, the default mode)
        $args = '-a -t -v';
        $message_title = 'DRY RUN';
    }

    // --- Construct the full command ---
    // 1. Full script path and arguments: ' /path/to/script.sh -a -f -v'
    // 2. Redirect standard output (1) and standard error (2) to the log file: ' > /path/to/log.log 2>&1'
    // 3. Append '&' to run the process in the background, immediately detaching it from the PHP process.
    $command = "$scriptPath $args > $logFile 2>&1 &";

    // Execute the command using shell_exec or similar function
    // shell_exec executes the command and returns the complete output, but because we background it, 
    // it returns immediately, which is what we want.
    shell_exec($command);

    // Provide user feedback
    $message = "<h2>✅ $message_title Initiated!</h2>
                <p>The consolidation script has been successfully launched in the background.</p>
                <p><strong>Mode:</strong> $message_title (Arguments: <code>$args</code>)</p>
                <p><strong>Log File:</strong> <code>$logFile</code></p>
                <p>The web page will not wait for completion. Please check the log file or your Unraid terminal for progress.</p>";

}

// --- HTML Output ---
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Unraid Consolidation Script Runner</title>
    <!-- Simple, clean CSS for a web UI like Unraid -->
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; background-color: #f0f4f8; margin: 0; padding: 20px; }
        .container { max-width: 600px; margin: 50px auto; background: #fff; padding: 30px; border-radius: 8px; box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1); }
        h1 { color: #333; border-bottom: 2px solid #ddd; padding-bottom: 10px; margin-bottom: 20px; }
        .message, .error { padding: 15px; margin-bottom: 20px; border-radius: 4px; }
        .message { background-color: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
        .error { background-color: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
        label { display: block; margin-bottom: 8px; font-weight: bold; color: #555; }
        select, button { width: 100%; padding: 12px; margin-bottom: 20px; border: 1px solid #ccc; border-radius: 4px; box-sizing: border-box; }
        button { background-color: #2e64c2; color: white; border: none; cursor: pointer; font-size: 16px; transition: background-color 0.3s; }
        button:hover { background-color: #1e4b95; }
        code { background-color: #eee; padding: 2px 4px; border-radius: 3px; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Unraid Consolidation Script Runner</h1>

        <?php if ($error): ?>
            <div class="error"><?= $error ?></div>
        <?php endif; ?>

        <?php if ($message): ?>
            <div class="message"><?= $message ?></div>
        <?php else: ?>
            <p>Select the desired mode for the <code>consld8-1.0.3.sh</code> script. It will run in **Automatic Mode** (`-a`) in the background.</p>
        <?php endif; ?>

        <form method="POST">
            <label for="mode">Select Execution Mode:</label>
            <select name="mode" id="mode" required>
                <option value="dry_run" selected>Dry Run (Test Mode: -a -t -v)</option>
                <option value="force_move">FORCE MOVE (Execution Mode: -a -f -v)</option>
            </select>
            
            <button type="submit">Execute Script in Background</button>
        </form>

        <p><small>Command executed (if successful): <code><?= htmlspecialchars($command ?: "Waiting for input...") ?></code></small></p>

        <?php if (!$error): ?>
            <p style="margin-top: 30px;">
                <span style="color: red; font-weight: bold;">⚠️ ACTION REQUIRED:</span> You must change the <code>$scriptPath</code> variable at the top of this PHP file to the actual location of your script (e.g., <code>'/mnt/user/system/scripts/consld8-1.0.3.sh'</code>).
            </p>
        <?php endif; ?>
    </div>
</body>
</html>
