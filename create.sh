if [[ "$OSTYPE" == "linux-gnu" ]]; then
	export PATH=`pwd`/bin:$PATH
	mkdir -p bin
	cd bin
	curl -o aws-iam-authenticator https://amazon-eks.s3-us-west-2.amazonaws.com/1.11.5/2018-12-06/bin/linux/amd64/aws-iam-authenticator
	curl -o kubectl https://amazon-eks.s3-us-west-2.amazonaws.com/1.11.5/2018-12-06/bin/linux/amd64/kubectl
	curl --silent --location "https://github.com/weaveworks/eksctl/releases/download/latest_release/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C .
	curl -o helm.tgz https://kubernetes-helm.storage.googleapis.com/helm-v2.12.3-linux-amd64.tar.gz
	tar -zxvf helm.tgz
	mv linux-amd64/helm .
	mv linux-amd64/tiller .
	chmod +x ./helm
	chmod +x ./tiller
	chmod +x ./aws-iam-authenticator
	chmod +x ./eksctl
	chmod +x ./kubectl
	cd ..
elif [[ "$OSTYPE" == "darwin"* ]]; then
	brew tap weaveworks/tap
	brew install weaveworks/tap/eksctl
	brew install helm
	brew install jq
fi

eksctl create cluster --timeout 40m -f cluster/cluster.yaml

# Fetch eksctl generated cluster vars
export VPC=$(aws ec2 describe-vpcs --region=us-west-2 --filters "Name=tag-key,Values=eksctl.cluster.k8s.io/v1alpha1/cluster-name" --query "Vpcs[*].VpcId" --output text)
export SG=$(aws ec2 describe-security-groups --region=us-west-2 --filters "Name=tag:aws:cloudformation:logical-id,Values=ClusterSharedNodeSecurityGroup" --query=SecurityGroups[*].GroupId --output text)
export SUBNETS=$(aws ec2 describe-subnets --region us-west-2 --filters="Name=tag:eksctl.cluster.k8s.io/v1alpha1/cluster-name, Values=acme-cluster, Name=tag:aws:cloudformation:logical-id, Values=SubnetPrivate*" --query Subnets[*].SubnetId|jq '.' -c|awk -F'[][]' '{print $2}'|sed 's/[" ]//g')

#aws cloudformation deploy --region=us-west-2 --template-file db/cfn-kms.yaml --stack-name=acme-kms
while [ ${#DBPASS} -lt 8 ]
do
	read -p "Enter DB Master Password (At least 8 characters): " DBPASS
done
aws cloudformation deploy --region=us-west-2 --template-file db/cfn-db.yaml --stack-name=acme-db --parameter-overrides "ClusterVpc=$VPC" "ClusterNodeSg=$SG" "DbPass=$DBPASS" "SubnetIdList=$SUBNETS"
export POSTGRES_ENDPOINT=$(aws rds describe-db-instances --region=us-west-2 --filters "Name=db-instance-id,Values=acme-db" --query DBInstances[*].Endpoint.Address --output text)
export POSTGRES_URL=${POSTGRES_ENDPOINT}:5432

kubectl apply -f cluster/storageclass.yaml
kubectl patch storageclass encrypted-gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

kubectl apply -f nginx-ingress/mandatory.yaml
kubectl apply -f nginx-ingress/service-l4.yaml
kubectl apply -f nginx-ingress/patch-configmap-l4.yaml
kubectl patch service ingress-nginx -p '{"spec":{"externalTrafficPolicy":"Local"}}' -n ingress-nginx
mkdir -p certs
openssl req -x509 -newkey rsa:4096 -sha256 -keyout certs/privkey.pem -out certs/domain.crt -days 365 -nodes -subj '/CN=localhost'
kubectl create secret tls my-certs --cert=certs/domain.crt --key=certs/privkey.pem

kubectl apply -f cluster/helm.yaml
helm init --service-account tiller
echo Waiting for tiller to be ready.
while [ $(kubectl -n kube-system get po|grep tiller|grep 1\/1|wc -c) -lt 1 ]
do
	echo -n .
	sleep 2
done
helm install -f metrics/prometheus-values.yaml stable/prometheus --name prometheus --namespace prometheus
export PROMETHEUS_URL=prometheus-server.prometheus.svc.cluster.local:80

kubectl apply -f api/deployment.yaml
kubectl apply -f api/service.yaml

kubectl apply -f ui/deployment.yaml
kubectl apply -f ui/service.yaml

kubectl apply -f nginx-ingress/app-ingress.yaml

export INGRESS_ELB=$(kubectl get ingress -ojsonpath='{.items[*].status.loadBalancer.ingress[*].hostname}')
aws cloudformation deploy --region=us-west-2 --template-file route53/dns-elb-nginx-ingress.yaml --stack-name acme-dns --parameter-overrides "VpcId=$VPC" "NginxIngressElbHost=$INGRESS_ELB"