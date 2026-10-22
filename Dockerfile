FROM php:8.4-fpm-alpine
LABEL maintainer="clamy54"
ENV container=docker

# Archive officielle QoQ-CoT. Si files/qoq-src/QoQ-CoT_v5.0_Mac_Bec.tgz existe, elle est utilisée à la place du téléchargement.
ARG QOQ_URL=https://sourcesup.renater.fr/frs/download.php/file/6336/QoQ-CoT_v5.0_Mac_Bec.tgz
ARG QOQ_SHA256=

WORKDIR /app

RUN apk add --no-cache rsync mariadb mariadb-client mariadb-server-utils pwgen tini tzdata \
        perl perl-io-socket-ssl perl-dbi perl-yaml-tiny perl-dbd-mysql perl-io-socket-inet6 perl-data-dump perl-mime-base64 perl-encode \
        apache2 apache2-utils apache2-ssl apache2-ldap apache2-proxy

RUN apk add --no-cache --virtual .build-deps $PHPIZE_DEPS \
        libpng-dev libjpeg-turbo-dev libwebp-dev freetype-dev libxpm-dev bzip2-dev libxslt-dev icu-dev libzip-dev openldap-dev \
 && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp --with-xpm \
 && docker-php-ext-install -j"$(nproc)" bcmath bz2 calendar exif gd intl ldap pcntl pdo_mysql xsl zip \
 && runDeps="$(scanelf --needed --nobanner --format '%n#p' --recursive /usr/local/lib/php/extensions \
        | tr ',' '\n' | sort -u \
        | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }')" \
 && apk add --no-cache --virtual .php-rundeps $runDeps \
 && apk del .build-deps

RUN cp /usr/share/zoneinfo/Europe/Paris /etc/localtime && echo "Europe/Paris" > /etc/timezone \
 && cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"
COPY files/php-qoq.ini $PHP_INI_DIR/conf.d/zz-qoq.ini

RUN sed -i "s/^user = www-data/user = apache/; s/^group = www-data/group = apache/" /usr/local/etc/php-fpm.d/www.conf \
 && sed -i "s/^listen = 9000/listen = 127.0.0.1:9000/" /usr/local/etc/php-fpm.d/*.conf

RUN sed -i "s/^#LoadModule mpm_event_module modules/LoadModule mpm_event_module modules/; s/^LoadModule mpm_prefork_module modules/#LoadModule mpm_prefork_module modules/" /etc/apache2/httpd.conf \
 && sed -i "s/DirectoryIndex index.html/DirectoryIndex index.html index.php/" /etc/apache2/httpd.conf \
 && sed -i "s/^#ServerName .*$/ServerName localhost:8080/" /etc/apache2/httpd.conf \
 && sed -i "s/^Listen 80$/Listen 8080/" /etc/apache2/httpd.conf \
 && sed -i '/^<Directory "\/var\/www\/localhost\/htdocs">/,/^<\/Directory>/ s/AllowOverride None/AllowOverride AuthConfig/' /etc/apache2/httpd.conf \
 && grep -q "AllowOverride AuthConfig" /etc/apache2/httpd.conf

RUN adduser -S -u 666 -s /bin/sh -h /home/coq -G nobody coq

COPY files/qoq-src/ /tmp/qoq-src/
RUN set -e; \
    if [ -f /tmp/qoq-src/QoQ-CoT_v5.0_Mac_Bec.tgz ]; then mv /tmp/qoq-src/QoQ-CoT_v5.0_Mac_Bec.tgz /tmp/qoq.tgz; \
    else wget -q -O /tmp/qoq.tgz "$QOQ_URL"; fi; \
    if [ -n "$QOQ_SHA256" ]; then echo "$QOQ_SHA256  /tmp/qoq.tgz" | sha256sum -c -; fi; \
    tar zxf /tmp/qoq.tgz -C /app; \
    rm -rf /tmp/qoq.tgz /tmp/qoq-src

COPY files/patches/ /tmp/patches/
RUN set -e; apk add --no-cache --virtual .patch-deps patch; cd /app/qoq-cot; \
    for p in /tmp/patches/*.patch; do echo "Applying $p"; patch -p1 --no-backup-if-mismatch < "$p"; done; \
    apk del .patch-deps; rm -rf /tmp/patches; \
    find src -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-16 > /app/qoq-cot/BUILD_ID

RUN mkdir /usr/local/coq && cp /app/qoq-cot/ressources/poussin-coq/coq/SOURCES/coq.pl /usr/local/coq/coq.pl && chmod +rx /usr/local/coq/coq.pl \
 && sed -i "s/'coq.yml'/'\/var\/www\/localhost\/htdocs\/config-coq\/coq.yml'/g" /usr/local/coq/coq.pl

COPY files/php-fpm.conf /etc/apache2/conf.d/php-fpm.conf
COPY files/apache-qoq.conf /etc/apache2/conf.d/qoq.conf
COPY --chmod=755 files/run.sh /app/run.sh

VOLUME ["/var/lib/mysql"]
VOLUME ["/var/www/localhost/htdocs"]

EXPOSE 8080
EXPOSE 9900

STOPSIGNAL SIGTERM
ENTRYPOINT ["/sbin/tini", "--", "/app/run.sh"]
