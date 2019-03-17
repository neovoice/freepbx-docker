FROM ubuntu:18.04

# Set environment variables
ENV DEBIAN_FRONTEND noninteractive
ENV ASTERISKUSER asterisk
ENV CFLAGS -O2 -pipe

WORKDIR /usr/src

# Install Required Dependencies
RUN apt-get update \
        && apt-get install -y \
            curl \ 
            gnupg \
        && curl -sL https://deb.nodesource.com/setup_8.x | bash - \
        && apt-get upgrade -y \
        && apt-get install -y \
            apache2 \
            autoconf \
            automake \
            bison \
            build-essential \
            cron \
            curl \
            dirmngr \
            flex \
            libasound2-dev \
            libcurl4-openssl-dev \
            libical-dev \
            libicu-dev \
            libmariadb-dev \
            libncurses5-dev \
            libneon27-dev \
            libnewt-dev \
            libogg-dev \
            libspandsp-dev \
            libsqlite3-dev \
            libsrtp0-dev \
            libssl-dev \
            libtool \
            libtool-bin \
            libvorbis-dev \
            libxml2-dev \
            mariadb-client \
            mariadb-server \
            mpg123 \
            nodejs \
            php \
            php-cli \
            php-curl \
            php-gd \
            php-mbstring \
            php-mysql \
            php-pdo \
            php-pear \
            pkg-config \
            python-dev \
            sox \
            sqlite3 \
            subversion \
            unixodbc \
            unixodbc-dev \
            uuid \
            uuid-dev \
            wget \
        && wget https://downloads.mariadb.com/Connectors/odbc/connector-odbc-3.0.8/mariadb-connector-odbc-3.0.8-ga-debian-x86_64.tar.gz \
        && tar vxfz mariadb-connector-odbc-3.0.8-ga-debian-x86_64.tar.gz \
        && cp lib/libmaodbc.so /usr/local/lib/ \
        && rm -rf * \
        && apt-get clean \
        && rm -rf /var/lib/apt/lists/* \
        && rm -rf /tmp/*


# Add config files
COPY conf/asterisk.conf /etc/asterisk.conf
COPY conf/odbc.ini /etc/odbc.ini
COPY conf/odbcinst.ini /etc/odbcinst.ini

# Compile and Install Asterisk
RUN wget http://downloads.asterisk.org/pub/telephony/asterisk/asterisk-16-current.tar.gz \
        && tar xvfz asterisk-16-current.tar.gz \
        && rm -f asterisk-16-current.tar.gz \
        && cd asterisk-* \
        && contrib/scripts/get_mp3_source.sh \
        && apt-get update \
        && yes y | contrib/scripts/install_prereq install \
        && ./configure --with-pjproject-bundled --with-jansson-bundled \
        && make menuselect.makeopts \
        && menuselect/menuselect \
            --enable app_macro \
            --enable format_mp3 \
            menuselect.makeopts \
        && make \
        && make install \
        && make config \
        && ldconfig \
        && rm -rf /usr/src/asterisk* \
        && apt-get clean \
        && rm -rf /var/lib/apt/lists/* \
        && rm -rf /tmp/*

# Add Asterisk user & Configure apache
RUN useradd -m $ASTERISKUSER \
        && touch /etc/asterisk/modules.conf \
        && touch /etc/asterisk/cdr.conf \
        && chown $ASTERISKUSER. /var/run/asterisk \ 
        && chown -R $ASTERISKUSER. /etc/asterisk \
        && chown -R $ASTERISKUSER /var/lib/asterisk /var/log/asterisk /var/spool/asterisk \
        && chown -R $ASTERISKUSER. /usr/lib/asterisk \
        && chown -R $ASTERISKUSER. /var/www/html \
        && sed -i 's/\(^upload_max_filesize = \).*/\120M/' /etc/php/7.2/apache2/php.ini\
        && sed -i 's/^\(User\|Group\).*/\1 asterisk/' /etc/apache2/apache2.conf \
        && sed -i 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf \
        && a2enmod rewrite

# Download and install FreePBX
RUN find /var/lib/mysql -type f -exec touch {} \; \
        && /etc/init.d/mysql start \
        && mysqladmin -u root create asterisk \
        && mysql -u root -e "CREATE USER '$ASTERISKUSER'@'localhost' IDENTIFIED BY '';" \
        && mysql -u root -e "GRANT ALL PRIVILEGES ON asterisk.* TO '$ASTERISKUSER'@'localhost' IDENTIFIED BY '';" \
        && mysql -u root -e "GRANT ALL PRIVILEGES ON asteriskcdrdb.* TO '$ASTERISKUSER'@'localhost' IDENTIFIED BY '';" \
        && wget http://mirror.freepbx.org/modules/packages/freepbx/freepbx-15.0-latest.tgz \
        && tar vxfz freepbx-15.0-latest.tgz \
        && rm -f freepbx-15.0-latest.tgz \
        && rm -rf /var/www/html/* \
        && cd freepbx \
        && ./start_asterisk start \
        && sed -i \
            "s/timeout = 60/timeout = 600/g" \
            ./amp_conf/htdocs/admin/libraries/Composer/vendor/symfony/process/Process.php \
        && ./install -n \
        && fwconsole ma upgradeall \
        && fwconsole ma downloadinstall callforward ivr ringgroups \
        && sed -i \
             "s/\(.*count(\$alterclauses).*\)/if (\!is_array(\$alterclauses)) \$alterclauses = array();\n\\1/g" \
             /var/www/html/admin/modules/cdr/install.php \
        && fwconsole ma install cdr \
        && fwconsole restart \
        && sed -i \
            "s/timeout = 600/timeout = 60/g" \
            ./amp_conf/htdocs/admin/libraries/Composer/vendor/symfony/process/Process.php \
        && sed -i \
            "s/\(require_once.*\)/\$amp_conf['CDRDBHOST'] = 'localhost';\n\\1/g" \
            /etc/freepbx.conf \
        && sed -i \
            "s/\(require_once.*\)/\$amp_conf['CDRDBUSER'] = 'asterisk';\n\\1/g" \
            /etc/freepbx.conf \
        && sed -i \
            "s/\(require_once.*\)/\$amp_conf['CDRDBPASS'] = '';\\n\\1/g" \
            /etc/freepbx.conf \
        && sed -i \
            "s/\(require_once.*\)/\$amp_conf['CDRDBNAME'] = 'asteriskcdr';\n\n\\1/g" \
            /etc/freepbx.conf \
        && mysqldump asterisk > ~/asterisk.sql \
        && mysqldump asteriskcdrdb > ~/asterisk_cdr.sql \
        && rm -rf /tmp/*

WORKDIR /var/log/asterisk/

COPY entrypoint.sh /
RUN chmod 755 /entrypoint.sh

CMD ["/entrypoint.sh"]
