
## Usage
1.	Prerequisites:  
	* Install and configure the Azure CLI with appropriate credentials and permissions to describe resources.  
	* Ensure the script has executable permissions:  
1.	Run the script
1. Provide the output/screenshot of the script to your Palo Alto Prisma Cloud team members.  


`chmod +x pcs_azure_sizing.sh`  
  
`./pcs_azure_sizing.sh <organization-id>`

### What It Does
1. Uses `az vm list` to fetch a list of virtual machines across all subscriptions in your Azure tenant and calculates the count.
1. Uses `az aks list` to fetch all AKS clusters and their associated resource groups across all subscriptions in your Azure tenant. For each cluster, it retrieves the number of worker nodes using the `az aks show` command and sums them up, and then calculates the total nodes.
