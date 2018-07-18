#!/bin/bash

: ${OSM_PBF_URL:=http://download.geofabrik.de/australia-oceania/australia-latest.osm.pbf}
: ${OSM_PBF:=$(basename "$OSM_PBF_URL")}
: ${OSM_PBF_BASENAME:=$(basename "$OSM_PBF" .osm.pbf)}
: ${OSM2PGSQLCACHE:=1000}

if [ "$1" == "apache2" ]; then
	shift

	. /etc/apache2/envvars

	cd ${APACHE_LOG_DIR} && \
		ln -sf /dev/stdout access.log && \
		ln -sf /dev/stdout error.log

	if [ ! -d /data/nominatim ]; then
		mkdir /data/nominatim
		chown postgres: /data/nominatim
	fi

	touch /data/nominatim/nominatim.log && \
		chgrp www-data /data/nominatim/nominatim.log && \
		chmod g+wr /data/nominatim/nominatim.log

	cd /


	mkdir -p "$APACHE_RUN_DIR" && \
	    rm -f $APACHE_PID_FILE && \
	    rm -f "$APACHE_LOG_DIR"/error.log "$APACHE_LOG_DIR"/access.log && \
	    ln -sf /dev/stdout "$APACHE_LOG_DIR"/error.log && \
	    ln -sf /dev/stdout "$APACHE_LOG_DIR"/access.log && \
	    exec /usr/sbin/apache2 -DFOREGROUND "$@"

fi

if [ "$1" == "initdb" ]; then
	shift

	# this is so nominatim.so is available in the postgres container
	# it's not used for standalone
	if [ -d /postgres/Nominatim/build ]; then
		mkdir -p /postgres/Nominatim/build/module
		cp /Nominatim/build/module/nominatim.so /postgres/Nominatim/build/module
	fi

	until echo select 1 | gosu postgres psql template1 &> /dev/null ; do
	        echo "Waiting for postgres"
	        sleep 5
	done

	gosu postgres createuser www-data &> /dev/null || true

	if [ ! -f /data/nominatim/country_name.sql ]; then
		cd /Nominatim && \
			mkdir -p /data/nominatim && \
			cp -a data/* /data/nominatim && \
			chown -R postgres: /data/nominatim
			touch /data/nominatim/nominatim.log && \
			chgrp www-data /data/nominatim/nominatim.log && \
			chmod g+wr /data/nominatim/nominatim.log
	fi

	cd /Nominatim && \
		rm -rf data && \
		ln -s /data/nominatim data && \

	if ! `echo select 1 | gosu postgres psql nominatim &> /dev/null` || [ "$REDOWNLOAD" ];then
		gosu postgres curl -L -z /Nominatim/data/country_osm_grid.sql.gz -o /Nominatim/data/country_osm_grid.sql.gz \
			https://www.nominatim.org/data/country_grid.sql.gz
		gosu postgres curl -L -z /data/nominatim/wikipedia_article.sql.bin -o /data/nominatim/wikipedia_article.sql.bin https://www.nominatim.org/data/wikipedia_article.sql.bin
		gosu postgres curl -L -z /data/nominatim/wikipedia_redirect.sql.bin -o /data/nominatim/wikipedia_redirect.sql.bin https://www.nominatim.org/data/wikipedia_redirect.sql.bin

		# this is a noop for a standalone nominatim container, it's used in
		# https://github.com/chesty/maps-docker-compose
		until ! test -f /data/renderd-initdb.init; do
			echo waiting on renderd-initdb
			sleep 5
		done

		if [ "$REDOWNLOAD" -o ! -f /data/"$OSM_PBF" -a "$OSM_PBF_URL" ]; then
			curl -L -z /data/"$OSM_PBF" -o /data/"$OSM_PBF" "$OSM_PBF_URL"
			curl -o /data/"$OSM_PBF".md5 "$OSM_PBF_URL".md5
			cd /data && \
				md5sum -c "$OSM_PBF".md5 || rm -f /data/"$OSM_PBF" && exit 1
		fi
		REINITDB=1
	fi

	if ! `echo select 1 | gosu postgres psql nominatim &> /dev/null` || [ "$REINITDB" ];then
		gosu postgres dropdb nominatim &> /dev/null
		cd /Nominatim/build && \
			gosu postgres ./utils/setup.php --osm-file /data/"$OSM_PBF" --all --osm2pgsql-cache "$OSM2PGSQLCACHE" && \
			gosu postgres ./utils/update.php --recompute-word-counts && \
			gosu postgres ./utils/specialphrases.php --wiki-import > /data/nominatim/specialphrases.sql && \
			gosu postgres psql -d nominatim -f /data/nominatim/specialphrases.sql

	fi
	exit 0
fi

exec docker-entrypoint.sh "$@"
