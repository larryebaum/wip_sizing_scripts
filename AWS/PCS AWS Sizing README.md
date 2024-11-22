
## Usage
1. Prerequisites  
    * Install and configure the AWS CLI with appropriate credentials and permissions to assume roles and describe resources.  
    * Ensure the script has executable permissions: `chmod +x pcs_aws_sizing.sh`   
1. The script by default will count up Cloud Security resources that are counted for licensing/credit counts.
2. Two flags are available:
    * `-o` will enable Organization mode and loop through each organization sub-account and sum up totals. 
    * `-d` will enable DSPM mode and count up resources for DSPM licensing/credit counts. This option can be used alone or in combination with `-o`.
1. Execute the script: `./pcs_aws_sizing.sh [o|d]`
2. Provide the output/screenshot of the script to your Palo Alto Prisma Cloud team members.  


### What It Does
1. Uses `aws organizations list-accounts` to retrieve all accounts in the organization.  
1. Assumes a cros-account role (e.g., OrganizationAccountAccessRole) in each account.  
1. Counts
    * EC2 instances using `aws ec2 describe-instances`.  
    * EKS nodes by listing clusters and their node groups with `aws eks describe-nodegroup`.  
