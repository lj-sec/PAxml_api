#!/bin/bash

# Author: Logan Jackson
# Stolen from: Raven Dean
# xml_api2.sh
#
# Description: A bash script that configures the firewall automatically using Palo Alto's XML API
# UPDATE VARIABLES BELOW

# Created 11/14/2024
# Usage: <./xml_api2.sh>

# Edit variables as required:
host="172.20.242.150" # CHANGEME! - Palo Alto host IP addr
management_subnet="172.20.242.0/24" #CHANGEME! - Palo Alto management subnet
team_number=0 #CHANGEME! - CCDC Team Number
user="admin" # - Admin username
password="1234" #CHANGEME! - Admin default/current password

# Do not touch these variables unless you know what you are doing:
third_octet=$((20+$team_number))
pan_device="localhost.localdomain"
pan_vsys="vsys1"
device_xpath="/config/devices/entry[@name='$pan_device']"
vsys_xpath="/vsys/entry[@name='$pan_vsys']"
script_name="xml_api.sh"
usage="./$script_name"
api="https://$host/api/" # api baseurl
job_status_poll_speed=3 # Speed (in seconds) that the script checks for the commit status

# Import environment variables (ekurc)
. ../../config_files/ekurc

## CONFIG CHECKS

# From ekurc, check for repository security (perms set correctly to 0750)
check_security

# Superuser requirement.
if [ "$EUID" -ne 0 ]
then error "This script must be ran as root!"
    exit 1
fi

# Check for the correct number of arguments
if [ "$#" -gt 0 ]
then error $usage
    exit 1
fi

# Check for default team number
if [ "$team_number" -eq 0 ]
then error "Team number cannot be set to default!"
    exit 1
fi

# Check for default password
if [ "$password" == "1234" ]
then error "Password cannot be set to default!"
    exit 1
fi

# Display current vars to the user
warn "Ensure all variables are set correctly!\nHost: $host\nManagement Subnet: $management_subnet\nUser: $user\nPassword: $password\nTeam Number: $team_number\nThird Octet: $third_octet\nDevice: $pan_device\nVirtual System: $pan_vsys\n\nProceed running script? (continue with any key or 'n' to quit)\n"
read -n 1 -s yn

if [ "$yn" == "n" ]
then
    error "User quit!"
    exit 1
else
    info "Continuing!"
fi

# Prompt user input to change PA admin password
while : ; do
    read -p "Enter new password to change Palo Alto Default (ensure 8 chars long, 1 uppercase, 1 lowercase, and 1 number/special char): " new_password
    read -p "Confirm new password: " confirm_password
    [[ $new_password != $confirm_password ]] || break
    echo "Passwords did not match."
done

## END CONFIG CHECKS

# Updating and upgrading apt
apt update -y && apt upgrade -y

# Install dependencies
apt install -y libxml-xpath-perl libxml2-utils jq findutils curl

# Action function for calling the Palo Alto API and recieving response codes
action() { # action <action> <description> <xpath>/<cmd> <element>
    api_call="action_$1($2)"
    if [ "$1" == "set" ] || [ "$1" == "edit" ]
    then
        url_encoded_element="$(echo $4 | jq -sRr @uri)"
        response=$(curl --location --globoff --insecure --request POST --header "$header" "$api?type=config&action=$1&xpath=$3&element=$url_encoded_element")
    elif [ "$1" == "op" ]
    then
        url_encoded_cmd="$(echo $3 | jq -sRr @uri)"
        response=$(curl --location --globoff --insecure --request POST --header "$header" "https://$host/api/?type=op&cmd=$url_encoded_cmd")
    else
        response=$(curl --location --globoff --insecure --request POST --header "$header" "$api?type=config&action=delete&xpath=$3")
    fi

    response_code=$(echo $response | xmllint --xpath 'string(/response/@code)' -)
    response_status=$(echo $response | xmllint --xpath 'string(/response/@status)' -)
    message=$(echo $response | xmllint --xpath 'string(/response/msg)' -)
    
    if [ ! -z "$response_code" ] # If the response contains a response code
    then
        if [ "$response_code" == "20" ] # Success
        then
            success $api_call
        elif [ "$response_code" == "7" ] # Object not found
        then
            warn "$api_call failed with reason: $message"
        else # Some other error
            error "$api_call failed with reason: $message"
        fi
    else # If the response does not contain a response code
        if [ "$response_status" == "success" ]
        then
            success $api_call
        else
            error "$api_call failed with reason: $message"
        fi
    fi
}

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

waits() { # waits <pid_array> <command>
    for pid in $1
    do
        while [ -e "/proc/$pid" ]
        do
            sleep 0.1
        done
    done
    shift
    "$@" &
}

# Grab API Key
api_key=$(curl --insecure --silent --request GET "$api?type=keygen&user=$user&password=$password" | xpath -q -e '/response/result/key/text()')

hash=$(curl --insecure --silent --request GET "$api?type=op&cmd=<request><password-hash><password>$new_password</password></password-hash></request>&key=$api_key")

action "set" "Change Admin Password" "/config/mgt-config/users/entry[@name='admin']/phash" "<phash>$($hash)</phash>"

success "Script Complete!"

exit 0