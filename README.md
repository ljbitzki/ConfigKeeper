# ConfigKeeper :floppy_disk: :watch:
### A very Lightweight Real-time backup and versioning of services configuration files on Development/Testing/Acceptance/Production servers.

That's a little and simple piece of software created to help SysAdmins in scenarios where a server have many "roots" and *shit can happen*.

With a classic architecture of clients talking to a centralized server, ConfigKeeper can keep track of any slightly change in sensible configuration files of a service, with a very efficient use of resources.

Imagine an organization with a production application server, where eventually an Administrator (in a team of administrators) enters to adjust some conf files, update de OS, this kind of stuff.

But this particular Admin is lazy/sloppy (and don't have the entire technical knowledge about the running services) and he mess with something, but don't know where and with what and how and (...) the service is out. Stopped.

What the hell happens? How can we get back if 5 minutes ago all are running well...? Well, if your organization have the classical backup strategy, one time a day (by night, e.g.), good1 luck digging log files...

Using a GitLab server and simple shell scripts (controlling inotify), if a semicolon was removed by accident and that generate a crazy behavior, will be very easy to identify the last change that cause this effect and correct the mistake.

## Requirements (I.e., where that have been tested :laughing:)
Server: Ubuntu 18.04, 4 CPU, 4GB of RAM, 30+ GB of disk
Client: Ubuntu 10, 12, 14, 16 and 18.

### Steps:
#### In the "Server":
*  Install the "server-install.sh" script on the server that will be "The Server", following the in-file instructions;  
  * Access the web interface, change the "root" password there, add and user "configkeeper" and promote his as Administrador;
  * (Every new client, you need to add the root public key of this client as a ssh key in "configkeeper" user profile).
#### In the "Client":
* Install the "client-install.sh", following the in-file instructions;
  * Edit /etc/configkkper/conf.d/apps.conf and change whatever you need (following the in file instructions);
  * When the installation script finishes, ConfigKeeper will be already running and all your changes ate apps.conf will be already been monitored...

### How it works
The GitLab server is just a GitLab server. :grin: All the *stuff* happens at clients. 
At client, there is a file (conf.d/apps.conf) where are declared which service and which folder (recursivelly) should be monitored. In general, all you need to do is modify this file only.
This file is monitored by a script using inotifywait the do all the things needed when a service is add or removed from apps.conf. (all the things needed = create new scripts, one per service monitored, control and commit it to GitLab server)
When a "app" is monitored, a complete matrix of file permissions is created at "/etc/configkeeper/permissions/" because some services are strictly denpendent os file permissions.
There is implemented a simple temporary file treatment. This is simple, but effective.
When you are monitoring a file with __*inotify*__ and open it with e.g.__vim__, make some changes and __:wq!__, this events happens, in this order: (the example file is example.txt)
* CREATE 4913.txt
* CLOSE,WRITE 4913.txt
* DELETE 4913.txt
* CREATE example.txt
* CLOSE,WRITE example.txt
We don't what to save/versionate 4913.txt, so there is a workaround implemented.

Server components:
Gitlab-ee default stock installation

Client components:
Installation:     /etc/configkeeper/
Main script:      /etc/configkeeper/ck.sh
Apps monitor:     /etc/configkeeper/monitors/apps.mon
Monitored apps:   /etc/configkeeper/conf.d/apps.conf
Monitors:         /etc/configkeeper/monitors/${apps}.conf
Permissions:      /etc/configkeeper/permissions/${apps}.perms
Template:         /etc/configkeeper/base/template.app
Lock directory:   /var/lock/configkeeper/
PIDs directory:   /tmp/configkeeper/
Log File:         /var/log/configkeeper.log
Init script:      /etc/init.d/configkeeper
