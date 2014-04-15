#!/bin/bash
#
# Installs a complete web environment 
#
# <UDF name="notify_email" Label="Send email notification to" example="Email address to send notification and system alerts. Check Spam folder if you don't receive a notification within 6 minutes." />

# <UDF name="user_name" label="Unprivileged user account name" example="This is the account that you will be using to log in." />
# <UDF name="user_password" label="Unprivileged user password" />
# <UDF name="user_sshkey" label="Public Key for user" default="" example="Recommended method of authentication. It is more secure than password log in." />
# <UDF name="sshd_passwordauth" label="Use SSH password authentication" oneof="Yes,No" default="No" example="Turn off password authentication if you have added a Public Key." />
# <UDF name="sshd_permitrootlogin" label="Permit SSH root login" oneof="No,Yes" default="No" example="Root account should not be exposed." />

# <UDF name="user_shell" label="Shell" oneof="/bin/zsh,/bin/bash" default="/bin/bash" />

# <UDF name="sys_hostname" label="System hostname" default="myvps" example="Name of your server, i.e. linode1." />

# <UDF name="setup_postgresql" label="Configure PostgreSQL and create database?" oneof="Yes,No" default="Yes" />
# <UDF name="postgresql_database" label="PostgreSQL database name" example="PostgreSQL database name, ASCII only." default="" />
# <UDF name="postgresql_user" label="PostgreSQL database user" example="PostgreSQL database user name, ASCII only." default="" />
# <UDF name="postgresql_password" label="PostgreSQL user password" default="" />

# <UDF name="setup_mongodb" label="Install MongoDB" oneof="Yes,No" default="No" />

# <UDF name="sys_private_ip" Label="Private IP" default="" example="Configure network card to listen on this Private IP (if enabled in Linode/Remote Access settings tab). See http://library.linode.com/networking/configuring-static-ip-interfaces" />
# <UDF name="r_env" Label="Rails/Rack environment to run" default="production" />
# <UDF name="nginx_release" Label="nginx Release" default="1.0.4" example="1.0.4" />
# <UDF name="redis_release" Label="Redis Release" default="2.2.11" example="2.2.11" />
# <UDF name="deploy_user" Label="Name of deployment user" default="app" />
# <UDF name="deploy_password" Label="Password for deployment user" />
# <UDF name="deploy_sshkey" Label="Deployment user public ssh key" />
# <UDF name="new_hostname_fqdn" Label="Server's fully-qualified hostname" default="appserver.example.com" />

# TODO
# god
# redis
# elasticsearch
# nginx
# puma/unicorn

set -e
set -u
#set -x

USER_GROUPS=sudo

exec &> /root/stackscript.log

source <ssinclude StackScriptID="1"> # StackScript Bash Library
system_update

source <ssinclude StackScriptID="124"> # lib-system
system_install_mercurial
system_start_etc_dir_versioning #start recording changes of /etc config files

# Configure system
source <ssinclude StackScriptID="123"> # lib-system-ubuntu
system_update_hostname "$SYS_HOSTNAME"
system_record_etc_dir_changes "Updated hostname" # SS124

# Create user account
system_add_user "$USER_NAME" "$USER_PASSWORD" "$USER_GROUPS" "$USER_SHELL"
if [ "$USER_SSHKEY" ]; then
    system_user_add_ssh_key "$USER_NAME" "$USER_SSHKEY"
fi
system_record_etc_dir_changes "Added unprivileged user account" # SS124

# Configure sshd
system_sshd_permitrootlogin "$SSHD_PERMITROOTLOGIN"
system_sshd_passwordauthentication "$SSHD_PASSWORDAUTH"
touch /tmp/restart-ssh
system_record_etc_dir_changes "Configured sshd" # SS124

# Lock user account if not used for login
if [ "SSHD_PERMITROOTLOGIN" == "No" ]; then
    system_lock_user "root"
    system_record_etc_dir_changes "Locked root account" # SS124
fi

# Install Postfix
postfix_install_loopback_only # SS1
system_record_etc_dir_changes "Installed postfix loopback" # SS124

# Setup logcheck
system_security_logcheck
system_record_etc_dir_changes "Installed logcheck" # SS124

# Setup fail2ban
system_security_fail2ban
system_record_etc_dir_changes "Installed fail2ban" # SS124

# Setup firewall
system_security_ufw_configure_basic
system_record_etc_dir_changes "Configured UFW" # SS124

# lib-system - SS124
system_install_utils
system_install_build
system_install_git
system_record_etc_dir_changes "Installed common utils"
  
  
# stackscript: nginx, ruby, passenger, redis
# Installs Ruby 1.9.2 + Nginx + Passenger + Git + Bundler + Redis + Deploy User
# Things to remember after install or to automate later:
# - adjust server timezone if required
# - put SSL certificate files at /usr/local/share/ca-certificates/
# - set up nginx to point to deployment app and eventual static site
# - create logrotate file to the deployed app logs
# - generate github ssh deployment keys
# - setup reverse DNS on Linode control panel
# - run cap production deploy:setup to configure initial files
#

