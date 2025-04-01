#!/bin/bash

# Script to fetch Azure inventory for Prisma Cloud sizing.
# Requirements: az cli

# This script can be run from Azure Cloud Shell.
# Run ./pcs_azure_sizing.sh -h for help on how to run the script.
# Or just read the text in showHelp below.

# Function to handle errors
function check_error {
    local exit_code=$1
    local message=$2
    if [ $exit_code -ne 0 ]; then
        echo "Error: $message (Exit Code: $exit_code)"
        # Add any Azure specific cleanup here if needed in the future
        exit $exit_code
    fi
}

# Ensure Azure CLI is logged in
az account show > /dev/null 2>&1
check_error $? "Azure CLI not logged in. Please run 'az login'."

echo "Counting VM instances across all subscriptions in the tenant..."

# Initialize a total count
total_vm_count=0
total_node_count=0

# Get a list of all subscription IDs in the tenant
subscriptions=$(az account list --query "[].id" -o tsv)
check_error $? "Failed to list Azure subscriptions."

if [ -z "$subscriptions" ]; then
    echo "No subscriptions found for the current logged-in user."
    exit 0
fi

# Loop through each subscription
for subscription_id in $subscriptions; do
    echo "Switching to subscription: $subscription_id"
    # Suppress output from az account set, check error code instead
    az account set --subscription "$subscription_id" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "  Warning: Failed to switch to subscription '$subscription_id'. Skipping this subscription."
        continue # Skip to the next subscription
    fi

    # Count VMs in the current subscription
    vm_count=$(az vm list --query "length(@)" -o tsv)
    if [ $? -ne 0 ]; then
        echo "  Warning: Failed to list VMs in subscription '$subscription_id'. Assuming 0 VMs."
        vm_count=0
    fi
    echo "VM instances in subscription '$subscription_id': $vm_count"

    # Add to the total count
    total_vm_count=$((total_vm_count + vm_count))

    # Get the list of all AKS clusters in the subscription
    clusters=$(az aks list --query "[].{name:name, resourceGroup:resourceGroup}" -o tsv)

    if [ $? -ne 0 ]; then
        echo "  Warning: Failed to list AKS clusters in subscription '$subscription_id'. Skipping AKS count for this subscription."
        # Skip the AKS part for this subscription
        continue 
    fi

    if [ -z "$clusters" ]; then
        echo "No AKS clusters found in the subscription."
        # No need to exit, just continue to the next subscription or finish if this is the last one
        # The loop will handle continuing to the next subscription if any
    else
        # Loop through each cluster only if clusters were found
        while IFS=$'\t' read -r cluster_name resource_group; do
            echo "Processing cluster: $cluster_name (Resource Group: $resource_group)"

            # Get the current node count for the AKS cluster
            node_count=$(az aks show --name "$cluster_name" --resource-group "$resource_group" \
                --query "agentPoolProfiles[].count | sum(@)" -o tsv 2>/dev/null) # Suppress stderr
            
            if [ $? -ne 0 ] || ! [[ "$node_count" =~ ^[0-9]+$ ]]; then
                 echo "    Warning: Failed to get node count for cluster '$cluster_name' (RG: $resource_group). Assuming 0 nodes."
                 node_count=0
            fi

            echo "  Cluster '$cluster_name' has $node_count nodes."
            total_node_count=$((total_node_count + node_count))
        done <<< "$clusters" # Pass the cluster list to the while loop
    fi

done



echo "##########################################"
echo "Prisma Cloud Azure inventory collection complete."
echo ""
echo "VM Summary all subscriptions:"
echo "==============================="
echo "VM Instances:      $total_vm_count"
echo "AKS container VMs: $total_node_count"
