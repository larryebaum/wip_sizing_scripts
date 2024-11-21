
## Usage
1. Prerequisites  
	* Install and configure the AWS CLI with appropriate credentials and permissions to assume roles and describe resources.  
	* `jq` must be installed for JSON parsing
    * Ensure the script has executable permissions:  
1. Run the script and if executing against an Organization account, include the flag `--organization` 
1. Provide the output/screenshot of the script to your Palo Alto Prisma Cloud team members.  

`chmod +x pcs_aws_sizing.sh`  
  
`./pcs_aws_sizing.sh [--organization]`  

### What It Does
1. Uses `aws organizations list-accounts` to retrieve all accounts in the organization.  
1. Assumes a cros-account role (e.g., OrganizationAccountAccessRole) in each account.  
1. Counts
    * EC2 instances using `aws ec2 describe-instances`.  
    * EKS nodes by listing clusters and their node groups with `aws eks describe-nodegroup`.  
