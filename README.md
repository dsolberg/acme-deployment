# acme-deployment


Requires: curl, wget, jq

Prerequisites:

You will need to have AWS API credentials configured. What works for AWS CLI or any other tools (kops, Terraform etc), should be sufficient. You can use ~/.aws/credentials file or environment variables.


Rationals:

* Utilized EKS / eksctl to be able to build a live k8s cluster relatively quickly given my available time is short. As well as wanting to give it a try.
* I used Cloudformation yaml because I prefer cloud native where possible.
* I used KMS to encrypt as much of the data at rest as possible as it has a high ROI.
* I used Helm to build Prometheus as it was a very simple way to do so.
* I used Nginx-ingress in order to do TLS offloading for the API and www as it was very simple to setup.
* I used Route53 for DNS as it was simple to lock to the ELB of the Nginx-ingress.
* I used RDS to simply do multi-AZ for high availability, automatic snapshots and updates.


Shortcomings:

* A lot of CLI driven tooling bridging the gap between eksctl, k8s and Cloudformation makes it somewhat fragile to create.
* No automated CI/CD makes the CLI tooling required.
* Self signed certs not ideal and this one doesn't quite work right.
* Autoscaling not enabled.
* No VPN setup to connect to services in the VPC.
* No automated testing to validate any changes.
* K8s --purge feature is in alpha and does not reliabily maintain state per configuration files.
* Only survives a single AZ failure being dual AZ by default.
* Would have liked to use more exports and parameters.
* Password entry is awkward and to update the db cluster you need to remember it.
* Did not have much time to make it bulletproof. May be some timing issues in the creation times.
* May look to using more AWS PaaS servies to get rid of the containers and use API Gateway/etc.
* May look to using full Kubernetes to take advantage of automated vertical/horizontal and control plane scaling


To create the K8s cluster in AWS.
Run:

./create.sh


To update the scaling of the nodes, run:

eksctl scale nodegroup --cluster acme-cluster -r us-west-2 -n acme-node-1 -N <x>

<x> being the digit of nodes you would like. 2 is the default.


To update the scaling of the UI edit:

ui/deployment.yaml

Change replicas to the number of replicas you would like.



To update the scaling of the API edit:

api/deployment.yaml

Change replicas to the number of replicas you would like.