NEW_HOSTNAME=`echo $NEW_HOSTNAME_FQDN | cut -d. -f1`

NGINX_PREFIX="/usr/local/nginx-$NGINX_RELEASE"
NGINX_OPTIONS="--prefix=$NGINX_PREFIX --with-http_ssl_module --with-pcre --user=nginx --group=nginx --without-http_scgi_module --without-http_fastcgi_module --without-http_uwsgi_module"

REDIS_PREFIX="/usr/local/redis-$REDIS_RELEASE"

exec &> /root/stackscript.log

function log {
  echo "### $1 -- `date '+%D %T'`"
}

function install_essentials {

  DEPS="build-essential 
        libpcre3-dev 
        libssl-dev 
        libcurl4-openssl-dev 
        openssh-server 
        git-core 
        tcl8.5 
        libmysqlclient16 
        libmysqlclient16-dev"

  aptitude -y install $DEPS 
  # See StackScript=1, vim, color root prompt, etc.
  goodstuff
  echo "set -o vi" >> /root/.bashrc
}

function download_and_extract_ruby {
  cd /usr/local/src
  wget ftp://ftp.ruby-lang.org/pub/ruby/2.0/$RUBY_VERSION.tar.gz
  tar xzf $RUBY_VERSION.tar.gz
  cd $RUBY_VERSION
}

function compile_and_install_ruby {
  ./configure
  make
  make install
}

function set_production_gemrc {
  cat > ~/.gemrc << EOF
verbose: true
bulk_treshold: 1000
install: --no-ri --no-rdoc --env-shebang
benchmark: false
backtrace: false
update: --no-ri --no-rdoc --env-shebang
update_sources: true
EOF
}

function download_and_extract_nginx {
    cd /usr/local/src
    curl http://nginx.org/download/nginx-$NGINX_RELEASE.tar.gz > nginx-$NGINX_RELEASE.tar.gz
    tar xvfz nginx-$NGINX_RELEASE.tar.gz
    cd nginx-$NGINX_RELEASE
}

function compile_and_install_nginx {
    ./configure $NGINX_OPTIONS
    make
    make install    

    useradd nginx
    mkdir -p $NGINX_PREFIX/{logs,proxy_temp,sites-available,sites-enabled,client_body_temp}
    chown -R nginx.nginx $NGINX_PREFIX/{logs,proxy_temp,client_body_temp}

    curl https://raw.github.com/napkindrawing/system_defaults/master/etc/nginx/nginx.conf > $NGINX_PREFIX/conf/nginx.conf
}

function download_and_extract_redis {
    cd /usr/local/src
    curl http://redis.googlecode.com/files/redis-$REDIS_RELEASE.tar.gz > redis-$REDIS_RELEASE.tar.gz
    tar xfz redis-$REDIS_RELEASE.tar.gz
}

function compile_and_install_redis {
    cd /usr/local/src/redis-$REDIS_RELEASE
    make PREFIX=$REDIS_PREFIX
    # make test
    mkdir -p $REDIS_PREFIX/bin
    cp src/redis-{cli,server,benchmark,check-aof,check-dump} $REDIS_PREFIX/bin
    # make install
}

function set_default_environment {
  cat >> /etc/environment << EOF
RAILS_ENV=$R_ENV
RACK_ENV=$R_ENV
EOF
}

function create_deployment_demo {
  mkdir -p /home/$DEPLOY_USER/deploy/hello/{tmp,public}
  cat > /home/$DEPLOY_USER/deploy/hello/config.ru <<EOF

app = proc do |env|
    [200, { "Content-Type" => "text/html" }, ["hello <b>world</b>"]]
end
run app

EOF

  ln -s /home/$DEPLOY_USER/deploy/hello/public /home/$DEPLOY_USER/sites/hello
}

function configure_default_host {

  cat > $NGINX_PREFIX/sites-available/$NEW_HOSTNAME <<EOF

server {
    listen 80;
    server_name $NEW_HOSTNAME_FQDN;
    access_log $NGINX_PREFIX/logs/$NEW_HOSTNAME.access.log;
    access_log $NGINX_PREFIX/logs/$NEW_HOSTNAME.error.log;

    location = / {
        empty_gif;
    }

    root /home/$DEPLOY_USER/sites;

    passenger_enabled on;

    passenger_base_uri /hello;
}

EOF

  ln -s $NGINX_PREFIX/sites-available/$NEW_HOSTNAME $NGINX_PREFIX/sites-enabled/$NEW_HOSTNAME

  /etc/init.d/nginx restart

}

