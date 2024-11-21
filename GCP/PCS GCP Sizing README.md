
## Usage
1.	Prerequisites:  
	* Install and configure the GCP CLI with appropriate credentials and permissions to describe resources.  
	* Ensure the script has executable permissions:  
1.	Run the script
1. Provide the output/screenshot of the script to your Palo Alto Prisma Cloud team members.  

`chmod +x pcs_gcp_sizing.sh`  
  
`./pcs_gcp_sizing.sh <organization-id>`

### What It Does
1.	Uses gcloud projects list to fetch all projects in the given organization.
2.	For each project:
	* Counts Compute Engine instances using gcloud compute instances list.
	* Lists GKE clusters using gcloud container clusters list and sums up the currentNodeCount of all clusters.
3.	Outputs the total counts for Compute Engine instances and GKE nodes across all projects.

