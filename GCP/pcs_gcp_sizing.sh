#!/bin/bash

# Script to fetch GCP inventory for Prisma Cloud sizing.

# This script can be run from Azure Cloud Shell.
# Run ./pcs_azure_sizing.sh -h for help on how to run the script.
# Or just read the text in printHelp below.

# Check for jq dependency
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install jq to run this script."
    echo "(e.g., 'sudo apt-get install jq' or 'sudo yum install jq' or 'brew install jq')"
    exit 1
fi

# Function to handle errors
function check_error {
    local exit_code=$1
    local message=$2
    if [ $exit_code -ne 0 ]; then
        echo "Error: $message (Exit Code: $exit_code)"
        # Add any GCP specific cleanup here if needed in the future
        exit $exit_code
    fi
}

function printHelp {
    echo ""
    echo "NOTES:"
    echo "* Requires gcloud CLI to execute"
    echo "* Requires JQ utility to be installed (TODO: Install JQ from script; exists in AWS, GCP)"
    echo "* Validated to run successfully from within CSP console CLIs"
    echo ""
    echo "Usage: $0 [organization-id]"
    echo "  If organization-id is not provided, the script will attempt to find it."
    echo ""
    echo "Available flags:"
    echo " -h       Display this help info"
    exit 1
}

# Initialize options
# No options needed currently besides -h

# Get options
while getopts ":h" opt; do
  case ${opt} in
    h) printHelp ;;
    *) echo "Invalid option: -${OPTARG}" && printHelp exit ;;
 esac
done
shift $((OPTIND-1))

# Ensure gcloud CLI is authenticated
gcloud auth list --filter=status:ACTIVE --format="value(account)" > /dev/null 2>&1
check_error $? "gcloud CLI not authenticated. Please run 'gcloud auth login'."

# Determine Organization ID
ORG_ID=""
if [ -n "$1" ]; then
    # Use Org ID provided as argument
    ORG_ID=$1
    echo "Using provided Organization ID: $ORG_ID"
    # Basic validation if it looks like a number
    if ! [[ "$ORG_ID" =~ ^[0-9]+$ ]]; then
        echo "Error: Provided Organization ID '$ORG_ID' does not appear to be numeric."
        exit 1
    fi
else
    # Attempt to fetch organization ID programatically
    echo "Attempting to detect Organization ID..."
    org_list=$(gcloud organizations list --format="value(ID)")
    check_error $? "Failed to list organizations. Ensure you have 'resourcemanager.organizations.get' permission or provide the Organization ID as an argument."
    
    org_count=$(echo "$org_list" | wc -w)

    if [ "$org_count" -eq 0 ]; then
        echo "Error: No organizations found for the current user. Please provide the Organization ID as an argument."
        exit 1
    elif [ "$org_count" -eq 1 ]; then
        ORG_ID=$org_list
        echo "Automatically detected Organization ID: $ORG_ID"
    else
        echo "Error: Multiple Organization IDs found. Please specify one as an argument:"
        echo "$org_list"
        exit 1
    fi
fi

echo "Counting Compute Engine instances and GKE nodes in organization: $ORG_ID"

# Initialize counters
total_compute_instances=0
total_gke_nodes=0

# Get the list of projects in the organization
projects=$(gcloud projects list --filter="parent.id=$ORG_ID" --format="value(projectId)")
check_error $? "Failed to list projects for organization $ORG_ID. Ensure you have 'resourcemanager.projects.list' permission."

if [ -z "$projects" ]; then
    echo "No active projects found in organization $ORG_ID."
    exit 0
fi

# Loop through each project
for project in $projects; do
    echo "Processing project: $project"

    # Set the current project - capture stderr to suppress potential permission errors if already set
    gcloud config set project "$project" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "  Warning: Failed to set project context to '$project'. Skipping project."
        continue
    fi

    # Count Compute Engine instances
    echo "  Checking Compute Engine API status..."
    # Check if Compute Engine API is enabled - capture stderr
    gcloud services list --enabled --filter="NAME:compute.googleapis.com" --format="value(NAME)" --quiet 2>/dev/null | grep -q "compute.googleapis.com"
    if [ $? -eq 0 ]; then
        echo "  Compute Engine API enabled. Counting instances..."
        # Use --format=json and jq for potentially more robust counting than wc -l
        compute_count=$(gcloud compute instances list --format=json --quiet | jq 'length')
        if [ $? -ne 0 ]; then
             echo "    Warning: Failed to list Compute Engine instances for project '$project'. Setting count to 0 for this project."
             compute_count=0
        fi
        echo "    Compute Engine instances: $compute_count"
        total_compute_instances=$((total_compute_instances + compute_count))
    else
        echo "  Compute Engine API not enabled or accessible in project '$project'. Skipping instance count."
    fi

    # Count GKE nodes
    echo "  Checking Kubernetes Engine API status..."
    # Check if Kubernetes Engine API is enabled - capture stderr
    gcloud services list --enabled --filter="NAME:container.googleapis.com" --format="value(NAME)" --quiet 2>/dev/null | grep -q "container.googleapis.com"
     if [ $? -eq 0 ]; then
        echo "  Kubernetes Engine API enabled. Counting nodes..."
        clusters=$(gcloud container clusters list --format="value(name)" --quiet)
        if [ $? -ne 0 ]; then
            echo "    Warning: Failed to list GKE clusters for project '$project'. Skipping node count for this project."
        else
            if [ -z "$clusters" ]; then
                echo "    No GKE clusters found in project '$project'."
            else
                 for cluster in $clusters; do
                    # Attempt to get node count, default to 0 on error
                    node_count=$(gcloud container clusters describe "$cluster" --format="value(currentNodeCount)" --quiet 2>/dev/null)
                    if [ $? -ne 0 ] || ! [[ "$node_count" =~ ^[0-9]+$ ]]; then
                         echo "      Warning: Failed to get node count for cluster '$cluster' in project '$project'. Assuming 0 nodes."
                         node_count=0
                    fi
                    echo "      Cluster '$cluster' has $node_count nodes."
                    total_gke_nodes=$((total_gke_nodes + node_count))
                done
            fi
        fi
    else
        echo "  Kubernetes Engine API not enabled or accessible in project '$project'. Skipping node count."
    done
done

echo "##########################################"
echo "Prisma Cloud GCP inventory collection complete."
echo ""
echo "VM Summary all projects:"
echo "==============================="
echo "VM Instances:      $total_compute_instances"
echo "GKE container VMs: $total_gke_nodes"
