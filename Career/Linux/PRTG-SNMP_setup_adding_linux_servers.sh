# PRTG SNMP Setup (Adding Linux Servers)

# ----------------------------------------------------------------------
# The following steps are for installing and enabling SNMP for PRTG sensors.
# All instructional text is commented out for clarity.
# ----------------------------------------------------------------------

#: <<INSTRUCTIONS
# Simple Network Management Protocol (SNMP) allows your target Linux server to send crucial information to PRTG, such as CPU and memory usage data, among other metrics.

# Instructions

# 1. Log into PRTG, select Devices from the top menu and select appropriate Device Group.
# 2. SNMP credential inheritance will be sourced from the Linux Environment group and will authenticate using the credentials that we will configure on the server to be monitored in the subsequent steps.
# 3. Determine where your server is based, select the relevant group, then select Add Device. Enter Device Name, IPv4 Address or DNS address, and Device Icon.
# 4. Choose Auto-discovery Level: Auto-discovery with specific device templates.
# 5. Template “Linux Basic (Mem, CPU, PING)” is a good starting point.
# 6. Disk monitoring should be added manually to avoid unnecessary partitions being added.
# 7. Once added, pause the device until the next few steps are completed to prevent false alerting.
# 8. SSH into the server to be monitored and, using sudo privileges, execute the relevant code based on the server's location.
#INSTRUCTIONS

# Example SNMP Setup Commands (replace values as appropriate):

yum install net-snmp -y

systemctl enable snmpd

systemctl stop snmpd

# Create SNMP v3 user (replace <username>, <authpass>, <privpass>)
net-snmp-create-v3-user -ro -A <authpass> -a SHA -X <privpass> -x AES <username>

systemctl start snmpd

# Add firewall rule for SNMP (replace <ip-address>)
firewall-cmd --permanent --zone=public \
--add-rich-rule='rule family="ipv4" source address="<ip-address>/32" \
port protocol="udp" port="161" accept'

systemctl restart firewalld

# If firewalld is enabled, verify rule
firewall-cmd --list-all-zones

# Test SNMP locally (replace <username>, <authpass>, <privpass>)
snmpwalk -v 3 -l authPriv -u <username> -a SHA -x AES -A <authpass> -X <privpass> 127.0.0.1 .1 | head

# Return to PRTG, configure the sensors, and resume them from the paused state. The sensors should start providing statistics within a few minutes.
# The server is now configured to be monitored via SNMP in PRTG.
# Consider setting appropriate priorities and alerting.

# If adding Disk Space monitoring use the following thresholds:
# Lower Warning Limit ( % ) = 15
# Lower Error Limit ( % ) = 5