#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Organization-wide role to assume in sub-accounts
ROLE_NAME="OrganizationAccountAccessRole"

# Function to assume role and retrieve temporary credentials
assume_role() {
    local account_id=$1
    echo "Assuming role in account: $account_id"

    # Assume the specified role in the sub-account
    aws sts assume-role \
        --role-arn "arn:aws:iam::$account_id:role/$ROLE_NAME" \
        --role-session-name "CountEC2Instances" \
        --query "Credentials" \
        --output json
}

# Function to count EC2 instances in a specific region and account
count_instances_in_account() {
    local account_id=$1
    local credentials=$2

    local access_key=$(echo "$credentials" | jq -r '.AccessKeyId')
    local secret_key=$(echo "$credentials" | jq -r '.SecretAccessKey')
    local session_token=$(echo "$credentials" | jq -r '.SessionToken')

    # Export temporary credentials
    export AWS_ACCESS_KEY_ID="$access_key"
    export AWS_SECRET_ACCESS_KEY="$secret_key"
    export AWS_SESSION_TOKEN="$session_token"

    # Get all regions
    local regions=$(aws ec2 describe-regions --query "Regions[*].RegionName" --output text)

    # Count instances in all regions
    local account_total=0
    for region in $regions; do
        echo "Checking region $region in account $account_id"
        local count=$(aws ec2 describe-instances \
            --region "$region" \
            --query "Reservations[*].Instances[*].InstanceId" \
            --output text | wc -w)
        account_total=$((account_total + count))
    done

    # Return the total count for the account
    echo $account_total
}

# Get the list of all account IDs in the AWS Organization
account_ids=$(aws organizations list-accounts --query "Accounts[*].Id" --output text)

# Initialize total count
grand_total=0

# Loop through each account and count instances
for account_id in $account_ids; do
    credentials=$(assume_role "$account_id")
    account_total=$(count_instances_in_account "$account_id" "$credentials")
    echo "Total EC2 instances in account $account_id: $account_total"
    grand_total=$((grand_total + account_total))
done

# Reset credentials back to the default profile
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN

echo "Grand total EC2 instances across all accounts: $grand_total"