#!/bin/sh

HTDOCS=/var/www/localhost/htdocs
DATADIR=/var/lib/mysql
SOCKET=/run/mysqld/mysqld.sock

MYSQLD_PID=""
FPM_PID=""
HTTPD_PID=""
COQ_PID=""

# Stop services in reverse order, MariaDB last so that it shuts down cleanly
shutdown() {
    echo "Stopping QoQ-CoT"
    [ -n "$COQ_PID" ] && kill "$COQ_PID" 2>/dev/null
    [ -n "$HTTPD_PID" ] && kill "$HTTPD_PID" 2>/dev/null
    [ -n "$FPM_PID" ] && kill -QUIT "$FPM_PID" 2>/dev/null
    if [ -n "$MYSQLD_PID" ]; then
        echo "Stopping mariadb database"
        kill -TERM "$MYSQLD_PID" 2>/dev/null
        wait "$MYSQLD_PID"
    fi
    exit "${1:-0}"
}
trap shutdown TERM INT

# Wait until mariadbd answers on the given socket
wait_db() {
    i=0
    until mariadb-admin --socket="$1" ping --silent >/dev/null 2>&1; do
        if ! kill -0 "$2" 2>/dev/null; then
            echo "[!] mariadb failed to start"
            return 1
        fi
        i=$((i+1))
        if [ $i -gt 120 ]; then
            echo "[!] mariadb did not answer after 120s"
            return 1
        fi
        sleep 1
    done
}

# Check if /run/mysqld exists

if [ -d "/run/mysqld" ]; then
    echo "[i] mysqld already present, skipping creation"
else
    echo "[i] mysqld not found, creating...."
    mkdir -p /run/mysqld
fi
chown -R mysql:mysql /run/mysqld

# Check if app deployed, or deployed from another image version
BUILD_ID="$(cat /app/qoq-cot/BUILD_ID)"
if [ ! -f "$HTDOCS/setup.php" ]; then
    echo "Deploying web app"
    rm -f $HTDOCS/index.html
    rsync -a --chown=apache:apache /app/qoq-cot/src/ $HTDOCS/
    cp $HTDOCS/config.php.dist $HTDOCS/config.php
    chown apache:apache $HTDOCS $HTDOCS/config.php
    echo "$BUILD_ID" > $HTDOCS/.qoq-build-id
elif [ "$(cat $HTDOCS/.qoq-build-id 2>/dev/null)" != "$BUILD_ID" ]; then
    echo "Updating web app code (config.php, .htaccess, .htpasswd, csv/ and config-coq/ are kept)"
    rsync -a --chown=apache:apache \
        --exclude=/config.php --exclude=/.htaccess --exclude=/.htpasswd --exclude=/csv/ --exclude=/config-coq/ \
        /app/qoq-cot/src/ $HTDOCS/
    echo "$BUILD_ID" > $HTDOCS/.qoq-build-id
fi

# UIDs may differ from the image that created the volumes (mysql and apache were swapped before Alpine 3.13)
find $HTDOCS \( -path $HTDOCS/csv -o -path $HTDOCS/config-coq \) -prune -o \! -user apache -exec chown -h apache:apache {} +

# config.php contient le mot de passe de la base : on le rend illisible aux autres comptes
# du conteneur (coq, mysql). S'applique aussi aux installations déjà déployées.
if [ -f $HTDOCS/config.php ]; then
    chmod 640 $HTDOCS/config.php
fi
DATADIR_OWNER=""
if [ -d $DATADIR/mysql ]; then
    DATADIR_OWNER="$(stat -c '%u:%g' $DATADIR/mysql)"
    find $DATADIR \! -user mysql -exec chown -h mysql:mysql {} +
fi

# Check if csv dir exists
if [ ! -d "$HTDOCS/csv" ]; then
    mkdir $HTDOCS/csv
    chown coq:root $HTDOCS/csv
    chmod 750 $HTDOCS/csv
fi

# Check if coq.yaml deployed
if [ ! -f "$HTDOCS/config-coq/coq.yml" ]; then
    echo "Deploying coq.yaml"
    mkdir -p $HTDOCS/config-coq
    cp /app/qoq-cot/ressources/poussin-coq/coq/conf/coq.yml $HTDOCS/config-coq/
    chown -R coq:root $HTDOCS/config-coq
    chmod 700 $HTDOCS/config-coq
    chmod 600 $HTDOCS/config-coq/coq.yml
    sed -i "s/port :.*$/port : 9900/g" $HTDOCS/config-coq/coq.yml
    sed -i "s/exclude :.*$/exclude : ^(DWM|UMFD)/g" $HTDOCS/config-coq/coq.yml
