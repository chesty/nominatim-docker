# nominatim-docker

- hammermc/nominatim-docker:latest dev
- hammermc/nominatim-docker:release-3.2.0 release-v3.2.0

It works as a standalone nominatim docker container and it should 
init to a working install, but it requires some tuning and
configuration changes to suit your environment.

See https://github.com/chesty/maps-docker-compose for a full OpenStreetMaps environment
using this image plus others.
 
To keep nominatim updated, start the nominatim-updatedb container every 24 hours.

