# The website: landing page, map page, the browser game's files and /proxy.
# The site pages are built in; the map tiles and the browser game are mounted
# (they are made by the map and client services). Build context: the repository root.
FROM nginx:1.27.5-alpine

COPY docker/web/default.conf /etc/nginx/conf.d/default.conf
COPY web/site /srv/site
