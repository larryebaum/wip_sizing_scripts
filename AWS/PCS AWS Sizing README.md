
## Usage
For best results, log in to the AWS Console for the master organization account with the admin/owner credentials. If an organization account is not in use, log in to each standalone account with admin/owner credentials.
   
### Prerequisites (if not using AWS CloudShell)  
* Install and configure the AWS CLI v2  
* Install `jq` 
    
### Execution  
1. Launch the AWS CloudShell from the top menu bar.  
2. Upload the sizing script to your CloudShell instance.  
3. `chmod +x ./pcs_aws_sizing.sh` to update permissions on the sizing script.  
4. Execute the script `./pcs_aws_sizing.sh [-o|-d]  
   * The script by default will sum up Cloud Security resources that are counted for licensing/credit counts.  
   * Two flags are available:  
      * `-o` will enable Organization mode and loop through each organization sub-account and sum up totals.  
      * `-d` will enable DSPM mode and count up resources for DSPM licensing/credit counts. This option can be used alone or in combination with `-o`.  
5. Provide the output/screenshot of the script to your Palo Alto Prisma Cloud team members.  

### What It Does
1. In Organization mode, the script uses `aws organizations list-accounts` to retrieve all accounts in the organization.  
1. Assumes a cross-account role (e.g., OrganizationAccountAccessRole) to access each sub-account.  
1. With no flags selected (Cloud Security mode), counts:
    * EC2 instances using `aws ec2 describe-instances`.  
    * EKS nodes by listing clusters and their node groups with `aws eks describe-nodegroup`.  
1. With `-d` flag, (DSPM Security mode), counts:
    * S3 instances using `aws s3api list-buckets`
    * EFS instances using `aws efs describe-file-systems`
    * Aurura clusters using `aws rds describe-db-clusters` and filtering on aurura engine
    * RDS instances using `aws rds describe-db-instances` and filtering on mysql, mariadb, and postgres engines
    * DynamoDB tables using `aws dynamodb list-tables`
    * Redshift clusters using `aws redshift describe-clusters`
      
### Troubleshooting
* The error `Cannot execute: required file not found` may result when using a Windows computer to upload the shell script to AWS console, due to the manner in which Windows converts CR/LF. The below two VIM commands can be used to convert CR/LF within the AWS CLI, or alternatively, utilities such as `dos2linux` can be utilized.
   * `:e ++ff=unix`
   * `:%s/\r\(\n\)/\1/g`
2. 
