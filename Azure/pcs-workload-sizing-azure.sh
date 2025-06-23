#!/bin/bash

# Script to fetch Azure inventory for Prisma Cloud sizing using Azure Resource Graph.
# Requirements: az cli (with graph extension potentially needed, though often built-in now)
# Permissions: Requires Azure Resource Graph read permissions across target subscriptions.

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
        # Optionally unset credentials if in org mode before exiting
        if [ "$ORG_MODE" == true ] && [ -n "$AWS_SESSION_TOKEN" ]; then
            unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
        fi
        exit $exit_code
    fi
}

function printHelp {
    echo ""
    echo "NOTES:"
    echo "* Requires AWS CLI v2 to execute"
    echo "* Requires JQ utility to be installed (TODO: Install JQ from script; exists in AWS)"
    echo "* Validated to run successfully from within CSP console CLIs"

    echo "Available flags:"
    echo " -c          Connect via SSM to EC2 instances running DBs in combination with DSPM mode"
    # echo " -d          DSPM mode"
    # echo "             This option will search for and count resources that are specific to data security"
    # echo "             posture management (DSPM) licensing."
    echo " -h          Display the help info"
    echo " -n <region> Single region to scan"
    echo " -o          Organization mode"
    echo "             This option will fetch all sub-accounts associated with an organization"
    echo "             and assume the default (or specified) cross account role in order to iterate through and"
    echo "             scan resources in each sub-account. This is typically run from the admin user in"
    echo "             the master account."
    echo " -r <role>   Specify a non default role to assume in combination with organization mode"
    echo " -s          Include stopped compute instances in addition to running"
    exit 1
}

echo "$(tput bold)$(tput setaf 2)";
echo "   ___           _                ___ _                 _ ";
echo "  / __\___  _ __| |_ _____  __   / __\ | ___  _   _  __| |";
echo " / /  / _ \| '__| __/ _ \ \/ /  / /  | |/ _ \| | | |/ _\` |";
echo "/ /__| (_) | |  | ||  __/>  <  / /___| | (_) | |_| | (_| |";
echo "\____/\___/|_|   \__\___/_/\_\ \____/|_|\___/ \__,_|\__,_|";
echo "                                                          ";
echo "                                                          ";
echo "$(tput sgr0)";

# Ensure Azure CLI is logged in
az account show > /dev/null 2>&1
check_error $? "Azure CLI not logged in. Please run 'az login'."

echo "Counting resources across accessible subscriptions using Azure Resource Graph..."

# Initialize options
ORG_MODE=false ##REWORK FOR SUB OR TENANT
ROLE="OrganizationAccountAccessRole" ##REWORK FOR SUB OR TENANT
REGION=""
STATE="running"

# Get options
while getopts ":cdhn:or:s" opt; do
  case ${opt} in
    c) SSM_MODE=true ;;
    d) DSPM_MODE=true ;; ##TO REMOVE
    h) printHelp ;;
    n) REGION="$OPTARG" ;;
    o) ORG_MODE=true ;; ##REWORK FOR SUB OR TENANT
    r) ROLE="$OPTARG" ;;
    s) STATE="running,stopped" ;;
    *) echo "Invalid option: -${OPTARG}" && printHelp exit ;;
 esac
done
shift $((OPTIND-1))

# Get a list of all supported Azure locations (regions)
# --query "[].name" extracts only the 'name' field from each location object
# --output tsv formats the output as tab-separated values, one region name per line
activeRegions=$(az account list-locations --query "[].name" | tr '\n' ' '| tr -s ' ')

# Check if any regions were found
if [ -z "$activeRegions" ]; then
  echo "Error: Could not retrieve list of active regions."
  exit 1
fi
echo "Active regions found: ($activeRegions"

# Validate region flag
if [[ "${REGION}" ]]; then
    # Use grep -w for whole word match to avoid partial matches (e.g., "us-east" matching "us-east-1")
    if echo "$activeRegions" | grep -qw "$REGION";
        then echo "Requested region is valid";
    else echo "Invalid region requested: $REGION";
    exit 1
    fi 
fi