fi

# If TZONE env var set
if [ -n "$TZONE" ]; then
    echo "Setting date.timezone in php.ini"
    sed -i "s|^date.timezone.*$|date.timezone = $TZONE|" "$PHP_INI_DIR/conf.d/zz-qoq.ini"
fi


# check if mysql db exists

MARIADB_ROOT_PASSWORD=""
MARIADB_COQUSER_PASSWORD=""
ADMIN_PASSWORD=""

echo "Checking if  /var/lib/mysql exists"
if [ ! -d $DATADIR/mysql ]; then
    echo "Installing database"
    mariadb-install-db --user=mysql --datadir=$DATADIR --skip-test-db > /dev/null

    initfile="/app/init_mariadb"

    MARIADB_ROOT_PASSWORD="$(pwgen -1 32)"
    MARIADB_COQUSER_PASSWORD="$(pwgen -1 -B 16)"

    cat << EOF > $initfile
      FLUSH PRIVILEGES;
      ALTER USER 'root'@'localhost' IDENTIFIED BY '$MARIADB_ROOT_PASSWORD';
      CREATE DATABASE IF NOT EXISTS COQQOQ;
      CREATE USER 'coq-user'@'localhost' IDENTIFIED BY '$MARIADB_COQUSER_PASSWORD';
      CREATE USER 'coq-user'@'%' IDENTIFIED BY '$MARIADB_COQUSER_PASSWORD';
      GRANT ALL PRIVILEGES ON COQQOQ.* TO 'coq-user'@'localhost';
      GRANT ALL PRIVILEGES ON COQQOQ.* TO 'coq-user'@'%';
      FLUSH PRIVILEGES;
EOF
    mariadbd --user=mysql --bootstrap --skip-name-resolve < $initfile
    rm -f $initfile

    echo "Configuring config.php file"
    sed -i "s/^.*define('SQL_DBNAME'.*$/define('SQL_DBNAME', 'COQQOQ');/g" $HTDOCS/config.php
    sed -i "s/^.*define('SQL_HOST'.*$/define('SQL_HOST', '127.0.0.1');/g" $HTDOCS/config.php
    sed -i "s/^.*define('SQL_PORT'.*$/define('SQL_PORT', '3306');/g" $HTDOCS/config.php
    sed -i "s/^.*define('SQL_USERNAME'.*$/define('SQL_USERNAME', 'coq-user');/g" $HTDOCS/config.php
    sed -i "s/^.*define('SQL_PASSWORD'.*$/define('SQL_PASSWORD', '$MARIADB_COQUSER_PASSWORD');/g" $HTDOCS/config.php
    sed -i "s/^.*define('FIRST_ADMIN'.*$/define('FIRST_ADMIN', 'admin');/g" $HTDOCS/config.php
    sed -i "s/^.*define('URL_ANNUAIRE'.*$/define('URL_ANNUAIRE', '');/g" $HTDOCS/config.php
    sed -i "s/^.*define('CONNEXIONS_CACHE'.*$/define('CONNEXIONS_CACHE',90);/g" $HTDOCS/config.php

    echo "Configuring coq.yaml file"
    sed -i "s/SQL_DBNAME.*$/SQL_DBNAME : COQQOQ/g" $HTDOCS/config-coq/coq.yml
    sed -i "s/SQL_HOST.*$/SQL_HOST : 127.0.0.1/g" $HTDOCS/config-coq/coq.yml
    sed -i "s/SQL_PORT.*$/SQL_PORT : 3306/g" $HTDOCS/config-coq/coq.yml
    sed -i "s/SQL_USERNAME.*$/SQL_USERNAME : coq-user/g" $HTDOCS/config-coq/coq.yml
    sed -i "s/SQL_PASSWORD.*$/SQL_PASSWORD : $MARIADB_COQUSER_PASSWORD/g" $HTDOCS/config-coq/coq.yml
fi;

