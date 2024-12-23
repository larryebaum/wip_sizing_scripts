#!/bin/bash

# Script to fetch GCP inventory for Prisma Cloud sizing.

# This script can be run from Azure Cloud Shell.
# Run ./pcs_azure_sizing.sh -h for help on how to run the script.
# Or just read the text in printHelp below.

function printHelp {
    echo ""
    echo "NOTES:"
    echo "* Requires gcloud CLI to execute"
    echo "* Requires JQ utility to be installed (TODO: Install JQ from script; exists in AWS, GCP)"
    echo "* Validated to run successfully from within CSP console CLIs"

    echo "Available flags:"
    echo " -d       Scan DSPM resources"
    echo "          This option will search for and count resources that are specific to data security"
    echo "          posture management (DSPM) licensing."
    echo " -o       Scan the indicated GCP organization ID, by default the organization ID will attempt"
    echo "          to be retrieved thus the need to provide the ID should not be necessary."
    echo "          If identified or supplied, this will fetch all projects associated with the organization"
    echo "          and assume a cross project role exists in order to iterate through and"
    echo "          scan each project resources. This is typically run from the admin user in"
    echo "          the organization account."
    echo " -h       Displays this help info"
    exit 1
}

# Initialize options
ORG_MODE=false
DSPM_MODE=false

# Get options
while getopts ":doh" opt; do
  case ${opt} in
    d) DSPM_MODE=true ;;
    o) ORG_MODE=true ;;
    h) printHelp ;;
    *) echo "Invalid option: -${OPTARG}" && printHelp exit ;;
 esac
done
shift $((OPTIND-1))

if [ "$ORG_MODE" == true ]; then
  echo "Organization mode active"
fi
if [ "$DSPM_MODE" == true ]; then
  echo "DSPM mode active"
fi

# Ensure gcloud CLI is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
    echo "Please authenticate with the gcloud CLI using 'gcloud auth login'."
    exit 1
fi
# Attempt to fetch organization ID programatically
ORG_ID=$(gcloud organizations list --format="value(ID)")

if [[ $ORG_ID =~ ^[0-9]{12}$ ]]; then
    echo "Organization ID: $ORG_ID identified"
    else
    echo "Organization ID not determined, reading input value"
    # Ensure the organization ID is set
    if [ -z "$1" ]; then
        echo "Usage: $0 <organization-id>"
        exit 1
    fi
    ORG_ID=$1
fi

#ORG_ID=$1
echo "Counting Compute Engine instances and GKE nodes in organization: $ORG_ID"

# Initialize counters
total_compute_instances=0
total_gke_nodes=0

# Get the list of projects in the organization
projects=$(gcloud projects list --filter="parent.id=$ORG_ID" --format="value(projectId)")

if [ -z "$projects" ]; then
    echo "No projects found in the organization."
    exit 0
fi

# Loop through each project
for project in $projects; do
    echo "Processing project: $project"

    # Set the current project
    gcloud config set project "$project" > /dev/null 2>&1

    # Count Compute Engine instances
    # TODO: INSERT LOGIC TO CHECK IF SERVICE IS ENABLED, ELSE SKIP
    compute_count=$(gcloud compute instances list --format="value(name)" --quiet | wc -l)
    echo "  Compute Engine instances: $compute_count"
    total_compute_instances=$((total_compute_instances + compute_count))

    # Count GKE nodes
    # TODO: INSERT LOGIC TO CHECK IF SERVICE IS ENABLED, ELSE SKIP
    clusters=$(gcloud container clusters list --format="value(name)" --quiet)
    for cluster in $clusters; do
        node_count=$(gcloud container clusters describe "$cluster" \
            --format="value(currentNodeCount)" --quiet 2>/dev/null || echo 0)
        echo "    Cluster '$cluster' has $node_count nodes."
        total_gke_nodes=$((total_gke_nodes + node_count))
    done
done

echo "##########################################"
echo "Prisma Cloud GCP inventory collection complete."
echo ""
echo "VM Summary all projects:"
echo "==============================="
echo "VM Instances:      $total_compute_instances"
echo "GKE container VMs: $total_gke_nodes"