# Initialize counts ###REWORK NOMENCLATURE
total_vm_count=0
total_node_count=0
total_s3_buckets=0
total_efs=0
total_aurora=0
total_rds=0
total_dynamodb=0
total_redshift=0
total_ec2_db=0
ec2_db_count=0
paas_workloads=0
total_paas_workloads=0
caas_workloads=0
total_caas_workloads=0
container_image_workloads=0
total_container_image_workloads=0
functionapp_count=0
total_functionapp_count=0
eks_workloads=0
total_eks_workloads=0
s3_workloads=0
total_s3_workloads=0


# # Function to count resources in a single account
# count_resources() {
#     local account_id=$1
   
#     echo "Counting Cloud Security resources in account: $account_id"
#     # Count VM instances
#     if [[ "${REGION}" ]]; then
#         vm_count=$(az vm list --query "length([?location=='$TARGET_REGION'])")
#         check_error $? "Failed to describe VM instances in region $REGION for account $account_id."
#     else
#         echo "  Counting VM instances across all accessible regions..."
#         vm_count=0
#         # Use the activeRegions variable fetched earlier
#         for r in $activeRegions; do
#             #strip out characters from array
#             r="${r//\"/}"; r="${r//,/}"
#             # Capture stderr to avoid cluttering output for regions where API might not be enabled/accessible
#             count_in_region=$(az vm list --query "length([?location=='$r'])")
#             if [ $? -eq 0 ] && [[ "$count_in_region" =~ ^[0-9]+$ ]]; then
#                 # Only print if count > 0 to reduce noise
#                 if [ "$count_in_region" -gt 0 ]; then
#                     echo "    Region $r: $count_in_region instances"
#                 fi
#                 vm_count=$((vm_count + count_in_region))
#             fi
#         done
#     fi

# --- Count VMs using Azure Resource Graph ---
echo "Querying Azure Resource Graph for VM count..."
# Query for all VMs across all accessible subscriptions
vm_query="Resources | where type =~ 'microsoft.compute/virtualmachines' | count"
vm_result_json=$(az graph query -q "$vm_query" --output json)
vm_query_exit_code=$?

if [ $vm_query_exit_code -ne 0 ]; then
    echo "  Warning: Failed to query Azure Resource Graph for VMs (Exit Code: $vm_query_exit_code). Assuming 0 VMs."
    total_vm_count=0
else
    # Extract count using jq
    total_vm_count=$(echo "$vm_result_json" | jq '.count // 0')
    if ! [[ "$total_vm_count" =~ ^[0-9]+$ ]]; then
         echo "  Warning: Could not parse VM count from Resource Graph result. Assuming 0 VMs."
         total_vm_count=0
    fi
fi
echo "Total VM Instances found: $total_vm_count"

# --- Count AKS Nodes using Azure Resource Graph ---
echo "Querying Azure Resource Graph for AKS node count..."
# Query for AKS clusters, expand agent pools, and sum node counts
aks_query="Resources | where type =~ 'microsoft.containerservice/managedclusters' | project properties.agentPoolProfiles | mv-expand profile = properties_agentPoolProfiles | summarize sum(toint(profile.count))"
aks_result_json=$(az graph query -q "$aks_query" --output json)
aks_query_exit_code=$?

if [ $aks_query_exit_code -ne 0 ]; then
    echo "  Warning: Failed to query Azure Resource Graph for AKS nodes (Exit Code: $aks_query_exit_code). Assuming 0 nodes."
    total_node_count=0
else
    # Extract sum using jq - the field name is typically 'sum_' followed by the summarized field
    total_node_count=$(echo "$aks_result_json" | jq '.data[0].sum_profile_count // 0')
     if ! [[ "$total_node_count" =~ ^[0-9]+$ ]]; then
         echo "  Warning: Could not parse AKS node count from Resource Graph result. Assuming 0 nodes."
         total_node_count=0
    fi
fi

# --- Count Azure Functions using Azure Resource Graph ---
echo "Querying Azure Resource Graph for Azure functions count..."
functionapp_count=$(az graph query \
  --graph-query "Resources | where type =~ 'Microsoft.Web/sites' and kind contains 'functionapp' | count" \
  --query "totalRecords" \
  -o tsv)

# Check if the count was retrieved successfully
if [ -z "$functionapp_count" ]; then
  echo "Failed to retrieve Function App count. Please check your Azure permissions or network connectivity."
fi

