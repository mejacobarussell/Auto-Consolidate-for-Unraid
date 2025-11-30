<?xml version="1.0" encoding="utf-8"?>

<plugin>
<!-- 1. UPDATED: ID should be unique, using the concept name -->
<id>DiskConsolidator</id>
<name>Disk Consolidator (consld8)</name>
<version>1.0.3</version>
<category>Tools</category>
<description>Consolidates fragmented user share folders onto a single disk using rsync, based on the consld8 script.</description>
<author>Your Name</author>
<website>https://www.google.com/search?q=https://yourwebsite.com</website>
<minSystem>6.10.0</minSystem>

<!-- 2. NO CHANGE: The <copy> block still uses relative paths (src) for the scripts -->

<copy>
<file src="consld8_web.sh" dest="/usr/local/emhttp/plugins/disk_consolidator/consld8_web.sh" mode="0777"/>
<file src="consld8-1.0.3.sh" dest="/usr/local/emhttp/plugins/disk_consolidator/consld8-1.0.3.sh" mode="0777"/>
</copy>

<!-- 3. NO CHANGE: The URL path remains correct as it points to the execution script in the plugin folder -->

<page>
<id>consolidatorsettings</id>
<label>Disk Consolidator</label>
<url>/plugins/disk_consolidator/consld8_web.sh</url>
</page>

<!-- 4. NO CHANGE: Removal remains the same -->

<remove>
<file dest="/usr/local/emhttp/plugins/disk_consolidator"/>
</remove>

</plugin>
