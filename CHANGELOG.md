## 📜 CHANGELOG.md

### **Version 1.0.3 (Latest)**

This version focuses on improving the user experience for both automatic planning and manual execution, adding crucial feedback and transparency.

#### ✨ New Features

* **Interactive Verbosity Prompt (Automatic Mode):** Added a new interactive step in **Automatic Mode** to prompt the user whether to display details for folders that were skipped because they were already fully consolidated (exist on only one disk).
* **Safety Margin Configuration:** The script now prompts the user to set the minimum required free space (safety margin, default 200 GB) in GB before running the automated scan. This value is used in planning to prevent overfilling target disks.

#### 🩹 Fixes & Improvements

* **Dry Run Clarity:** Enhanced the `[DRY RUN]` message in `execute_move` to explicitly remind the user that the **`-f` flag** is required at script start to perform actual file movement.
    * *Example: `[DRY RUN]: ... Use the -f flag at script start to perform actual moves.`*
* **Share Selection Robustness:** Corrected a syntax error in the `select_base_share` function that caused an unexpected script termination (`unexpected EOF` error) under certain conditions.
* **Code Cleanup:** Minor refactoring and improved color-coded prompts for better terminal readability.

***

### **Version 1.0.2 (Initial Feature Release)**

#### ✨ New Features

* **Interactive Mode (`-I`):** Implemented a full interactive workflow allowing manual selection of the base share, the specific fragmented folder, and the final destination disk.
* **Automated Mode (`-a`):** Implemented the core auto-planning logic based on maximizing existing data to minimize I/O:
    1.  Calculates required space for full consolidation.
    2.  Filters out disks that would violate the **Safety Margin**.
    3.  Prioritizes the safe disk with the **highest existing file count** for the specific folder.
* **Pre-Consolidation Check:** Added the `is_consolidated