# --- Count Azure Blob containers using Azure Resource Graph ---
echo "Querying Azure Resource Graph for Blob container count..."
blob_container_count=$(az graph query \
  --graph-query "Resources | where type =~ 'Microsoft.Storage/storageAccounts/blobServices/containers' | count" \
  --query "totalRecords" \
  -o tsv)

if [ -z "$blob_container_count" ]; then
  echo "Failed to retrieve Blob Container count. Please check your Azure permissions or network connectivity."
else
  echo "--------------------------------------------------------"
  echo "Total Azure Blob Containers found: $blob_container_count"
  echo "--------------------------------------------------------"
fi

# --- Count CaaS containers using Azure Resource Graph ---
echo "Querying Azure Resource Graph for container instances, apps, & AKS pods count..."
# Initialize total counter
total_managed_containers=0

# --- Part 1: Count Azure Container Instances (ACI Container Groups) using Azure Resource Graph ---
echo "1. Counting Azure Container Instances (Container Groups)..."
aci_count=$(az graph query \
  --graph-query "Resources | where type =~ 'microsoft.containerinstance/containergroups' | count" \
  --query "totalRecords" \
  -o tsv)

# Handle cases where query might fail or return no resources
if [ -z "$aci_count" ]; then
  aci_count=0 # Ensure it's a number for arithmetic
  echo "  (No Azure Container Instances found or query failed.)"
fi
echo "  Azure Container Instances (Container Groups) found: $aci_count"
total_managed_containers=$((total_managed_containers + aci_count))

# --- Part 2: Count Azure Container Apps using Azure Resource Graph ---
echo "2. Counting Azure Container Apps..."
aca_count=$(az graph query \
  --graph-query "Resources | where type =~ 'microsoft.app/containerapps' | count" \
  --query "totalRecords" \
  -o tsv)

# Handle cases where query might fail or return no resources
if [ -z "$aca_count" ]; then
  aca_count=0 # Ensure it's a number for arithmetic
  echo "  (No Azure Container Apps found or query failed.)"
fi
echo "  Azure Container Apps found: $aca_count"
total_managed_containers=$((total_managed_containers + aca_count))

# --- Part 3: Count individual Pods running within AKS Clusters ---
echo "3. Counting individual Pods within Azure Kubernetes Service (AKS) clusters..."
echo "   Note: This process connects to each AKS cluster and may take significant time."
echo "   It counts Kubernetes Pods. Each Pod typically contains one or more containers."
echo "   Ensure you have appropriate permissions to access AKS clusters and list pods."

aks_pod_count=0

# Get all AKS cluster IDs across all resource groups
# Using 'id' for a robust loop
aks_clusters=$(az aks list --query "[].id" -o tsv)

if [ -z "$aks_clusters" ]; then
  echo "  No Azure Kubernetes Service (AKS) clusters found in your subscription."
else
  for cluster_id in $aks_clusters; do
    # Extract name and resource group from the cluster ID for az aks get-credentials
    cluster_name=$(echo "$cluster_id" | awk -F'/' '{print $NF}')
    cluster_resource_group=$(echo "$cluster_id" | awk -F'/' '{print $(NF-3)}')

    echo "  Processing AKS cluster: $cluster_name (Resource Group: $cluster_resource_group)"

    # Get AKS credentials for kubectl.
    # --overwrite-existing: Ensures kubectl context is updated.
    # --only-show-errors: Suppresses most output for cleaner script logs.
    # > /dev/null: Further redirects remaining output.
    az aks get-credentials --resource-group "$cluster_resource_group" --name "$cluster_name" --overwrite-existing --only-show-errors > /dev/null 2>&1

    # Check if kubectl context was successfully set and we can query pods
    # This checks for connectivity/permissions before trying to count.
    if kubectl get pods -A --output=name > /dev/null 2>&1; then
      # Count all pods in all namespaces for the current cluster
      # '-A' or '--all-namespaces' lists pods from all namespaces.
      # '-o name' outputs 'pod/<pod-name>' per line.
      # 'wc -l' counts the lines.
      current_cluster_pods=$(kubectl get pods -A -o name 2>/dev/null | wc -l)
      echo "    Pods found in $cluster_name: $current_cluster_pods"
      aks_pod_count=$((aks_pod_count + current_cluster_pods))
    else
      echo "    Warning: Could not connect to or count pods in $cluster_name (possible permission issue or cluster not ready)."
    fi
  done
