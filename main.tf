terraform {
  required_version = ">= 1.3"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.26.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}
data "aws_vpc" "default" { // Fetch default VPC
  default = true
}
variable "cluster_name" { // Variable for cluster name
  type    = string
  default = "my-cluster-via-jenkins"

}

data "aws_subnets" "default" { // Fetch  all subnets in the default VPC
  filter {
    name   = "vpc-id"  //   Filter by VPC ID
    values = [data.aws_vpc.default.id]  // Filter by default VPC ID
  }
}

resource "aws_iam_role" "eks_cluster_role" { // IAM role for EKS cluster
  name = "eks-cluster-role"   // Name of the cluster role

  assume_role_policy = jsonencode({ // Assume role policy
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {  // Attach EKS cluster policy to the role
  role       = aws_iam_role.eks_cluster_role.name // Cluster role name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}           // Attach EKS cluster policy to the role    


resource "aws_iam_role" "node_role" { // IAM role for EKS worker nodes
  name = "eks-node-role" // Name of the node role

  assume_role_policy = jsonencode({ // Assume role policy
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_policies" { // Attach necessary policies to the node role
  count = 3         // Three policies to attach 
  role  = aws_iam_role.node_role.name // Node role name

  policy_arn = element([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  ], count.index)
}

resource "aws_eks_cluster" "mycluster" { // EKS Cluster resource
  name     = var.cluster_name   // Cluster name
  role_arn = aws_iam_role.eks_cluster_role.arn // IAM role for the cluster

  vpc_config {
    subnet_ids = data.aws_subnets.default.ids // Use all subnets in the default VPC
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy   // Ensure the cluster role policy is attached before creating the cluster
  ]
}


resource "aws_eks_node_group" "nodegroup" { // EKS Node Group resource
  cluster_name    = aws_eks_cluster.mycluster.name
  node_group_name = "default-node-group" // Name of the node group
  node_role_arn   = aws_iam_role.node_role.arn // IAM role for the node group
  subnet_ids      = data.aws_subnets.default.ids  // Use all subnets in the default VPC

  instance_types = ["c7i-flex.large"]  // Instance type for the worker nodes

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 3
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_policies   // Ensure node role policies are attached before creating the node group
  ]
}

output "cluster_name" { // Output for cluster name
  value = aws_eks_cluster.mycluster.name 
}

output "cluster_endpoint" {    //  Output for cluster endpoint
  value = aws_eks_cluster.mycluster.endpoint
}




#############################
jenkinsfile using parameters apply and destroy 


pipeline {
    agent any
    tools {
        terraform 'terraform' // Name of the Terraform installation in Jenkins
    }
    environment {
        AWS_ACCESS_KEY_ID = credentials('aws-id')
        AWS_SECRET_ACCESS_KEY = credentials('aws-key')
        AWS_DEFAULT_REGION = 'us-west-2' 
    }

    parameters {
        choice(name: 'ACTION', choices: ['apply', 'destroy'], description: 'Select the Terraform action to perform')
    }
    
    stages {
        stage('Checkout tf Code') {
            steps {
               git branch: 'main', url: 'https://github.com/mayur-z/tf-infra-jnkins.git' //main.tf file location
            }
        }
        
        stage('init tf') {
            steps {
               // withAWS(credentials: 'my-aws-key-id', region: 'us-west-2') {
                sh 'terraform init'
               // }
            }
        }
        
        stage('validate tf') {
            steps {
             //   withAWS(credentials: 'my-aws-key-id', region: 'us-west-2') {
                sh 'terraform validate'
               // }
            }
        }

        stage('plan tf') {
            steps {
            //    withAWS(credentials: 'my-aws-key-id', region: 'us-west-2') {
                sh 'terraform plan -out=tfplan'
              //  }                
            }
        }

        stage('apply/destroy tf') {
            steps { 
                script {
                    if (params.ACTION == 'apply') {
                        // Apply the pre-generated plan. The --auto-approve flag is necessary for automation.
                        sh 'terraform apply -auto-approve tfplan'
                    } else if (params.ACTION == 'destroy') {
                        // Destroy all resources managed by the configuration. The -auto-approve flag is used for automation.
                        sh 'terraform destroy -auto-approve'
                    }
                }
            }
        }
        
        stage('tf output') {
            steps {                
                //withAWS(credentials: 'my-aws-key-id', region: 'us-west-2') {
                sh 'terraform output'
                //}
            }
        }        
    }
}
