#!/bin/bash

. /etc/apache2/envvars

cd ${APACHE_LOG_DIR} && \
	ln -sf /dev/stdout access.log && \
	ln -sf /dev/stdout error.log

touch /data/nominatim/nominatim.log && \
	chgrp www-data /data/nominatim/nominatim.log && \
	chmod g+wr /data/nominatim/nominatim.log

cd /
exec /usr/sbin/apache2 -DFOREGROUND