function create_deployment_user {
  system_add_user $DEPLOY_USER $DEPLOY_PASSWORD "users,sudo"
  system_user_add_ssh_key $DEPLOY_USER "$DEPLOY_SSHKEY"
  system_update_locale_en_US_UTF_8
  cp ~/.gemrc /home/$DEPLOY_USER/
  mkdir /home/$DEPLOY_USER/{sites,deploy}
  chown $DEPLOY_USER:$DEPLOY_USER /home/$DEPLOY_USER/{.gemrc,sites,deploy}

  # Add nginx to the app group
  usermod -G app nginx

}

function configure_passenger_nginx {
  PASSENGER_ROOT=`passenger-config --root`
  PASSENGER_RUBY=`which ruby`

  perl -i -lane "print; if(/^http/) { print '    passenger_root $PASSENGER_ROOT;'; print '    passenger_ruby $PASSENGER_RUBY;' }" $NGINX_PREFIX/conf/nginx.conf
}

function set_nginx_boot_up {

   curl https://raw.github.com/napkindrawing/system_defaults/master/etc/init.d/nginx > /etc/init.d/nginx
   chmod +x /etc/init.d/nginx
   
   for re in "s|/usr/local/nginx/|$NGINX_PREFIX/|g" \
             "s|/usr/local/sbin/nginx|$NGINX_PREFIX/sbin/nginx|g" \
             "s|PIDSPATH=/var/run|PIDSPATH=$NGINX_PREFIX/logs|g" 
             do 
       perl -i -lape "$re" /etc/init.d/nginx;
   done
   
   /usr/sbin/update-rc.d -f nginx defaults

   /etc/init.d/nginx start
   
   cat > /etc/logrotate.d/nginx << EOF
$NGINX_PREFIX/logs/* {
        daily
        missingok
        rotate 52
        compress
        delaycompress
        notifempty
        create 640 nobody root
        sharedscripts
        postrotate
                [ ! -f $NGINX_PREFIX/logs/nginx.pid ] || kill -USR1 `cat $NGINX_PREFIX/logs/nginx.pid`
        endscript
}
EOF

   
}

log "Updating System..."
system_update

log "Installing essentials..."
install_essentials

log "Setting hostname to $NEW_HOSTNAME"
system_update_hostname $NEW_HOSTNAME

log "Setting basic security settings"
system_security_fail2ban
system_security_ufw_install
system_security_ufw_configure_basic
system_sshd_pubkeyauthentication Yes
/etc/init.d/ssh restart

log "Installing Ruby $RUBY_RELEASE"
export RUBY_VERSION="ruby-$RUBY_RELEASE"
download_and_extract_ruby
compile_and_install_ruby

log "Installing nginx $NGINX_RELEASE"
download_and_extract_nginx
compile_and_install_nginx

log "Installing redis $REDIS_RELEASE"
download_and_extract_redis
compile_and_install_redis

log "Updating Ruby gems"
set_production_gemrc
gem update --remote --system

log "Creating deployment user $DEPLOY_USER"
create_deployment_user

log "Creating deployment demo app"
create_deployment_demo

log "Installing Phusion Passenger and Nginx"
gem install passenger
passenger-install-nginx-module --auto --prefix=$NGINX_PREFIX --nginx-source-dir=/usr/local/src/nginx-$NGINX_RELEASE --extra-configure-flags="$NGINX_OPTIONS"
configure_passenger_nginx

log "Setting up Nginx to start on boot and rotate logs"
set_nginx_boot_up

log "Setting up default host"
configure_default_host

log "Install Bundler"
gem install bundler


# Install PostgreSQL and setup database
if [ "$SETUP_POSTGRESQL" == "Yes" ]; then
    source <ssinclude StackScriptID="125"> # lib-postgresql
    postgresql_install
    system_record_etc_dir_changes "Installed PostgreSQL"
    postgresql_create_user "$POSTGRESQL_USER" "$POSTGRESQL_PASSWORD"
    postgresql_create_database "$POSTGRESQL_DATABASE" "$POSTGRESQL_USER"
    system_record_etc_dir_changes "Configured PostgreSQL"
fi

# Install MongoDB
if [ "$SETUP_MONGODB" == "Yes" ]; then
    source <ssinclude StackScriptID="128"> # lib-mongodb
    mongodb_install
    system_record_etc_dir_changes "Installed MongoDB"
fi

restart_services
restart_initd_services

log "Restarting Services"
restartServices
  

cat >> ~/setup_message <<EOD
To access your server ssh to $USER_NAME@$RDNS

Thanks for using this StackScript. Follow http://github.com/nigma/StackScripts for updates.

Need help with developing web apps? Email me at en@ig.ma.

Best,
Filip
--
http://en.ig.ma/
EOD

mail -s "Your Linode VPS is ready" "$NOTIFY_EMAIL" < ~/setup_message
