# Auto-Consolidate-for-Unraid

This script was inspired and basedon the original unRAID diskmv script, it is HEAVLY modified from the original
diskmv script by trinapicot.
See: https://github.com/trinapicot/unraid-diskmv


### Support the Project

If this script helps you keep your unRAID array tidy, please consider supporting its development!

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=000000)](https://buymeacoffee.com/yourditchdoc)


![image](https://github.com/mejacobarussell/Auto-Consolidate-for-Unraid/blob/main/example.png)


 # 💾 consld8: UnRAID Share Consolidation Script

**A powerful bash script for managing and consolidating fragmented user shares across your unRAID array disks.**

This script automates or facilitates the safe movement of files from fragmented shares (like `TVSHOWS` or `MOVIES`) to a single target disk/cache drive, optimizing disk usage and spin-down efficiency.

---

## 💡 About consld8-auto

In an unRAID environment, user shares often become fragmented, with different parts of the same logical folder spread across multiple physical disks. `consld8-auto` solves this by safely moving all file fragments of a selected sub-folder (e.g., a specific TV show or movie folder) to a single, chosen destination disk using `rsync` with the `--remove-source-files` option for maximum safety and efficiency.

### Key Features

* **Dual Operation Modes:** Run in **Interactive Mode** for manual control, or **Automatic Mode** for fully optimized consolidation planning.
* **Intelligent Planning (Auto Mode):** The script scans fragmented folders and selects the optimal destination disk based on a tiered priority system:
    1.  **Safety Margin:** Must meet a configurable minimum free space (default 200 GB) after the move.
    2.  **Existing Files:** Prioritizes moving to the disk that **already holds the most files** for that specific folder, reducing I/O and increasing the likelihood of successful spin-down.
    3.  **Free Space:** Uses available free space as a tie-breaker.
* **Dry Run/Test Mode:** Default-enabled safety feature to simulate the entire move process without touching files.
* **User Share Selector:** Easily pick the top-level user share (e.g., `TVSHOWS`, `MOVIES`) to process.
* **Safe Execution:** Uses `rsync -avh --remove-source-files` to ensure the move completes before the source files are deleted.

---

## 🛠️ Getting Started

### Prerequisites

This script is written in **Bash** and requires standard Linux tools available on the unRAID OS, including:

* **Bash** (v4.0 or higher is recommended)
* `find`
* `du` and `df`
* `awk`
* `rsync`
* `numfmt` (standard utility for human-readable size formatting)

### Installation

1.  **SSH into your unRAID server.**
2.  **Download the script:**
    ```bash
    wget [https://raw.githubusercontent.com/](https://raw.githubusercontent.com/)[Your-Username]/[Your-Repo]/main/consld8-1.0.3.sh -O /consld8.sh.sh
    ```
3.  **Make the script executable:**
    ```bash
    chmod +x consld8.sh
    ```
4.  *(Optional but Recommended):* Run it using the **User Scripts** plugin on unRAID for easier management.

---

## ⌨️ Usage

The script defaults to **Test Mode (Dry Run)** for safety. Use the `-f` flag to enable actual file movement.

### Command Line Options

| Option | Description | Mode |
| :--- | :--- | :--- |
| `-h` | Display the usage information. | Both |
| `-t` | **Test Mode (Dry Run).** This is the **default**. No files will be moved. | Both |
| `-f` | **Force Execution.** Overrides test mode, and files **will be moved**. | Both |
| `-v` | Increase verbosity (recommended for Auto Mode planning). | Both |
| `-a` | **FULL AUTOMATIC PLANNING MODE.** Scans all folders, generates an optimized plan, and executes (if `-f` is also used). | Auto |
| `-I` | **INTERACTIVE MODE.** Prompts you to select a specific folder and destination disk. | Interactive |

### 1. Interactive Mode Example

Use this mode for granular control over one specific folder.

# Run in Interactive Mode and Dry Run (Default)
./consld8.sh -I

# Run in Interactive Mode and EXECUTE the move
./consld8.sh -I -f

### 2. Automatic Mode Example

Use this mode to let the script manage the entire array cleanup.

# Run in Auto Mode and Test the full plan (Recommended first run)
./consld8.sh -a -v

# Run in Auto Mode and EXECUTE the full plan
./consld8.sh -a -f -v

⚙️ Configuration & Safety
The script is configured using internal variables and runtime prompts.

Safety Margin

By default, the script enforces a 200 GB minimum free space safety margin on the target disk after the consolidation move is planned.

In Automatic Mode, you are prompted to adjust this value before the planning phase begins.

Consolidation Logic

The script uses the following command for moving files. This method copies the contents to the destination and removes the source files only if the copy was successful, ensuring data integrity.

rsync -avh --remove-source-files [source_path]/ [dest_path]/


🤝 Contributing
I welcome suggestions and contributions to improve the efficiency and safety of this script for the unRAID community.

Fork the repository.

Create your feature branch (git checkout -b feature/AmazingFeature).

Commit your changes (git commit -m 'Add some AmazingFeature').

Push to the branch (git push origin feature/AmazingFeature).

📝 License
Distributed under the Unliscense See LICENSE for more information.

📧 Contact
[Jacob Russell] - [Mrjacobarussell@gmail.com]

Project Link: https://github.com/mejacobrussell/Auto-Consolidate-for-Unraid
