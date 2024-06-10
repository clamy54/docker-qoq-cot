#!/bin/sh

# Check if /run/mysqld exists

if [ -d "/run/mysqld" ]; then
    echo "[i] mysqld already present, skipping creation"
    chown -R mysql:mysql /run/mysqld
else
    echo "[i] mysqld not found, creating...."
    mkdir -p /run/mysqld
    chown -R mysql:mysql /run/mysqld
fi

# Check if app deployed
if [ ! -f "/var/www/localhost/htdocs/setup.php" ]; then
    echo "Deploying web app"
    rm -f /var/www/localhost/htdocs/index.html 
    rsync -arv /app/qoq-cot/src/ /var/www/localhost/htdocs/ 
    cp /var/www/localhost/htdocs/config.php.dist /var/www/localhost/htdocs/config.php 
    chown -R apache:apache /var/www/localhost/htdocs
    sed -i "s/public function getTableConnexions/public static function getTableConnexions/g" /var/www/localhost/htdocs/lib/Dao.class.php
fi

# Check if csv dir exists
if [ ! -d "/var/www/localhost/htdocs/csv" ]; then
    mkdir /var/www/localhost/htdocs/csv
    chown coq:root /var/www/localhost/htdocs/csv
    chmod 750 /var/www/localhost/htdocs/csv
fi

# Check if coq.yaml deployed
if [ ! -f "/var/www/localhost/htdocs/config-coq/coq.yml" ]; then
    echo "Deploying coq.yaml"
    mkdir /var/www/localhost/htdocs/config-coq 
    cp /app/qoq-cot/ressources/poussin-coq/coq/conf/coq.yml /var/www/localhost/htdocs/config-coq/ 
    chown -R coq:root /var/www/localhost/htdocs/config-coq 
    chmod 700 /var/www/localhost/htdocs/config-coq 
    chmod 600 /var/www/localhost/htdocs/config-coq/coq.yml
    sed -i "s/port :.*$/port : 9900/g" /var/www/localhost/htdocs/config-coq/coq.yml 
    sed -i "s/exclude :.*$/exclude : ^(DWM|UMFD)/g" /var/www/localhost/htdocs/config-coq/coq.yml
fi

# If TZONE env var set
if [ ! -z "$TZONE" ]; then
     echo "Setting date.timezone in php.ini"
     sed -i "s/date.timezone.*$/date.timezone = $TZONE/g" /usr/local/etc/php/php.ini
fi


# check if mysql db exists

MARIADB_ROOT_PASSWORD=""
MARIADB_COQUSER_PASSWORD=""
ADMIN_PASSWORD=""

echo "Checking if  /var/lib/mysql exists"
if [ ! -d /var/lib/mysql/mysql ]; then 
    echo "Installing database"
    mariadb-install-db --user=mysql --ldata=/var/lib/mysql > /dev/null

    initfile="/app/init_mariadb"

    MARIADB_ROOT_PASSWORD="$(pwgen -1 32)"
    MARIADB_COQUSER_PASSWORD="$(pwgen -1 -B 16)"

    cat << EOF > $initfile

      DROP DATABASE test;
      USE mysql;
      DELETE FROM user;
      FLUSH PRIVILEGES;
      GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY '$MARIADB_ROOT_PASSWORD' WITH GRANT OPTION;
      GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' IDENTIFIED BY '$MARIADB_ROOT_PASSWORD'  WITH GRANT OPTION;
      GRANT ALL PRIVILEGES ON *.* TO 'mariadb.sys'@'localhost' IDENTIFIED BY '$MARIADB_ROOT_PASSWORD';
      CREATE DATABASE IF NOT EXISTS COQQOQ;
      CREATE USER 'coq-user'@'localhost' IDENTIFIED BY '$MARIADB_COQUSER_PASSWORD';
      CREATE USER 'coq-user'@'%' IDENTIFIED BY '$MARIADB_COQUSER_PASSWORD';           
      GRANT ALL PRIVILEGES ON COQQOQ.* TO 'coq-user'@'localhost';
      GRANT ALL PRIVILEGES ON COQQOQ.* TO 'coq-user'@'%';
      FLUSH PRIVILEGES;
