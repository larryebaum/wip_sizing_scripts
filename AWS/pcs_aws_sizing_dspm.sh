#!/bin/bash

# Ensure AWS CLI is configured
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    echo "Please configure your AWS CLI using 'aws configure' before running this script."
    exit 1
fi

# Initialize options
ORG_MODE=false
DSPM_MODE=false

# Get options
<<<<<<< HEAD
while getopts ":d:o:" opt; do
=======
while getopts ":do:" opt; do
>>>>>>> 3c72040b01ac3e5e9b0f512d637bd9cfd116a3d1
  case ${opt} in
    d)
      DSPM_MODE=true
      ;;
    o)
      ORG_MODE=true
      ;;
 esac
done
shift $((OPTIND-1))

if [ "$ORG_MODE" == true ]; then
  echo "Organization mode active"
fi
if [ "$DSPM_MODE" == true ]; then
  echo "DSPM mode active"
fi

# # Check for the organization mode argument
# ORG_MODE=false
# DSPM_MODE=false

# if [[ "$1" == "--organization" ]]; then
#     ORG_MODE=true
#     echo "Running in organization mode..."
# fi

# if [[ "$2" == "dspm" ]]; then
#     DSPM_MODE=true
#     echo "Counting additional DSPM resources..."
# fi

# Initialize counters
total_ec2_instances=0
total_eks_nodes=0
total_s3_buckets=0
total_efs=0
total_aurora=0
total_rds=0
total_dynamodb=0
total_redshift=0

# Function to count resources in a single account
count_resources() {
    local account_id=$1

    if [ "$ORG_MODE" == true ]; then
        # Assume role in the account (replace "OrganizationAccountAccessRole" with your role name if different)
        creds=$(aws sts assume-role --role-arn "arn:aws:iam::$account_id:role/OrganizationAccountAccessRole" \
            --role-session-name "OrgSession" --query "Credentials" --output json)

        if [ -z "$creds" ]; then
            echo "  Unable to assume role in account $account_id. Skipping..."
            return
        fi

        # Export temporary credentials
        export AWS_ACCESS_KEY_ID=$(echo $creds | jq -r ".AccessKeyId")
        export AWS_SECRET_ACCESS_KEY=$(echo $creds | jq -r ".SecretAccessKey")
        export AWS_SESSION_TOKEN=$(echo $creds | jq -r ".SessionToken")
    fi


    if [ "$DSPM_MODE" == false ]; then
        echo "Counting Cloud Security resources in account: $account_id"
        # Count EC2 instances
        ec2_count=$(aws ec2 describe-instances --query "Reservations[*].Instances[*]" --output json | jq 'length')
        echo "  EC2 instances: $ec2_count"
        total_ec2_instances=$((total_ec2_instances + ec2_count))

        # Count EKS nodes
        clusters=$(aws eks list-clusters --query "clusters" --output text)
        for cluster in $clusters; do
            node_count=$(aws eks describe-nodegroup --cluster-name "$cluster" --query "nodegroups[].scalingConfig.desiredSize" --output text | awk '{sum+=$1} END {print sum}')
            node_count=${node_count:-0} # Default to 0 if no nodes found
            echo "    EKS cluster '$cluster' nodes: $node_count"
            total_eks_nodes=$((total_eks_nodes + node_count))
        done
    fi

    if [ "$DSPM_MODE" == true ]; then
        echo "Counting DSPM Security resources in account: $account_id"
        # Count S3 buckets
        s3_count=$(aws s3api list-buckets --query "Buckets[*].Name" --output text | wc -w)
        echo "  S3 buckets: $s3_count"
        total_s3_buckets=$((total_s3_buckets + s3_count))

        # Count EFS file systems
        efs_count=$(aws efs describe-file-systems --query "FileSystems[*].FileSystemId" --output text | wc -w)
        echo "  EFS file systems: $efs_count"
        total_efs=$((total_efs + efs_count))

        # Count Aurora clusters
        aurora_count=$(aws rds describe-db-clusters --query "DBClusters[?Engine=='aurora'].DBClusterIdentifier" --output text | wc -w)
        echo "  Aurora clusters: $aurora_count"
        total_aurora=$((total_aurora + aurora_count))

        # Count RDS instances
        rds_count=$(aws rds describe-db-instances --query "DBInstances[?Engine=='mysql' || Engine=='mariadb' || Engine=='postgres'].DBInstanceIdentifier" --output text | wc -w)
        echo "  RDS instances (MySQL, MariaDB, PostgreSQL): $rds_count"
        total_rds=$((total_rds + rds_count))

        # Count DynamoDB tables
        dynamodb_count=$(aws dynamodb list-tables --query "TableNames" --output text | wc -w)
        echo "  DynamoDB tables: $dynamodb_count"
        total_dynamodb=$((total_dynamodb + dynamodb_count))

        # Count Redshift clusters
        redshift_count=$(aws redshift describe-clusters --query "Clusters[*].ClusterIdentifier" --output text | wc -w)
        echo "  Redshift clusters: $redshift_count"
        total_redshift=$((total_redshift + redshift_count))
    fi

    if [ "$ORG_MODE" == true ]; then
        # Unset temporary credentials
        unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    fi
}

# Main logic
if [ "$ORG_MODE" == true ]; then
    # Get the list of all accounts in the AWS Organization
    accounts=$(aws organizations list-accounts --query "Accounts[].Id" --output text)

    if [ -z "$accounts" ]; then
        echo "No accounts found in the organization."
        exit 0
    fi

    # Loop through each account in the organization
    for account_id in $accounts; do
        count_resources "$account_id"
    done
else
    # Run for the standalone account
    current_account=$(aws sts get-caller-identity --query "Account" --output text)
    count_resources "$current_account"
fi

if [ "$DSPM_MODE" == true ]; then
    echo "Total EC2 instances: $total_ec2_instances"
    echo "Total EKS nodes: $total_eks_nodes"
fi

if [ "$DSPM_MODE" == true ]; then
    echo "Total S3 buckets: $total_s3_buckets"
    echo "Total EFS file systems: $total_efs"
    echo "Total Aurora clusters: $total_aurora"
    echo "Total RDS instances: $total_rds"
    echo "Total DynamoDB tables: $total_dynamodb"
    echo "Total Redshift clusters: $total_redshift"
fi