fi

echo "  Total Pods across all AKS clusters: $aks_pod_count"
total_managed_containers=$((total_managed_containers + aks_pod_count))

echo "-----------------------------------------------------------------------------------------------------------------"
echo "Final Total Managed Containers (ACI Container Groups + Azure Container Apps + AKS Pods): $total_managed_containers"
echo "-----------------------------------------------------------------------------------------------------------------"
echo "Please remember:"
echo " - This count includes Azure Container Instances (Container Groups) and Azure Container Apps directly."
echo " - For Azure Kubernetes Service (AKS), this counts Kubernetes Pods. A single Pod can contain multiple containers."
echo " - This script requires appropriate Azure RBAC permissions for 'az aks get-credentials' and Kubernetes RBAC permissions within the clusters to 'list pods'."
echo " - Running this script may take considerable time if you have many AKS clusters, as it connects to each one."

# --- Count Container Images within repositories ---
echo "Counting container image tags across all Azure Container Registries..."

total_image_tags=0

# Get a list of all Azure Container Registry names
acr_names=$(az acr list --query '[].name' -o tsv)

if [ -z "$acr_names" ]; then
  echo "No Azure Container Registries found in your current subscription."
else
  for acr_name in $acr_names; do
    echo "Processing registry: $acr_name"

    # List all repositories within the current ACR
    repositories=$(az acr repository list --name "$acr_name" --query '[]' -o tsv)

    if [ -z "$repositories" ]; then
      echo "  No repositories found in $acr_name."
    else
      for repo in $repositories; do
        # Count tags for each repository
        # We need to escape the repository name if it contains slashes (e.g., 'ubuntu/nginx')
        # JMESPath query 'length(@)' counts elements in the returned array of tags
        tag_count=$(az acr repository show-tags \
          --name "$acr_name" \
          --repository "$repo" \
          --query 'length(@)' \
          -o tsv)

        if [ -n "$tag_count" ]; then
          echo "    - Repository '$repo': $tag_count tags"
          total_image_tags=$((total_image_tags + tag_count))
        else
          echo "    - Repository '$repo': Could not retrieve tag count."
        fi
      done
    fi
  done
fi

echo "Container Image Count: $total_image_tags"

# --- Count PaaS databases ---
echo "Querying Azure Resource Graph for PaaS managed database count..."
# Define the Kusto Query Language (KQL) query.
# It selects resources of various managed database types and then counts them.
# Each 'type' corresponds to a specific Azure managed database service.
graph_query="Resources \
| where type =~ 'microsoft.sql/servers/databases' \
or type =~ 'microsoft.sql/managedinstances' \
or type =~ 'microsoft.dbforpostgresql/servers' \
or type =~ 'microsoft.dbforpostgresql/flexibleservers' \
or type =~ 'microsoft.dbformysql/servers' \
or type =~ 'microsoft.dbformysql/flexibleservers' \
or type =~ 'microsoft.dbformariadb/servers' \
or type =~ 'microsoft.documentdb/databaseaccounts' \
| count"

# Execute the Azure Resource Graph query
# The '--query "totalRecords"' extracts the total count from the JSON output.
# The '-o tsv' ensures a clean numerical output for easy variable assignment.
database_count=$(az graph query \
  --graph-query "$graph_query" \
  --query "totalRecords" \
  -o tsv)

# Check if the count was retrieved successfully
if [ -z "$database_count" ]; then
  echo "Failed to retrieve managed database count. Please check your Azure permissions or network connectivity."
else
  echo "Total managed databases (instances/accounts) found: $database_count"
fi


echo ""
echo "  WORKLOAD COUNTS"
echo "  VM workloads: $total_vm_count"
echo "  VM (container) workloads: $total_node_count"
echo "  Serverless workloads: $functionapp_count"
echo "  Blob workloads: $blob_container_count"
echo "  CaaS workloads: $total_managed_containers"
echo "  Container Image workloads: $total_container_image_workloads"
echo "  PaaS workloads: $database_count"  
echo ""
#echo "$(tput bold)$(tput setaf 2)** SUM TOTAL WORKLOADS: $((total_ec2_instances+total_eks_workloads+total_serverless_workloads+total_s3_workloads+total_caas_workloads+total_container_image_workloads+total_paas_workloads))**$(tput sgr0)"
