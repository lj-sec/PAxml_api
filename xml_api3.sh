#!/bin/bash

# Author: Logan Jackson
# Original Script: Raven Dean
# xml_api3.sh
#
# Description: A bash script that automatically configures PANOS using its XML API
# UPDATE VARIABLES BELOW

# Created 11/26/2024
# Usage: <./xml_api3.sh>

# Import env vairables
. $repo_root/config_files/ekurc || { echo "Error: Failed to import ekurc files"; exit 1; }

# Updating and upgrading apt
apt update -y && apt upgrade -y || { warn "Failed to update/upgrade"; }

# Install dependencies
apt install -y libxml-xpath-perl libxml2-utils jq findutils curl || { error "Failed to install dependencies"; exit 1; }
snap install yq || { error "Failed to install yq"; exit 1; } 

# Required vars
script_name="xml_api3.sh"
usage="./$script_name"
repo_root=$(git rev-parse --show-toplevel) # Grab the root of the git repository
config_file="$repo_root/config_files/firewall_config.yaml" || { error "Failed to fetch firewall_config.yaml"; exit 1; }
job_status_poll_speed=3 # Speed (in seconds) that the script checks for the commit status

# Fetching variables from config file
host=$(yq eval '.firewall.host' "$config_file") || { error "Host not found in firewall_config.yaml"; }
port=$(yq eval '.firewall.api_port' "$config_file") || { error "API Port not found in firewall_config.yaml"; }
username=$(yq eval '.firewall.username' "$config_file") || { error "Username not found in firewall_config.yaml"; }
password=$(yq eval '.firewall.password' "$config_file") || { error "Password not found in firewall_config.yaml"; }
use_https=$(yq eval '.security.use_https' "$config_file") || { error "Use HTTPS not found in firewall_config.yaml"; }
log_file=$(yq eval '.logs.file' "$config_file") || { error "Log file not found in firewall_config.yaml"; }

# Grab API Key
api_key=$(curl --insecure --silent --request GET "$api?type=keygen&user=$user&password=$password" | xpath -q -e '/response/result/key/text()')
header="X-PAN-KEY: $api_key"

# Define xpaths for quick access
pan_vsys="vsys1"
pan_device="localhost.localdomain"
device_xpath="/config/devices/entry[@name='$pan_device']"
vsys_xpath="/vsys/entry[@name='$pan_vsys']"
full_xpath="$device_xpath$vsys_xpath"
mgmt_profile_xpath="$device_xpath/network/profiles/interface-management-profile/entry"
eth_interface_xpath="$device_xpath/network/interface/ethernet/entry"
app_group_xpath="$full_xpath/application-group/entry"
addr_object_xpath="$full_xpath/address/entry"
addr_group_xpath="$full_xpath/address-group/entry"
srvc_object_xpath="$full_xpath/service/entry"
srvc_group_xpath="$full_xpath/service-group/entry"
log_profiles_xpath="$full_xpath/log-settings/profiles/entry"
srvc_route_xpath="$device_xpath/deviceconfig/system/route"
sec_policy_xpath="$full_xpath/rulebase/security/rules/entry"
dsec_policy_xpath="$full_xpath/rulebase/default-security-rules/rules/entry"
tag_object_xpath="$full_xpath/tag/entry"

# Determine if we are using https
if [ "$use_https" = "true" ]; then
  url="https://$host:$port/api/"
else
  url="http://$host:$port/api/"
fi

info "Firewall URL: $url"

check_job_status() {
    # Check the commit status for the job in $1 and echo the result.
    response=$(curl --location --globoff --insecure --silent --request GET --header "$header" "$api?type=op&cmd=<show><jobs><id>$1</id></jobs></show>")
    echo $(echo $response | xpath -e '/response/result/job/status/text()' 2>/dev/null)
}

commit() { #commit <description>
    info "Starting Job: $1"
    job_id=$(curl --location --globoff --insecure --silent --request POST --header "$header" "$api?type=commit&cmd=<commit></commit>" | xpath -q -e '/response/result/job/text()')

    if [ ! -z "$job_id" ]
    then
        status=$(check_job_status $job_id)
        while [ "$status" != "FIN" ]
        do
            info "Waiting for job $job_id ($1) to complete..."
            sleep $job_status_poll_speed
            status=$(check_job_status $job_id)
        done
        success "Job $job_id: '$1' complete!"
    else
        warn "Job $job_id: Nothing to do!"
    fi
}

# Perform API actions
actions_count=$(yq eval '.api.actions | length' "$config_file")

for i in $(seq 0 $((actions_count - 1))); do

    # Extract action payload
    action_name=$(yq eval ".api.actions[$i].name" "$config_file")
    xpath=$(yq eval ".api.actions[$i].payload.xpath" "$config_file")

    # Zones
    to_zones=$(yq eval ".api.actions[$i].payload.to_zone | join(\" \")" "$config_file")
    from_zones=$(yq eval ".api.actions[$i].payload.from_zone | join(\" \")" "$config_file")

    # Other payload details
    source=$(yq eval ".api.actions[$i].payload.source | join(\" \")" "$config_file")
    destination=$(yq eval ".api.actions[$i].payload.destination | join(\" \")" "$config_file")
    source_user=$(yq eval ".api.actions[$i].payload.source_user | join(\" \")" "$config_file")
    category=$(yq eval ".api.actions[$i].payload.category | join(\" \")" "$config_file")
    application=$(yq eval ".api.actions[$i].payload.application | join(\" \")" "$config_file")
    service=$(yq eval ".api.actions[$i].payload.service | join(\" \")" "$config_file")
    source_hip=$(yq eval ".api.actions[$i].payload.source_hip | join(\" \")" "$config_file")
    destination_hip=$(yq eval ".api.actions[$i].payload.destination_hip | join(\" \")" "$config_file")
    action=$(yq eval ".api.actions[$i].payload.action" "$config_file")
    icmp_unreachable=$(yq eval ".api.actions[$i].payload.icmp_unreachable" "$config_file")
    description=$(yq eval ".api.actions[$i].payload.description" "$config_file")
    log_setting=$(yq eval ".api.actions[$i].payload.log_setting" "$config_file")

    # Default to 'any' if missing
    source=${source:-any}
    destination=${destination:-any}

    # Generate XML
    xml_payload="<to><member>${to_zones// /</member><member>}</member></to>"
    xml_payload+="<from><member>${from_zones// /</member><member>}</member></from>"
    xml_payload+="<source><member>${source// /</member><member>}</member></source>"
    xml_payload+="<destination><member>${destination// /</member><member>}</member></destination>"
    xml_payload+="<source-user><member>${source_user// /</member><member>}</member></source-user>"
    xml_payload+="<category><member>${category// /</member><member>}</member></category>"
    xml_payload+="<application><member>${application// /</member><member>}</member></application>"
    xml_payload+="<service><member>${service// /</member><member>}</member></service>"
    xml_payload+="<source-hip><member>${source_hip// /</member><member>}</member></source-hip>"
    xml_payload+="<destination-hip><member>${destination_hip// /</member><member>}</member></destination-hip>"
    xml_payload+="<action>${action}</action>"
    xml_payload+="<icmp-unreachable>${icmp_unreachable}</icmp-unreachable>"
    xml_payload+="<description>${description}</description>"
    xml_payload+="<log-setting>${log_setting}</log-setting>"

    # Print or send XML
    echo "Generated XML for action: $action_name"
    echo "$xml_payload"

done

commit "Final commit"

success "Script complete!"