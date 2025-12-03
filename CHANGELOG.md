## 📜 CHANGELOG.md

All notable changes to the `consld8-auto` script will be documented in this file.

---

## [1.2.2] - 2025-12-03 (Latest)

### 🩹 Fixed
-   Fixed a **color error** in 'Progress Only' (Mode 3) scan output where the ANSI reset code (`\033[0m`) was printing literally due to incorrect `printf` formatting. The progress line is now correctly formatted and displayed.

---

## [1.2.1]

### ✨ Added
-   Implemented the **'Progress Only' (Mode 3)** scan verbosity option for Automatic Mode. This mode displays only a real-time folder count during the scan phase, hiding detailed planning output for cleaner console operation.

---

## [1.1.0]

### 🩹 Fixed & Improved
-   **Dry Run Clarity:** Enhanced the `[DRY RUN]` message within the `execute_move` function to explicitly remind the user that the `-f` flag is required at script start to perform actual file movement.
-   Corrected the `shopt s nullglob` syntax in the script's header to `shopt -s nullglob` for robust operation.

---

## [1.0.3]

### ✨ Added
-   **Interactive Verbosity Prompt (Automatic Mode):** Added a new interactive step in Automatic Mode to prompt the user on how much detail to display during the planning phase (e.g., whether to show skipped, already-consolidated folders).
-   **Safety Margin Configuration:** The script now prompts the user to set the **minimum required free space** (safety margin, default 200 GB) in GB before running the automated scan. This value is used in planning to prevent overfilling target disks.

### 🩹 Fixed & Improved
-   **Share Selection Robustness:** Corrected a syntax error in the `select_base_share` function that caused an unexpected script termination (`unexpected EOF error`) under certain conditions.
-   Minor code refactoring and improved color-coded prompts for better terminal readability.

---

## [1.0.2] - Initial Feature Release

### ✨ Added
-   **Interactive Mode (`-I`):** Implemented a full interactive workflow allowing manual selection of the base share, the specific fragmented folder, and the final destination disk.
-   **Automated Mode (`-a`):** Implemented the core auto-planning logic based on maximizing existing data to minimize I/O:
    -   Calculates the required space for full consolidation.
    -   Filters out disks that would violate the Safety Margin (using a fixed default of 200GB).
    -   Prioritizes the safe disk with the **highest existing file count** for the specific folder.
-   **Pre-Consolidation Check:** Added the `is_consolidated` function to efficiently skip folders that already reside on a single disk.
