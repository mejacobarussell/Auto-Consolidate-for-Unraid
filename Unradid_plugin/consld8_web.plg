#!/bin/bash
# Unraid Plugin Web Interface for consld8-1.0.3.sh

# --- Configuration ---
# Path to your core script (as defined in the .plg file)
CORE_SCRIPT="/usr/local/emhttp/plugins/disk_consolidator/consld8-1.0.3.sh"
# --- End Configuration ---

# Required for Unraid WebUI interaction
echo "Content-type: text/html"
echo ""

# --- Helper Functions for HTML ---

# Function to safely encode text for HTML display
# This is crucial for displaying terminal output in an HTML pre block
html_encode() {
  sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&#39;/g'
}

# Function to start the standard Unraid Panel content area
start_content() {
  echo "<div class='panel'>
    <div class='header'>
      <span class='title'>Disk Consolidation Utility</span>
    </div>
    <div class='content'>"
}

# Function to end the standard Unraid Panel content area
end_content() {
  echo "</div></div>"
}

# Function to handle execution of the core script
run_consolidation() {
  local mode="$1" # Either -a (Auto) or -I (Interactive)
  local force="$2" # Flag for -f (Force/Execute)
  local flags="$mode $force"

  start_content
  echo "<h2>Consolidation Running...</h2>"
  echo "<p>Mode: <b>$([ "$mode" == "-a" ] && echo "AUTOMATIC" || echo "INTERACTIVE")</b>, Execution: <b>$([ "$force" == "-f" ] && echo "LIVE MOVE" || echo "DRY RUN")</b></p>"
  echo "<pre style='background:#111; color:#eee; padding:15px; border-radius:5px; max-height: 400px; overflow: auto;'>"
  
  # Execute the core script with the selected flags
  # We use the 'stdbuf' command to ensure output is not buffered and appears immediately.
  stdbuf -oL -eL "$CORE_SCRIPT" $flags | html_encode

  if [ "${PIPESTATUS[0]}" -eq 0 ]; then
    echo "<b>[PROCESS ENDED]</b>: Script completed successfully."
  else
    echo "<b>[PROCESS FAILED]</b>: An error occurred during execution. Check logs above." >&2
  fi
  
  echo "</pre>"
  
  # Provide a button to return to the main selection
  echo "<form method='get' action='/plugins/disk_consolidator/consld8_web.sh'>
    <button type='submit' class='btn btn-primary'>&laquo; Back to Settings</button>
  </form>"

  end_content
}


# --- Main HTML Generation ---
# Output standard HTML head and Unraid styling
cat << EOF
<!DOCTYPE html>
<html>
<head>
  <title>Disk Consolidator</title>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
  <link rel="stylesheet" type="text/css" href="/css/default.css">
  <style>
    .consolidator-card {
        max-width: 600px;
        margin: 20px auto;
        padding: 20px;
        background-color: #f7f7f7;
        border-radius: 8px;
        box-shadow: 0 4px 8px rgba(0,0,0,0.1);
    }
  </style>
</head>
<body>
EOF

# Check for POST data, which indicates a form submission to run the script
if [ "$REQUEST_METHOD" == "POST" ]; then
    # Parse POST data (Unraid commonly uses a simple POST structure)
    
    # We will grab the POST data from stdin
    read -n $CONTENT_LENGTH POST_DATA
    
    # --- Simplified POST Data Parsing ---
    # Extract the mode (auto or interactive)
    if [[ "$POST_DATA" =~ mode=auto ]]; then
        SCRIPT_MODE="-a"
    elif [[ "$POST_DATA" =~ mode=interactive ]]; then
        SCRIPT_MODE="-I"
    else
        SCRIPT_MODE="-I" # Default to Interactive if not specified
    fi
    
    # Extract the action (test or force)
    if [[ "$POST_DATA" =~ action=force ]]; then
        ACTION_FLAG="-f" # Run live
    else
        ACTION_FLAG="-t" # Run test (Dry Run)
    fi
    
    run_consolidation "$SCRIPT_MODE" "$ACTION_FLAG"
    
else # No POST data, show the configuration form
    
    start_content
    
    echo "<h2>Consolidation Mode Selection</h2>"
    echo "<p>The core script has two main modes: Automatic (recommended for planning) and Interactive (for specific folder moves).</p>"

    # --- Mode Selection Form ---
    echo "<form method='post' action='/plugins/disk_consolidator/consld8_web.sh'>"
    echo "<table class='table' style='max-width:100%;'>"
    
    # Row 1: Select Mode
    echo "<tr><td colspan='2' class='td-title'>1. Select Operation Mode</td></tr>"
    echo "<tr>"
    echo "<td style='width:50%;'><input type='radio' name='mode' value='interactive' id='mode-interactive' checked> <label for='mode-interactive'><b>Interactive Mode</b></label></td>"
    echo "<td><p class='note'>Manually select a fragmented folder and its consolidation target disk.</p></td>"
    echo "</tr>"
    echo "<tr>"
    echo "<td><input type='radio' name='mode' value='auto' id='mode-auto'> <label for='mode-auto'><b>Automatic Mode</b></label></td>"
    echo "<td><p class='note'>The script will scan all shares, generate an optimized move plan, and prompt for execution.</p></td>"
    echo "</tr>"
    
    # Row 2: Select Execution Type (Dry Run vs. Live)
    echo "<tr><td colspan='2' class='td-title' style='padding-top:20px;'>2. Select Action Type</td></tr>"
    echo "<tr>"
    echo "<td><input type='radio' name='action' value='test' id='action-test' checked> <label for='action-test'><b style='color:#F39C12;'>Test Run (Dry Run)</b></label></td>"
    echo "<td><p class='note'>Recommended first step. The script will output the plan and moves, but <b>NO FILES</b> will be modified.</p></td>"
    echo "</tr>"
    echo "<tr>"
    echo "<td><input type='radio' name='action' value='force' id='action-force'> <label for='action-force'><b style='color:#C0392B;'>Execute Live Move</b></label></td>"
    echo "<td><p class='note'>This will run the move commands using <b>rsync</b>. Ensure you have tested first!</p></td>"
    echo "</tr>"

    # Row 3: Submit Button
    echo "<tr><td colspan='2' style='text-align:center; padding-top:30px;'>
        <button type='submit' class='btn btn-lg btn-success'>
            Start Consolidation Process
        </button>
    </td></tr>"
    
    echo "</table>"
    echo "</form>"

    echo "<p class='note' style='padding-top:20px;'><b>Note on Interactive Mode:</b> Since the WebUI lacks a persistent terminal, Interactive Mode may not work perfectly with your original script's sequential 'read' prompts. For reliable web execution, the Automatic Mode is preferred for Unraid plugins.</p>"

    end_content
fi

# End HTML body and close document
echo "</body>"
echo "</html>"
