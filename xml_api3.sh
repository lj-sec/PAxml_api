#!/bin/bash

# Updating and upgrading apt
apt update -y && apt upgrade -y

# Install dependencies
apt install -y libxml-xpath-perl libxml2-utils jq findutils curl
snap install yq

# Required vars
script_name="xml_api.sh"
usage="./$script_name"
repo_root=$(git rev-parse --show-toplevel)
config_file="$repo_root/config_files/firewall_config.yaml"

host=$(yq eval '.firewall.host' "$config_file")
port=$(yq eval '.firewall.api_port' "$config_file")
username=$(yq eval '.firewall.username' "$config_file")
password=$(yq eval '.firewall.password' "$config_file")
use_https=$(yq eval '.security.use_https' "$config_file")
log_file=$(yq eval '.logs.file' "$config_file")

# Use these variables in script
if [ "$use_https" = "true" ]; then
  url="https://$host:$port/api/"
else
  url="http://$host:$port/api/"
fi

echo "Connecting to firewall at $url..."

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

    # Example: Sending the XML via curl (replace <api_url> with your endpoint)
    curl -k -X POST "$url" \
      -d "xpath=$xpath" \
      -d "element=$xml_payload" \
      -d "type=config" \
      -u "$username:$password"
done