#!/bin/bash
#
# Installs a complete web environment with Apache, Python, Django and PostgreSQL.
#
# Copyright (c) 2010 Filip Wasilewski <en@ig.ma>.
#
# My ref: http://www.linode.com/?r=aadfce9845055011e00f0c6c9a5c01158c452deb

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
# <UDF name="setup_monit" label="Install Monit system monitoring?" oneof="Yes,No" default="Yes" />

# <UDF name="setup_deploy_user" label="Create a deploy user?" oneof="Yes,No" default="Yes" />

# TODO
# god
# redis
# elasticsearch

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

# Install and configure apache and mod_wsgi
if [ "$SETUP_APACHE" == "Yes" ]; then
    source <ssinclude StackScriptID="122"> # lib-apache
    apache_worker_install
    system_record_etc_dir_changes "Installed apache" # SS124
    apache_mod_wsgi_install
    system_record_etc_dir_changes "Installed mod-wsgi" # SS124
    apache_cleanup
    system_record_etc_dir_changes "Cleaned up apache config" # SS124
fi

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

# Setup and configure sample django project
RDNS=$(get_rdns_primary_ip)

if [ -n "$SYS_PRIVATE_IP" ]; then
    system_configure_private_network "$SYS_PRIVATE_IP"
    system_record_etc_dir_changes "Configured private network"
fi

restart_services
restart_initd_services

# Send info message
cat > ~/setup_message <<EOD
Hi,

Your Linode VPS configuration is completed.

EOD


if [ "$SETUP_DEPLOY_USER" == "Yes" ]; then
    # Add deploy user
    echo "deploy:deploy:1000:1000::/home/deploy:/bin/bash" | newusers
    cp -a /etc/skel/.[a-z]* /home/deploy/
    chown -R deploy /home/deploy
    # Add to sudoers(?)
    echo "deploy    ALL=(ALL) ALL" >> /etc/sudoers
fi

# Installing Ruby
  export RUBY_VERSION="ruby-2.0.0p247"
  log "Installing Ruby $RUBY_VERSION"

  log "Downloading: (from calling wget ftp://ftp.ruby-lang.org/pub/ruby/2.0/$RUBY_VERSION.tar.gz)" 
  
  log `wget ftp://ftp.ruby-lang.org/pub/ruby/2.0/$RUBY_VERSION.tar.gz`

  log "tar output:"
  log `tar xzf $RUBY_VERSION.tar.gz`
  rm "$RUBY_VERSION.tar.gz"
  cd $RUBY_VERSION

  log "current directory: `pwd`"
  log ""
  log "Ruby Configuration output: (from calling ./configure)" 
  log `./configure` 

  log ""
  log "Ruby make output: (from calling make)"
  log `make`

  log ""
  log "Ruby make install output: (from calling make install)"
  log `make install` 
  cd ..
  rm -rf $RUBY_VERSION
  log "Ruby installed!"

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
