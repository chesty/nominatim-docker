#!/bin/bash

rm -f /data/initdb.ready

: ${OSM_PBF_URL:=http://download.geofabrik.de/australia-oceania/australia-latest.osm.pbf}
: ${OSM_PBF:=$(basename "$OSM_PBF_URL")}
: ${OSM_PBF_BASENAME:=$(basename "$OSM_PBF" .osm.pbf)}
: ${OSM2PGSQLCACHE:=1000}

until echo select 1 | gosu postgres psql template1 &> /dev/null ; do
        echo "Waiting for postgres"
        sleep 5
done

# this isn't going to be in effect during init,
# either inject your own postgresql.conf into the container,
# or after init, down the containers and edit postgresql.conf
# in the postgres-data volume with suitable values for your environment
if ! grep -q '#addedConfig' /var/lib/postgresql/data/postgresql.conf ; then
	cat >> /var/lib/postgresql/data/postgresql.conf <<EOL

#addedConfig don't remove this line
max_connections = 50
shared_buffers = 2GB
effective_cache_size = 4GB
maintenance_work_mem = 2GB
checkpoint_completion_target = 0.7
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 200
work_mem = 2GB
min_wal_size = 1GB
max_wal_size = 10GB

wal_buffers = 16MB
max_worker_processes = 8
max_parallel_workers_per_gather = 4
max_parallel_workers = 16

logging_collector = on
log_destination = 'stderr'
log_directory = log
log_rotation_age = 1d
log_min_duration_statement = 50
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on
log_temp_files = 0
log_autovacuum_min_duration = 0
log_error_verbosity = default
lc_messages='C'

checkpoint_warning = 1
checkpoint_timeout = 3600

EOL
fi

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
	curl -L -z /data/"$OSM_PBF" -o /data/"$OSM_PBF" "$OSM_PBF_URL"
	curl -o /data/"$OSM_PBF".md5 "$OSM_PBF_URL".md5
	cd /data && \
		md5sum -c "$OSM_PBF".md5 || exit 1
	gosu postgres curl -L -z /data/nominatim/wikipedia_article.sql.bin -o /data/nominatim/wikipedia_article.sql.bin https://www.nominatim.org/data/wikipedia_article.sql.bin
	gosu postgres curl -L -z /data/nominatim/wikipedia_redirect.sql.bin -o /data/nominatim/wikipedia_redirect.sql.bin https://www.nominatim.org/data/wikipedia_redirect.sql.bin
	REINITDB=1
fi

if ! `echo select 1 | gosu postgres psql nominatim &> /dev/null` || [ "$REINITDB" ];then
	gosu postgres dropdb nominatim &> /dev/null
	cd /Nominatim/build && \
		gosu postgres ./utils/setup.php --osm-file "$OSM_PBF" --all --osm2pgsql-cache "$OSM2PGSQLCACHE"
fi

touch /data/initdb.ready
