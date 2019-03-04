# Backup and versioning of services configuration files on Development/Testing/Acceptance/Production servers.
#
# Installation script for the "main" server with GitLab. (Change the FQDN variable to the Full Qualifyied Domain Name URL or - if you don't have DNS a name - the URL as http://IP.ADDRESS)
FQDN="http://configkeeper.dev.ufrgs.br"
# Add the "git" user to the group that can access the server through ssh.
# E.g.: If in your sshd_config only members of "ssh-users" group can connnect via ssh, run:
usermod -aG ssh-users git
# Root keypair 
ssh-keygen -o -t rsa -b 4096
# Update/Dist-Upgrade
apt update
apt dist-upgrade -y
# Dependencies installation
apt install rsync gzip openssh-server postfix diffutils curl gcc make pkg-config build-essential git cmake ca-certificates automake autoconf autogen -y
# Last official installation script from GitLab
curl https://packages.gitlab.com/install/repositories/gitlab/gitlab-ee/script.deb.sh | sudo bash
# Proper installation 
sudo EXTERNAL_URL="${FQDN}" apt-get install gitlab-ee
echo "All done!"
echo "Reboot the server..."
exit 0