EOF
    /usr/bin/mysql_install_db --user=mysql --ldata=/var/lib/mysql
    /usr/bin/mysqld --user=mysql --bootstrap --verbose=0 --skip-name-resolve --skip-networking=0 < $initfile
    rm -f $initfile

    echo "Configuring config.php file"
    sed -i "s/^.*define('SQL_DBNAME'.*$/define('SQL_DBNAME', 'COQQOQ');/g" /var/www/localhost/htdocs/config.php
    sed -i "s/^.*define('SQL_HOST'.*$/define('SQL_HOST', '127.0.0.1');/g" /var/www/localhost/htdocs/config.php
    sed -i "s/^.*define('SQL_PORT'.*$/define('SQL_PORT', '3306');/g" /var/www/localhost/htdocs/config.php
    sed -i "s/^.*define('SQL_USERNAME'.*$/define('SQL_USERNAME', 'coq-user');/g" /var/www/localhost/htdocs/config.php
    sed -i "s/^.*define('SQL_PASSWORD'.*$/define('SQL_PASSWORD', '$MARIADB_COQUSER_PASSWORD');/g" /var/www/localhost/htdocs/config.php
    sed -i "s/^.*define('FIRST_ADMIN'.*$/define('FIRST_ADMIN', 'admin');/g" /var/www/localhost/htdocs/config.php
    sed -i "s/^.*define('URL_ANNUAIRE'.*$/define('URL_ANNUAIRE', '');/g" /var/www/localhost/htdocs/config.php
    sed -i "s/^.*define('CONNEXIONS_CACHE'.*$/define('CONNEXIONS_CACHE',90);/g" /var/www/localhost/htdocs/config.php

    echo "Configuring coq.yaml file"
    sed -i "s/SQL_DBNAME.*$/SQL_DBNAME : COQQOQ/g" /var/www/localhost/htdocs/config-coq/coq.yml
    sed -i "s/SQL_HOST.*$/SQL_HOST : 127.0.0.1/g" /var/www/localhost/htdocs/config-coq/coq.yml
    sed -i "s/SQL_PORT.*$/SQL_PORT : 3306/g" /var/www/localhost/htdocs/config-coq/coq.yml
    sed -i "s/SQL_USERNAME.*$/SQL_USERNAME : coq-user/g" /var/www/localhost/htdocs/config-coq/coq.yml
    sed -i "s/SQL_PASSWORD.*$/SQL_PASSWORD : $MARIADB_COQUSER_PASSWORD/g" /var/www/localhost/htdocs/config-coq/coq.yml
fi;

echo "Checking if  /var/www/localhost/htdocs/.htaccess exists"
if [ ! -f /var/www/localhost/htdocs/.htaccess ]; then 
    echo "Creating .htaccess"
    cat << EOF > /var/www/localhost/htdocs/.htaccess

    AuthName "Restricted Area"
    AuthType Basic
    AuthUserFile "/var/www/localhost/htdocs/.htpasswd"
    Require valid-user
EOF
   
   ADMIN_PASSWORD="$(pwgen -1 -B 8)"
   /usr/bin/htpasswd -b -c  /var/www/localhost/htdocs/.htpasswd admin $ADMIN_PASSWORD
fi;

# Start mariadb
echo "Starting mariadb database"
exec /usr/bin/mysqld --user=mysql --skip-networking=0 --silent-startup 2>&1 &

# Start php-fpm
exec /usr/local/sbin/php-fpm  2>&1 &

# Start Apache2
echo "Starting Apache 2"
exec /usr/sbin/httpd 2>&1 &



# Modify k1,k2,k3,k4 if not set
NMBR="$(/usr/bin/shuf -i 1-65535 -n 1)"
sed -i "s/k1 : <un nombre quelconque.*$/k1 : $NMBR/1" /var/www/localhost/htdocs/config-coq/coq.yml
NMBR="$(/usr/bin/shuf -i 1-65535 -n 1)"
sed -i "s/k2 : <un nombre quelconque.*$/k2 : $NMBR/1" /var/www/localhost/htdocs/config-coq/coq.yml
NMBR="$(/usr/bin/shuf -i 1-65535 -n 1)"
sed -i "s/k3 : <un nombre quelconque.*$/k3 : $NMBR/1" /var/www/localhost/htdocs/config-coq/coq.yml
NMBR="$(/usr/bin/shuf -i 1-65535 -n 1)"
sed -i "s/k4 : <un nombre quelconque.*$/k4 : $NMBR/1" /var/www/localhost/htdocs/config-coq/coq.yml

echo "***********************************************************"
echo "|                      COQ SETTINGS                       |"
echo "***********************************************************"
grep "k1" /var/www/localhost/htdocs/config-coq/coq.yml | grep -v "#"
grep "k2" /var/www/localhost/htdocs/config-coq/coq.yml | grep -v "#"
grep "k3" /var/www/localhost/htdocs/config-coq/coq.yml | grep -v "#"
grep "k4" /var/www/localhost/htdocs/config-coq/coq.yml | grep -v "#"
echo


if [ ! -z "$MARIADB_ROOT_PASSWORD" ]; then
    echo "************************************************************"
    echo "|                     MARIADB SETTINGS                     |"
    echo "************************************************************"
    echo "| MARIADB ROOT PASSWORD : $MARIADB_ROOT_PASSWORD |"
    echo "************************************************************"
    echo "| MARIADB COQ-USER PASSWORD : $MARIADB_COQUSER_PASSWORD             |"
    echo "************************************************************"
    echo
fi

if [ ! -z "$ADMIN_PASSWORD" ]; then
    echo "***********************************************************"
    echo "|                   WEB ACCESS SETTINGS                   |"
    echo "***********************************************************"
    echo "| LOGIN : admin                                           |"
    echo "***********************************************************"
    echo "| PASSWORD : $ADMIN_PASSWORD                                     |"
    echo "***********************************************************"
    echo
fi

echo "Starting Coq"
su - coq -c "/usr/local/coq/coq.pl"