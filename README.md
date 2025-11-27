# Auto-Consolidate-for-Unraid

This script was inspired and a HEAVY modifacation fromthe UNRAID diskmv script by: trinapicot
https://github.com/trinapicot/unraid-diskmv

This Bash script is designed to automatically plan and execute consolidation of data within a specific unRAID user share (/mnt/user/TVSHOWS by default) onto the array's physical disks. Its primary goal is to ensure folders are contained on a single, optimal disk while strictly maintaining a disk space safety margin.

⚙️ Core Operational Flow
The script operates in three main phases when run in Automatic Mode (-a): Scanning, Planning, and Execution.

1. Scanning and Initialization

The script first establishes the current state of your unRAID array and share usage:

Disk State: It iterates through all physical disks (disk1, disk2, etc., and cache). It uses a robust method (df -P) to calculate the exact Available Free Space on each disk and the current usage of the entire $BASE_SHARE across all disks. This data is stored in associative arrays for fast lookups.

2. Planning Phase (The Optimization Logic)

The script iterates through every subfolder (e.g., /mnt/user/TVSHOWS/ShowName) and determines the single best destination disk based on a three-tiered set of rules.


***********(In this version the Share folder is hard coded please change as you need too)

A. Pre-Consolidation Check (Efficiency Guard)

The script first checks how many physical disks currently contain files for the specific folder being analyzed.

If the folder's files exist on only 0 or 1 disk, the folder is immediately skipped from the plan. This prevents the script from wasting time calculating moves for data that is already consolidated.

B. Safety Check (The Hard Requirement)

For any remaining fragmented folder, the script calculates the total required space for all components of the entire share to land on the candidate disk.

The candidate disk is only deemed eligible if its Final Free Space (Current Free Space minus the Required Consolidation Size) is greater than the 200 GB Safety Margin ($MIN_FREE_SPACE_KB). Disks failing this test are immediately eliminated from consideration.

C. Prioritization (Optimization)

If multiple disks pass the Safety Check, the script follows this strict hierarchy to select the single best disk:

Primary Rule (Max Files): It chooses the disk that currently holds the highest number of files for the folder component being analyzed. This minimizes the amount of data that needs to be copied into the destination disk, reducing I/O and movement time.

Secondary Rule (Max Free Space): If two or more disks are tied for the highest file count (e.g., both are empty), the script selects the disk with the most total available free space.

The chosen folder and destination disk are then recorded in the final $PLAN_ARRAY.

3. Execution Phase (Moving Data)

If the script is run with the Force flag (-f), it executes the plan recorded in the $PLAN_ARRAY.

Iterative Move: For each folder, the script iterates through all physical source disks (including cache).

Safe Transfer: It uses rsync -avh --remove-source-files to copy files from the source disk into the single, designated destination disk. The --remove-source-files flag ensures files are only deleted from the source after a successful transfer.

Cleanup: After the transfer completes successfully, the script safely removes any empty directories left behind on the source disks using find ... -type d -empty -delete.

