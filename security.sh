#!/bin/bash
#
# Security StackScript
# By Donald von Stufft <donald.stufft@gmail.com>
#
# <udf name="user_name" label="Unprivileged User Account" />
# <udf name="user_password" label="Unprivileged User Password" />
# <udf name="user_sshkey" label="Public Key for User" default="" />
#
# <udf name="sshd_port" label="SSH Port" default="22" />
# <udf name="sshd_protocol" label="SSH Protocol" oneOf="1,2,1 and 2" default="2" />
# <udf name="sshd_permitroot" label="SSH Permit Root Login" oneof="No,Yes" default="No" />
# <udf name="sshd_passwordauth" label="SSH Password Authentication" oneOf="No,Yes" default="No" />
# <udf name="sshd_group" label="SSH Allowed Groups" default="sshusers" example="List of groups seperated by spaces" />
#
# <udf name="sudo_usergroup" label="Usergroup to use for Admin Accounts" default="wheel" />
# <udf name="sudo_passwordless" label="Passwordless Sudo" oneof="Require Password,Do Not Require Password", default="Require Password" />

source <ssinclude StackScriptID="1">

# Update the System
system_update

# Install and Configure Sudo
aptitude -y install sudo

cp /etc/sudoers /etc/sudoers.tmp
chmod 0640 /etc/sudoers.tmp
test "${SUDO_PASSWORDLESS}" == "Do Not Require Password" && (echo "%`echo ${SUDO_USERGROUP} | tr '[:upper:]' '[:lower:]'` ALL = NOPASSWD: ALL" >> /etc/sudoers.tmp)
test "${SUDO_PASSWORDLESS}" == "Require Password" && (echo "%`echo ${SUDO_USERGROUP} | tr '[:upper:]' '[:lower:]'` ALL = (ALL) ALL" >> /etc/sudoers.tmp)
chmod 0440 /etc/sudoers.tmp
mv /etc/sudoers.tmp /etc/sudoers

# Configure SSHD
echo "Port ${SSHD_PORT}" > /etc/ssh/sshd_config.tmp
echo "Protocol ${SSHD_PROTOCOL}" >> /etc/ssh/sshd_config.tmp

sed -n 's/\(HostKey .*\)/\1/p' < /etc/ssh/sshd_config >> /etc/ssh/sshd_config.tmp

sed -n 's/\(UsePrivilegeSeparation .*\)/\1/p' < /etc/ssh/sshd_config >> /etc/ssh/sshd_config.tmp

sed -n 's/\(KeyRegenerationInterval .*\)/\1/p' < /etc/ssh/sshd_config >> /etc/ssh/sshd_config.tmp
sed -n 's/\(ServerKeyBits .*\)/\1/p' < /etc/ssh/sshd_config >> /etc/ssh/sshd_config.tmp

sed -n 's/\(SyslogFacility .*\)/\1/p' < /etc/ssh/sshd_config >> /etc/ssh/sshd_config.tmp
sed -n 's/\(LogLevel .*\)/\1/p' < /etc/ssh/sshd_config >> /etc/ssh/sshd_config.tmp

sed -n 's/\(LoginGraceTime .*\)/\1/p' < /etc/ssh/sshd_config >> /etc/ssh/sshd_config.tmp
echo "PermitRootLogin `echo ${SSHD_PERMITROOT} | tr '[:upper:]' '[:lower:]'`" >> /etc/ssh/sshd_config.tmp
sed -n 's/\(StrictModes .*\)/\1/p' < /etc/ssh/sshd_config >> /etc/ssh/sshd_config.tmp

sed -n 's/\(RSAAuthentication .*\)/\1/p' < /etc/ssh/sshd_config >> /etc/ssh/sshd_config.tmp
sed -n 's/\(PubkeyAuthentication .*\)/\1/p' < /etc/ssh/sshd_config >> /etc/ssh/sshd_config.tmp

