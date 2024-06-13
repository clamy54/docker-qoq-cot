FROM php:7.2-fpm-alpine
MAINTAINER clamy54
ENV container docker

RUN mkdir /app
WORKDIR /app
RUN apk add --no-cache wget rsync mariadb mariadb-client mariadb-server-utils pwgen perl perl-io-socket-ssl  perl-dbi perl-yaml-tiny perl-io-socket-ssl perl-dbd-mysql perl-io-socket-inet6 perl-data-dump perl-mime-base64 perl-encode && rm -f /var/cache/apk/*
RUN apk add --no-cache apache2 apache2-utils apache2-ssl apache2-ldap apache2-proxy tzdata  && rm -f /var/cache/apk/*
RUN docker-php-ext-install pdo_mysql
RUN apk add --no-cache libpng libpng-dev libjpeg-turbo-dev libwebp-dev zlib-dev libxpm-dev libbz2 libmcrypt libxslt icu imagemagick imagemagick-libs imagemagick-dev  bzip2-dev libmcrypt-dev libxml2-dev libedit-dev libxslt-dev icu-dev sqlite-dev freetype-dev 
RUN docker-php-ext-configure gd  --with-freetype-dir=/usr/include/  --with-png-dir=/usr/include/ --with-jpeg-dir=/usr/include 
RUN docker-php-ext-install bz2 bcmath dom exif fileinfo hash iconv intl opcache pcntl pdo pdo_mysql pdo_sqlite readline session simplexml xml xsl zip gd calendar
RUN apk del freetype-dev libpng-dev libjpeg-turbo-dev freetype-dev libpng-dev libjpeg-turbo-dev bzip2-dev libmcrypt-dev libxml2-dev libedit-dev libxslt-dev icu-dev sqlite-dev
RUN cp /usr/share/zoneinfo/Europe/Paris /etc/localtime  
RUN cp /usr/local/etc/php/php.ini-production /usr/local/etc/php/php.ini
RUN sed -i "s/;date.timezone =/date.timezone = Europe\/Paris/g" /usr/local/etc/php/php.ini && echo "Europe/Paris" > /etc/timezone
RUN sed -i "s/; error_reporting.*$/error_reporting = E_ALL/g" /usr/local/etc/php/php.ini && sed -i "s/; display_errors/display_errors = Off/g" /usr/local/etc/php/php.ini 
RUN sed -i "s/user = www-data/user = apache/g" /usr/local/etc/php-fpm.d/www.conf && sed -i "s/group = www-data/group = apache/g" /usr/local/etc/php-fpm.d/www.conf
RUN sed -i "s/^#LoadModule mpm_event_module modules/LoadModule mpm_event_module modules/g" /etc/apache2/httpd.conf && sed -i "s/^LoadModule mpm_prefork_module modules/#LoadModule mpm_prefork_module modules/g" /etc/apache2/httpd.conf && sed -i "s/DirectoryIndex index.html/DirectoryIndex index.html index.php/g" /etc/apache2/httpd.conf
RUN sed -i "s/^#ServerName .*$/ServerName localhost:8080/1" /etc/apache2/httpd.conf
RUN adduser -S -u 666 -s /bin/sh -h /home/coq -G nobody coq
RUN mkdir /usr/local/coq && wget https://sourcesup.renater.fr/frs/download.php/file/6336/QoQ-CoT_v5.0_Mac_Bec.tgz && tar zxf QoQ-CoT_v5.0_Mac_Bec.tgz -C /app && rm -f QoQ-CoT_v5.0_Mac_Bec.tgz 
RUN cp /app/qoq-cot/ressources/poussin-coq/coq/SOURCES/coq.pl /usr/local/coq/coq.pl && chmod +rx /usr/local/coq/coq.pl && sed -i "s/'coq.yml'/'\/var\/www\/localhost\/htdocs\/config-coq\/coq.yml'/g" /usr/local/coq/coq.pl 
RUN sed -i "s/^.*AllowOverride None$/    AllowOverride AuthConfig/2" /etc/apache2/httpd.conf && sed -i "s/^.*Listen 80$/Listen 8080/" /etc/apache2/httpd.conf

ADD files/php-fpm.conf /etc/apache2/conf.d/php-fpm.conf
ADD files/run.sh /app/run.sh
RUN chmod +rx /app/run.sh

VOLUME ["/var/lib/mysql"]
VOLUME ["/var/www/localhost/htdocs"]

EXPOSE 8080
EXPOSE 9900

ENTRYPOINT ["/app/run.sh"]