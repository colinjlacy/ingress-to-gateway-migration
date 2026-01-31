#!/bin/bash

# cd to the directory where the OpenTofu script is located
cd tofu-eks

# ensure the plan runs successfully
echo "Planning to create a new EKS cluster"
tofu init
tofu plan --out plan

# apply the plan
echo "Applying the plan to create the EKS cluster"
tofu apply plan

# check if the apply was successful
if [ $? -ne 0 ]; then
  echo "Error: OpenTofu apply failed"
  exit 1
fi

# store the cluster name and AWS Load Balancer Controller IAM role ARN
export EKS_CLUSTER=$(tofu output -raw cluster_name)
export AWS_LBC_ROLE_ARN=$(tofu output -raw aws_load_balancer_controller_role_arn)

# change to the directory where the K8s configs are located
cd ../

# Create a new context for the service account
echo "Creating a new context in the default kubeconfig file"
aws eks --region us-east-2 update-kubeconfig --alias east-cluster --name $EKS_CLUSTER

# Set the default storage class
echo "Setting the default storage class"
kubectl patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Create Kubernetes service account for AWS Load Balancer Controller with IRSA annotation
echo "Creating Kubernetes service account for AWS Load Balancer Controller"
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: ${AWS_LBC_ROLE_ARN}
EOF

# Install the AWS Load Balancer Controller
echo "Installing the AWS Load Balancer Controller"
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$EKS_CLUSTER \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

# wait for the AWS Load Balancer Controller to be ready
echo "Waiting for the AWS Load Balancer Controller to be ready"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=aws-load-balancer-controller -n kube-system --timeout=120s
