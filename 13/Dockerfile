FROM hammermc/postgis-docker:13 as buildstage

ENV BUMP 20200927

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends install \
        apache2 \
        build-essential \
        cmake \
        curl \
        g++ \
        git \
        libapache2-mod-php \
        libboost-all-dev \
        libboost-dev \
        libboost-filesystem-dev \
        libboost-system-dev \
        libbz2-dev \
        libexpat1-dev \
        libgeos++-dev \
        libgeos-dev \
        libpq-dev \
        libproj-dev \
        libxml2-dev \
        php \
        php-cgi \
        php-cli \
        php-dev \
        php-intl \
        php-pgsql \
        php-symfony \
        postgresql-13-postgis-3 \
        postgresql-13-postgis-3-scripts \
        postgresql-contrib-13 \
        postgresql-server-dev-13 \
        python3-dev \
        python3-pip \
        wget \
        zlib1g-dev

RUN set -ex; \
	\
    apt-get update; \
	DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
	    build-essential \
	    libpq5 \
	    libpq-dev \
	    python3-dev; \
	python3 -m pip install wheel setuptools; \
	python3 -m pip install osmium psycopg2 pytidylib

RUN git clone --depth 1 --branch master --single-branch https://github.com/openstreetmap/Nominatim.git && \
    cd Nominatim && \
    git submodule update --recursive --init && \
    wget -O /Nominatim/data/country_osm_grid.sql.gz https://www.nominatim.org/data/country_grid.sql.gz

RUN cd Nominatim && \
    mkdir -p build && \
    cd build && \
    cmake .. && \
    make && \
    ./utils/setup.php --setup-website && \
    make install

FROM hammermc/postgis-docker:13 as runstage
COPY --from=buildstage /usr/local/ /usr/local/
COPY --from=buildstage /Nominatim /Nominatim

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends install \
        apache2 \
        ca-certificates \
        curl \
        gosu \
        libapache2-mod-php \
        libboost-filesystem1.71.0 \
        libboost-python1.71.0 \
        libboost-system1.71.0 \
        libproj15 \
        php-cgi \
        php-cli \
        php-db \
        php-intl \
        php-pgsql \
        php-symfony \
        postgresql-13-postgis-3 \
        postgresql-13-postgis-3-scripts \
        postgresql-client-13 \
        postgresql-contrib-13 \
        python3 \
        python3-pip && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /src

RUN set -ex; \
	\
    apt-get update; \
	DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
	    build-essential \
	    libpq5 \
	    libpq-dev \
	    python3-dev; \
	python3 -m pip install wheel setuptools; \
	python3 -m pip install osmium psycopg2 pytidylib; \
	apt-get purge -y \
	    build-essential \
	    libpq-dev \
	    python3-dev; \
    apt-get autoremove --purge -y; \
    rm -rf /var/lib/apt/lists/*

RUN useradd -ms /bin/bash osm
RUN chown postgres /Nominatim/build
RUN mkfifo -m 600 /Nominatim/build/logpipe && \
    chown www-data /Nominatim/build/logpipe

COPY nominatim-docker-entrypoint.sh /usr/local/bin/
COPY osm-config.sh /usr/local/etc/

EXPOSE 5432
EXPOSE 80

WORKDIR /Nominatim/build

ENTRYPOINT ["nominatim-docker-entrypoint.sh"]
