# The website: landing page, map page, the browser game's files and /proxy.
# The site pages are built in; the map tiles and the browser game are mounted
# (they are made by the map and client services). Build context: the repository root.
FROM nginx:1.27.5-alpine

COPY docker/web/default.conf /etc/nginx/conf.d/default.conf
COPY web/site /srv/site
# The stylesheet's and script's version, for the ?v= in every page
RUN v=$(cat /srv/site/css/site.css /srv/site/js/site.js | md5sum | cut -c1-10) \
	&& sed -i "s/__ASSETS__/$v/g" /etc/nginx/conf.d/default.conf
COPY docker/web/snippets /etc/nginx/snippets
