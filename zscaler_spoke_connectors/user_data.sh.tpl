# /zscaler_spoke_connectors/user_data.sh.tpl
#!/bin/bash

# Stop the App Connector service which may have auto-started at boot time
systemctl stop zpa-connector

# Create the provisioning key file from the unique key provided by Terraform
# The key is enclosed in double quotes to ensure it's handled as a single string.
echo "${provisioning_key}" > /opt/zscaler/var/provision_key
chmod 644 /opt/zscaler/var/provision_key

# Run a yum update to apply the latest patches
yum update -y

# Start the App Connector service to enroll it in the ZPA cloud
systemctl start zpa-connector

# Wait for the App Connector to download the latest build after enrollment
sleep 60

# Restart the service to ensure it's running the latest downloaded build
systemctl stop zpa-connector
systemctl start zpa-connector