sed -n 's/\(IgnoreRhosts .*\)/\1/p' < /etc/ssh/sshd_config >> /etc/ssh/sshd_config.tmp
sed -n 's/\(RhostsRSAAuthentication .*\)/\1/p' < /etc/ssh/sshd_config >> /etc/ssh/sshd_config.tmp
sed -n 's/\(HostbasedAuthentication .*\)/\1/p' < /etc/ssh/sshd_config >> /etc/ssh/sshd_config.tmp

sed -n 's/\(PermitEmptyPasswords .*\)/\1/p' < /etc/ssh/sshd_config >> /etc/ssh/sshd_config.tmp

sed -n 's/\(ChallengeResponseAuthentication .*\)/\1/p' < /etc/ssh/sshd_config >> /etc/ssh/sshd_config.tmp

echo "PasswordAuthentication `echo ${SSHD_PASSWORDAUTH} | tr '[:upper:]' '[:lower:]'`" >> /etc/ssh/sshd_config.tmp

sed -n 's/\(X11Forwarding .*\)/\1/p' < /etc/ssh/sshd_config >> /etc/ssh/sshd_config.tmp
sed -n 's/\(X11DisplayOffset .*\)/\1/p' < /etc/ssh/sshd_config >> /etc/ssh/sshd_config.tmp
sed -n 's/\(PrintMotd .*\)/\1/p' < /etc/ssh/sshd_config >> /etc/ssh/sshd_config.tmp
sed -n 's/\(PrintLastLog .*\)/\1/p' < /etc/ssh/sshd_config >> /etc/ssh/sshd_config.tmp
sed -n 's/\(TCPKeepAlive .*\)/\1/p' < /etc/ssh/sshd_config >> /etc/ssh/sshd_config.tmp

sed -n 's/\(MaxStartups .*\)/\1/p' < /etc/ssh/sshd_config >> /etc/ssh/sshd_config.tmp

sed -n 's/\(AcceptEnv .*\)/\1/p' < /etc/ssh/sshd_config >> /etc/ssh/sshd_config.tmp

sed -n 's/\(Subsystem .*\)/\1/p' < /etc/ssh/sshd_config >> /etc/ssh/sshd_config.tmp

sed -n 's/\(UsePAM .*\)/\1/p' < /etc/ssh/sshd_config >> /etc/ssh/sshd_config.tmp

echo "AllowGroups `echo ${SSHD_GROUP} | tr '[:upper:]' '[:lower:]'`" >> /etc/ssh/sshd_config.tmp

chmod 0600 /etc/ssh/sshd_config.tmp
mv /etc/ssh/sshd_config.tmp /etc/ssh/sshd_config
touch /tmp/restart-ssh

# Create Groups
groupadd ${SSHD_GROUP}
groupadd ${SUDO_USERGROUP}

# Create User & Add SSH Key
USER_NAME_LOWER=`echo ${USER_NAME} | tr '[:upper:]' '[:lower:]'`

useradd -m -s /bin/bash -G ${SSHD_GROUP},${SUDO_USERGROUP} ${USER_NAME_LOWER}
echo "${USER_NAME_LOWER}:${USER_PASSWORD}" | chpasswd

USER_HOME=`sed -n "s/${USER_NAME_LOWER}:x:[0-9]*:[0-9]*:[^:]*:\(.*\):.*/\1/p" < /etc/passwd`

sudo -u ${USER_NAME_LOWER} mkdir ${USER_HOME}/.ssh
echo "${USER_SSHKEY}" >> $USER_HOME/.ssh/authorized_keys
chmod 0600 $USER_HOME/.ssh/authorized_keys
chown ${USER_NAME_LOWER}:${USER_NAME_LOWER} $USER_HOME/.ssh/authorized_keys

# Setup Hostname
get_rdns_primary_ip > /etc/hostname
/etc/init.d/hostname.sh start

# Restart Services
restartServices
