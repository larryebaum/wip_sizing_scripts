#!/bin/bash

# Script to fetch Azure inventory for Prisma Cloud sizing.
# Requirements: az cli, jq, cut, grep

# This script can be run from Azure Cloud Shell.
# Run ./pcs_azure_sizing.sh -h for help on how to run the script.
# Or just read the text in showHelp below.

# Ensure Azure CLI is logged in
if ! az account show > /dev/null 2>&1; then
    echo "Please log in to Azure CLI using 'az login' before running this script."
    exit 1
fi

echo "Counting VM instances across all subscriptions in the tenant..."

# Initialize a total count
total_vm_count=0
total_node_count=0

# Get a list of all subscription IDs in the tenant
subscriptions=$(az account list --query "[].id" -o tsv)

# Loop through each subscription
for subscription_id in $subscriptions; do
    echo "Switching to subscription: $subscription_id"
    az account set --subscription "$subscription_id"

    # Count VMs in the current subscription
    vm_count=$(az vm list --query "length(@)" -o tsv)
    echo "VM instances in subscription '$subscription_id': $vm_count"

    # Add to the total count
    total_vm_count=$((total_vm_count + vm_count))

    # Get the list of all AKS clusters in the subscription
    clusters=$(az aks list --query "[].{name:name, resourceGroup:resourceGroup}" -o tsv)

    if [ -z "$clusters" ]; then
        echo "No AKS clusters found in the subscription."
        exit 0
    fi

    # Loop through each cluster
    while IFS=$'\t' read -r cluster_name resource_group; do
        echo "Processing cluster: $cluster_name (Resource Group: $resource_group)"

        # Get the current node count for the AKS cluster
        node_count=$(az aks show --name "$cluster_name" --resource-group "$resource_group" \
            --query "agentPoolProfiles[].count | sum(@)" -o tsv)

        echo "  Cluster '$cluster_name' has $node_count nodes."
        total_node_count=$((total_node_count + node_count))
    done <<< "$clusters"

done



echo "##########################################"
echo "Prisma Cloud Azure inventory collection complete."
echo ""
echo "VM Summary all subscriptions:"
echo "==============================="
echo "VM Instances:      $total_vm_count"
echo "AKS container VMs: $total_node_count"
