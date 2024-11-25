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
while getopts ":do" opt; do
  case ${opt} in
    d) DSPM_MODE=true ;;
    o) ORG_MODE=true ;;
    *) echo "Invalid option: -${OPTARG}" && exit 1 ;;
 esac
done
shift $((OPTIND-1))

if [ "$ORG_MODE" == true ]; then
  echo "Organization mode active"
fi
if [ "$DSPM_MODE" == true ]; then
  echo "DSPM mode active"
fi

# Initialize counters
total_ec2_instances=0
total_eks_nodes=0
total_s3_buckets=0
total_efs=0
total_aurora=0
total_rds=0
total_dynamodb=0
total_redshift=0

# Functions
check_running_databases() {
    # # Ensure AWS CLI is configured
    # if ! aws sts get-caller-identity &>/dev/null; then
    #     echo "Please configure your AWS CLI using 'aws configure' before running this script."
    #     return 1
    # fi

    # Required ports for database identification
    local DATABASE_PORTS=(3306 5432 27017 1433 33060)

    echo "Fetching all running EC2 instances..."
    local instances=$(aws ec2 describe-instances \
        --filters "Name=instance-state-name,Values=running" \
        --query "Reservations[*].Instances[*].{ID:InstanceId,IP:PrivateIpAddress,Name:Tags[?Key=='Name']|[0].Value}" \
        --output json)

    # Check if any instances were returned
    if [[ -z "$instances" || "$instances" == "[]" ]]; then
        echo "No running EC2 instances found."
        return 0
    fi

    echo "Found running EC2 instances. Checking each instance for database activity..."

    # Parse instances and check for databases
    for instance in $(echo "$instances" | jq -c '.[][]'); do
        local instance_id=$(echo "$instance" | jq -r '.ID')
        local private_ip=$(echo "$instance" | jq -r '.IP')
        local instance_name=$(echo "$instance" | jq -r '.Name // "Unnamed Instance"')

        echo "Checking instance: $instance_name (ID: $instance_id, IP: $private_ip)"

        # Fetch security group details
        local sg_ids=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --query "Reservations[0].Instances[0].SecurityGroups[*].GroupId" \
            --output text)

        echo "  Security Groups: $sg_ids"

        for sg_id in $sg_ids; do
            local open_ports=$(aws ec2 describe-security-groups \
                --group-ids "$sg_id" \
                --query "SecurityGroups[0].IpPermissions[*].FromPort" \
                --output text | tr '\t' '\n' | sort -u)

            echo "    Open Ports: $open_ports"

            # Check for database ports
            for port in "${DATABASE_PORTS[@]}"; do
                if echo "$open_ports" | grep -q "^$port$"; then
                    echo "      Database port $port detected in Security Group $sg_id"
                fi
            done
        done

        # Optional: Check for running database processes via Systems Manager
        if aws ssm describe-instance-information \
            --query "InstanceInformationList[?InstanceId=='$instance_id']" \
            --output text &>/dev/null; then
            echo "  Instance is managed by Systems Manager. Checking for database processes..."
            local running_processes=$(aws ssm send-command \
                --instance-ids "$instance_id" \
                --document-name "AWS-RunShellScript" \
                --comment "Check for running database processes" \
                --parameters 'commands=["ps aux | grep -E \"postgres|mongo|mysql|mariadb|sqlserver\" | grep -v grep"]' \
                --query "Command.CommandId" --output text)

            sleep 2 # Allow time for the command to execute
            local output=$(aws ssm list-command-invocations \
                --command-id "$running_processes" \
                --details --query "CommandInvocations[0].CommandPlugins[0].Output" \
                --output text)

            if [[ -n "$output" ]]; then
                echo "  Database processes detected:"
                echo "$output"
            else
                echo "  No database processes detected."
            fi
        else
            echo "  Instance is not managed by Systems Manager. Skipping process check."
        fi
    done

    echo "Database scan complete."
}

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
            node_groups=$(aws eks list-nodegroups --cluster-name "$cluster" --query 'nodegroups' --output text)
            total_nodes=0
            for node_group in $node_groups; do
                node_count=$(aws eks describe-nodegroup --cluster-name "$cluster" --nodegroup-name "$node_group" --query "nodegroup.scalingConfig.desiredSize" --output text)
                total_nodes=$((total_nodes + node_count))
                echo "    EKS cluster '$cluster' nodegroup $node_group nodes: $node_count"
                total_eks_nodes=$((total_eks_nodes + total_nodes))
            done
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
    
    check_running_databases

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

#end