# Upgrade system tables when the database was created by another MariaDB version
MARIADB_VERSION="$(mariadbd --version | awk '{print $3}')"
DATADIR_VERSION="$(cat $DATADIR/mariadb_upgrade_info $DATADIR/mysql_upgrade_info 2>/dev/null | tr -d '\0\n' | head -c 64)"
if [ "$MARIADB_VERSION" != "$DATADIR_VERSION" ]; then
    echo "Upgrading mariadb system tables (${DATADIR_VERSION:-unknown} -> $MARIADB_VERSION)"
    upgrade_socket=/run/mysqld/upgrade.sock
    upgrade_log=/run/mysqld/upgrade.err
    mariadbd --user=mysql --skip-grant-tables --skip-networking --socket=$upgrade_socket --log-error=$upgrade_log &
    upgrade_pid=$!
    if ! wait_db $upgrade_socket $upgrade_pid; then
        cat $upgrade_log
        if grep -q "Upgrade after a crash is not supported" $upgrade_log; then
            # Give the files back to their previous owner so that the previous image can start again
            chown -R -h "$DATADIR_OWNER" $DATADIR
            echo "[!] This database was not shut down cleanly by MariaDB $DATADIR_VERSION and cannot be upgraded."
            echo "[!] Start the previous image again on the same volumes, then stop its database cleanly with:"
            echo "[!]     docker exec <container> sh -c 'kill \$(pidof mysqld); while pidof mysqld >/dev/null; do sleep 1; done'"
            echo "[!] then stop the container and start this image again."
        fi
        exit 1
    fi
    mariadb-upgrade --socket=$upgrade_socket --upgrade-system-tables || echo "[!] mariadb-upgrade failed"
    kill -TERM $upgrade_pid
    wait $upgrade_pid
fi

echo "Checking if  /var/www/localhost/htdocs/.htaccess exists"
if [ ! -f $HTDOCS/.htaccess ]; then
    echo "Creating .htaccess"
    cat << EOF > $HTDOCS/.htaccess

    AuthName "Restricted Area"
    AuthType Basic
    AuthUserFile "/var/www/localhost/htdocs/.htpasswd"
    Require valid-user
EOF

   ADMIN_PASSWORD="$(pwgen -1 -B 16)"
   # -B : hachage bcrypt plutôt que le MD5 (apr1) par défaut d'Apache
   /usr/bin/htpasswd -B -b -c  $HTDOCS/.htpasswd admin $ADMIN_PASSWORD
fi;

# Start mariadb
echo "Starting mariadb database"
mariadbd --user=mysql --skip-networking=0 --silent-startup 2>&1 &
MYSQLD_PID=$!
wait_db $SOCKET $MYSQLD_PID || exit 1

# Start php-fpm
php-fpm -F 2>&1 &
FPM_PID=$!

# Start Apache2
echo "Starting Apache 2"
/usr/sbin/httpd -DFOREGROUND 2>&1 &
HTTPD_PID=$!



# Modify k1,k2,k3,k4 if not set
NMBR="$(/usr/bin/shuf -i 1-65535 -n 1)"
sed -i "s/k1 : <un nombre quelconque.*$/k1 : $NMBR/1" $HTDOCS/config-coq/coq.yml
NMBR="$(/usr/bin/shuf -i 1-65535 -n 1)"
sed -i "s/k2 : <un nombre quelconque.*$/k2 : $NMBR/1" $HTDOCS/config-coq/coq.yml
NMBR="$(/usr/bin/shuf -i 1-65535 -n 1)"
sed -i "s/k3 : <un nombre quelconque.*$/k3 : $NMBR/1" $HTDOCS/config-coq/coq.yml
NMBR="$(/usr/bin/shuf -i 1-65535 -n 1)"
sed -i "s/k4 : <un nombre quelconque.*$/k4 : $NMBR/1" $HTDOCS/config-coq/coq.yml

echo "***********************************************************"
echo "|                      COQ SETTINGS                       |"
echo "***********************************************************"
grep "k1" $HTDOCS/config-coq/coq.yml | grep -v "#"
grep "k2" $HTDOCS/config-coq/coq.yml | grep -v "#"
grep "k3" $HTDOCS/config-coq/coq.yml | grep -v "#"
grep "k4" $HTDOCS/config-coq/coq.yml | grep -v "#"
echo


if [ -n "$MARIADB_ROOT_PASSWORD" ]; then
    echo "************************************************************"
    echo "|                     MARIADB SETTINGS                     |"
    echo "************************************************************"
    echo "| MARIADB ROOT PASSWORD : $MARIADB_ROOT_PASSWORD |"
    echo "************************************************************"
    echo "| MARIADB COQ-USER PASSWORD : $MARIADB_COQUSER_PASSWORD             |"
    echo "************************************************************"
    echo
fi

if [ -n "$ADMIN_PASSWORD" ]; then
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
su - coq -c "exec /usr/local/coq/coq.pl" &
COQ_PID=$!

# Stop the whole container as soon as one service dies
wait -n
echo "[!] A service has stopped unexpectedly"
shutdown 1
