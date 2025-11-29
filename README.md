# Auto-Consolidate-for-Unraid

This script was inspired and basedon the original unRAID diskmv script, it is HEAVLY modified from the original
diskmv script by trinapicot.
See: https://github.com/trinapicot/unraid-diskmv


### Support the Project

If this script helps you keep your unRAID array tidy, please consider supporting its development!

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=000000)](https://buymeacoffee.com/yourditchdoc)


![image](https://github.com/mejacobarussell/Auto-Consolidate-for-Unraid/blob/main/example.png)



## 📦 `consld8.sh`: UnRAID Share Consolidation Script

A powerful Bash script for unRAID systems designed to automatically or interactively consolidate fragmented user shares (sub-folders)
onto a single physical disk, ensuring optimal disk utilization and organization.

### 📝 Table of Contents

* [Features](#-features)
* [Prerequisites](#-prerequisites)
* [Installation](#-installation)
* [Usage](#-usage)
    * [Mode Selection](#mode-selection)
    * [Options](#options)
* [Automatic Mode Logic](#automatic-mode-logic)
* [Configuration](#configuration)

---

## ✨ Features

* **Two Modes:** Fully **Automatic** planning and execution, or step-by-step 
**Interactive** control. * **Safety Margin:** Uses a configurable minimum free space buffer
(**200 GB by default**) to prevent overfilling target disks.* **Dry Run Support:** The default
mode is a **test run** (`-t`), allowing you to review the plan before committing any changes. *
**Smart Planning (Auto Mode):** Prioritizes consolidation to the disk that **already holds the largest
fragment** (highest file count) of the folder to minimize total data movement. * **Safe Execution:**
Utilizes `rsync -avh --remove-source-files` to safely copy data and only delete the source files upon
successful completion.

---

## 🛠️ Prerequisites

This script is designed to run directly on an **unRAID** server, as it relies on the specific disk
mounting structure (`/mnt/diskX`, `/mnt/cache`) and standard Linux/unRAID utilities 
(`bash`, `du`, `df`, `find`, `rsync`, `numfmt`).

---

## 🚀 Installation

1.  **Save the Script:** Save the script content to a file named `consld8.sh` on your unRAID server
(e.g., in `/boot/config/scripts/`).

2.  **Make Executable:** Set the execution permission:

```bash
chmod +x /consld8.sh
## 📦 `consld8.sh`: UnRAID Share Consolidation Script

A powerful Bash script for unRAID systems designed to automatically or interactively consolidate fragmented
user shares (sub-folders) onto a single physical disk, ensuring optimal disk utilization and organization.

### 📝 Table of Contents

* [Features](#-features)
* [Prerequisites](#-prerequisites)
* [Installation](#-installation)
* [Usage](#-usage)
    * [Mode Selection](#mode-selection)
    * [Options](#options)
* [Automatic Mode Logic](#automatic-mode-logic)
* [Configuration](#configuration)

---

## ✨ Features

* **Two Modes:** Fully **Automatic** planning and execution, or step-by-step **Interactive** control.
* **Safety Margin:** Uses a configurable minimum free space buffer (**200 GB by default**) to prevent overfilling
target disks. * **Dry Run Support:** The default mode is a **test run** (`-t`), allowing you to review the plan before 
committing any changes. * **Smart Planning (Auto Mode):** Prioritizes consolidation to the disk that **already holds
the largest fragment** (highest file count) of the folder to minimize total data movement.* **Safe Execution:**
Utilizes `rsync -avh --remove-source-files` to safely copy data and only delete the source files upon successful
completion.

---

## 🛠️ Prerequisites

This script is designed to run directly on an **unRAID** server, as it relies on the specific disk mounting structure
(`/mnt/diskX`, `/mnt/cache`) and standard Linux/unRAID utilities (`bash`, `du`, `df`, `find`, `rsync`, `numfmt`).

````

3.  **Run:** Execute the script from the command line:

<!-- end list -->


-----

## 💡 Usage

The script requires you to explicitly select either **Automatic** or **Interactive** mode using 
the `-a` or `-I` flag. If no mode is supplied,  it will prompt you for selection.

### Mode Selection

| Flag | Mode | Description |
| :--- | :--- | :--- |
| `-a` | **Automatic** | Scans all sub-folders within the selected share, calculates the optimal target disk
for each, and generates a plan. |
| `-I` | **Interactive** | Allows you to manually select the base share, the specific fragmented sub-folder, 
and the exact destination disk. |

### Options

| Flag | Name | Default | Applies to | Description |
| :--- | :--- | :--- | :--- | :--- |
| `-h` | Help | N/A | Both | Display the usage information and exit. |
| `-t` | Test Run | `true` | Both | **(Default)** Only generates the plan/reports the move. No files are moved. |
| `-f` | Force Execute | `false` | Both | **Overrides** the test run. Files **WILL** be moved and deleted from
original locations. |
| `-v` | Verbose | `1` | Both | Increases detail, useful for troubleshooting the planning logic in Auto Mode. |

#### Example (Automatic Dry Run)

Run the automatic planner and review the proposed moves without risk:

```bash
./consld8.sh -a
```

#### Example (Interactive Force Run)

Select a specific share and folder, then execute the move immediately:

```bash
./consld8.sh -I -f
```

-----

## 🧠 Automatic Mode Logic

The automatic planner uses a prioritized system to choose the best destination disk for consolidating a
fragmented folder:

1.  **Safety Check (Must Pass):** The proposed move must ensure the target disk's final free space is greater
than the configured **Safety Margin**
2.  (`MIN_FREE_SPACE_KB`). Disks failing this are ignored.
    **Primary Metric (Maximize existing data):** Among all safe disks, the script selects the disk that
    **already contains the highest number of
   files** belonging to the folder being consolidated. This minimizes the I/O operations required.
5.  **Secondary Metric (Tie-breaker):** If multiple disks tie for the highest file count, the script chooses
the one with the **most free space**.

-----

## ⚙️ Configuration

You can easily adjust the script's default behavior by editing the constants at the top of the `consld8.sh` file.

| Constant | Default Value | Description |
| :--- | :--- | :--- |
| `BASE_SHARE` | `"/mnt/user/TVSHOWS"` | The default starting user share path if one is not manually selected. |
| `MIN_FREE_SPACE_KB` | `209715200` | The required minimum free space after consolidation, specified 
in **1K blocks** (200 GB). This value can also be set interactively during the automatic run. |

```
```
### Support the Project

If this script helps you keep your unRAID array tidy, please consider supporting its development!

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=000000)](https://buymeacoffee.com/yourditchdoc)
