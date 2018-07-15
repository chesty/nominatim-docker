#!/bin/bash

rm -f /data/nominatim-initdb.ready

: ${OSM_PBF_URL:=http://download.geofabrik.de/australia-oceania/australia-latest.osm.pbf}
: ${OSM_PBF:=$(basename "$OSM_PBF_URL")}
: ${OSM_PBF_BASENAME:=$(basename "$OSM_PBF" .osm.pbf)}
: ${OSM2PGSQLCACHE:=1000}

if [ -d /postgres/Nominatim/build ]; then
	rm -rf /postgres/Nominatim/build/*
	cp -a /Nominatim/build/* /postgres/Nominatim/build
fi

until echo select 1 | gosu postgres psql template1 &> /dev/null ; do
        echo "Waiting for postgres"
        sleep 5
done

until echo select 1 | gosu postgres psql template1 &> /dev/null ; do
        echo "Waiting for postgres"
        sleep 5
done

gosu postgres createuser www-data || true

if [ ! -f /data/nominatim/country_name.sql ]; then
	cd /Nominatim && \
		mkdir -p /data/nominatim && \
		cp -a data/* /data/nominatim && \
		chown -R postgres: /data/nominatim
fi

cd /Nominatim && \
	rm -rf data && \
	ln -s /data/nominatim data && \
	touch /data/nominatim/nominatim.log && \
	chgrp www-data /data/nominatim/nominatim.log && \
	chmod g+wr /data/nominatim/nominatim.log

if ! `echo select 1 | gosu postgres psql nominatim &> /dev/null` || [ "$REDOWNLOAD" ];then
	gosu postgres curl -L -z /Nominatim/data/country_osm_grid.sql.gz -o /Nominatim/data/country_osm_grid.sql.gz \
		https://www.nominatim.org/data/country_grid.sql.gz
	gosu postgres curl -L -z /data/nominatim/wikipedia_article.sql.bin -o /data/nominatim/wikipedia_article.sql.bin https://www.nominatim.org/data/wikipedia_article.sql.bin
	gosu postgres curl -L -z /data/nominatim/wikipedia_redirect.sql.bin -o /data/nominatim/wikipedia_redirect.sql.bin https://www.nominatim.org/data/wikipedia_redirect.sql.bin
	until ! test -f /data/renderd-initdb.init; do
		echo waiting on renderd-initdb
		sleep 5
	done
	curl -L -z /data/"$OSM_PBF" -o /data/"$OSM_PBF" "$OSM_PBF_URL"
	curl -o /data/"$OSM_PBF".md5 "$OSM_PBF_URL".md5
	cd /data && \
		md5sum -c "$OSM_PBF".md5 || exit 1
	REINITDB=1
fi

if ! `echo select 1 | gosu postgres psql nominatim &> /dev/null` || [ "$REINITDB" ];then
	gosu postgres dropdb nominatim &> /dev/null
	cd /Nominatim/build && \
		gosu postgres ./utils/setup.php --osm-file /data/"$OSM_PBF" --all --osm2pgsql-cache "$OSM2PGSQLCACHE"
fi

touch /data/nominatim-initdb.ready
