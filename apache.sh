#!/bin/bash

sleep 10 # give it sometime for initdb.sh to start and remove an old /data/initdb.ready if it exists.
until test -f /data/nominatim-initdb.ready; do
	echo waiting on nomintim-initdb
	sleep 10
done

. /etc/apache2/envvars

if [ ! -d /data/nominatim/apache2 ]; then
	mkdir -p /data/nominatim
	cp -a /etc/apache2 /data/nominatim/
	cd /data/nominatim/apache2/sites-available && \
		mv 000-default.conf 000-default.conf.orig &&
		cat > 000-default.conf <<EOL
<VirtualHost *:80>
    DocumentRoot /Nominatim/build/website
    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
    <Directory /Nominatim/build/website>
        Options FollowSymLinks MultiViews
        AddType text/html .php
        DirectoryIndex search.php
        Require all granted
    </Directory>
</VirtualHost>
EOL

fi

if [ ! -d /data/nominatim/settings ]; then
	mkdir -p /data/nominatim/
	cd /Nominatim/build && \
		mv settings /data/nominatim/
fi

cd /Nominatim/build && \
	rm -rf settings && \
	ln -sf /data/nominatim/settings

cd /etc && \
	rm -rf apache2 && \
	ln -sf /data/nominatim/apache2

cd ${APACHE_LOG_DIR} && \
	ln -sf /dev/stdout access.log && \
	ln -sf /dev/stdout error.log

touch /data/nominatim/nominatim.log && \
	chgrp www-data /data/nominatim/nominatim.log && \
	chmod g+wr /data/nominatim/nominatim.log

exec /usr/sbin/apache2 -DFOREGROUND
