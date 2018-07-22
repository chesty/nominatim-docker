<?php

@define('CONST_Log_File', '/data/nominatim/nominatim.log');
@define('CONST_Website_BaseURL', '/');

@define('CONST_Default_Lat', 20.0);
@define('CONST_Default_Lon', 0.0);
@define('CONST_Default_Zoom', 2);
@define('CONST_Map_Tile_URL', 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png');
@define('CONST_Map_Tile_Attribution', ''); // Set if tile source isn't osm.org

// Replication settings
@define('CONST_Replication_Url', 'http://download.geofabrik.de/australia-oceania/australia-updates/');
@define('CONST_Replication_MaxInterval', '604800');
@define('CONST_Replication_Update_Interval', '86400');  // How often upstream publishes diffs
@define('CONST_Replication_Recheck_Interval', '86400'); // How long to sleep if no update found yet
