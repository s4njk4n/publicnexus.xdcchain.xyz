# publicnexus.xdcchain.xyz

To solve public/community RPC availability issues we've built a type of **"Layer 2 RPC Stable Access Point"** with integrated health-checks.

Publicnexus is a load-balancer with all known public RPCs on XDC network set as its origin/backend servers.

It checks each RPC's block height in parallel once per minute. If no response, or wrong response, or if the block height is greater than 4 blocks behind highest-block-height result from the cycle, then that RPC is removed from the list of origin/backend servers and no further RPC traffic will be directed there. (So max exposure time to any problematic RPC should be about 1 minute before Publicnexus fixes itself).

Conversely, if an RPC improves to meet criteria again, then it gets re-added to the list of origin/backend servers and will once again commence receiving RPC traffic.

We've added in a throttling mechanism for each IP that accesses it so commercial projects that will need higher transaction throughput won't be able to use it (as they should probably run their own private RPC). That way it is specifically for public/community use as the allowed-rate-per-IP will be adequate for them.

The various rate-limit / throttling settings will also prevent its use for DOS and other malicious activity.

Project is in alpha. Current RPC settings if wanting to test:

- **Network Name:** xdcchain.xyz PublicNexus
- **RPC URL:** https://publicnexus.xdcchain.xyz
- **Chain ID:** 50
- **Currency Symbol:** XDC
- **Explorer:** https://explorer.xinfin.network

Because Publicnexus uses all known public RPCs, it means this access point only supports the xdc prefix at the moment. A secondary access point can be added at a later point specifically for supporting the 0x-prefix if needed)

---

## Server setup

Server running Ubuntu 22.04

### Deployed on server:
- apache2 (_modules enabled: proxy, proxy_http, proxy_balancer, lbmethod_byrequests, ssl, ratelimit_)
- certbot (_for LetsEncrypt CA cert/key_)
- python3
- ufw
- fail2ban

### apache2
- Should already be deployed on your server
- Enable modules with:
```
a2enmod proxy
a2enmod proxy_http
a2enmod proxy_balancer
a2enmod lbmethod_byrequests
a2enmod ssl
a2enmod ratelimit
```
### certbot and python3
- Install, get certificate, and set up apache SSL configs with:
```
apt install certbot python3 python3-certbot-apache -y
certbot --apache
```
### ufw
- Install and setup firewall:
```
apt install ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow 443
ufw allow 22
ufw enable
reboot
```
Port 22 is default SSH port. You can see instructions on how to change it by modifying /etc/ssh/sshd_config as described in [this article](https://www.xdc.dev/s4njk4n/securing-your-xdc-masternode-running-on-ubuntu-2004lts-57k8).
Port 443 for SSL
### fail2ban
- Follow instructions in [this article](https://www.xdc.dev/s4njk4n/securing-your-xdc-masternode-running-on-ubuntu-2004lts-57k8).
### Further security
Also recommend:
- Setting up ssh-key authentication to access the server
- Consider disabling passwords or if keeping passwords then consider making them VERY long and complex consisting of upper/lower case letters, numbers + symbols. Disabling password login to root account can also be helpful as it is an easy to guess username on your server so it is easier to bruteforce.
---
### Apache config
This is located in:
- /etc/apache2/sites-enabled/000-default.conf <-- Certbot will write http to https redirects in here
- /etc/apache2/sites-enabled/000-default-le-ssl.conf   <-- Certbot will add your SSL setup in here
You will need to modify these files to replace with your own domain name of course if you are establishing your own system. Also need to add load balancer configuration as shown.
### Scripts/Files
Our scripts are located at ~/RPC_Check/
- **rpc_check.sh** - This performs all the functions required to check RPCs, interpret responses, modify the load-balancer's origin servers, and (gracefully) apply the new origin server addresses. _Note: curl is set to allow max 10sec for an RPC to respond. No response in this time = broken RPC. Also remember to set your variables at the top of this file with absolute path locations etc. as we are going to run this script as a cron job. Also at present the permitted lag in block height allowed by the script for an RPC to retain its "Active" status we have arbitrarily set to 4 blocks - which would be about 8 seconds based on an average block time of 2sec on the network. After further testing a more appropriate block-height lag tolerance may be determined._
- **rpc_check-pause.sh** - In the event that you need to modify files manually and don't want rpc_check.sh running, this script will create a pause flag that inhibits the actions of rpc_check.sh.
- **rpc_check-restart.sh** - This script deletes the pause flag so rpc_check.sh will then kick off where it left off.
- **rpc_pool.csv** - This is a csv file containing 3 fields about each RPC it can potentially send traffic to: The RPC address/URL, that RPC's health-status, that RPC's last recorded block height
- **events.log** - Our log file. By default, rpc_check.sh will limit this file to the last 5000 lines of log history. You can allow a longer history by just modifying rpc_check.sh.

rpc_check.sh is set to run minutely as a cron job:
```
crontab -e
```
Then in the crontab file:
```
* * * * * /bin/bash /root/RPC_Check/rpc_check.sh >/dev/null 2>&1
```
---
### To do
- Further determine the optimal maximum permissible block height lag. This will become apparent with further usage.
- Add more public RPCs. The more RPCs used in rotation, the less percentage effect a failing RPC will have on success/failure of overall transaction burden. (Transactions are allocated on a round-robin approach between Active RPCs)
---
