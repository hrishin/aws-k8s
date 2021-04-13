variable "key_name" {
  default = "cks-key"
}

resource "tls_private_key" "cks" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "cks_key" {
  key_name   = var.key_name
  public_key = tls_private_key.cks.public_key_openssh
  tags = {
    "name" = "cks"
  }
}

resource "random_string" "token_id" {
  length  = 6
  special = false
  upper   = false
}

resource "random_string" "token_secret" {
  length  = 16
  special = false
  upper   = false
}

locals {
  token        = "${random_string.token_id.result}.${random_string.token_secret.result}"
  KUBE_VERSION = "1.20.2"
}

# EIP for master node because it must know its public IP during initialisation
resource "aws_eip" "master" {
  depends_on = [
    aws_internet_gateway.cks
  ]

  vpc = true
  tags = {
    Name = "master"
    kind = "cks"
  }
}

resource "aws_eip_association" "master" {
  allocation_id = aws_eip.master.id
  instance_id   = aws_instance.master.id
}

resource "aws_instance" "master" {
  ami                         = "ami-0244a5621d426859b"
  instance_type               = "t2.medium"
  subnet_id                   = aws_subnet.cks-az-2a.id
  associate_public_ip_address = true
  vpc_security_group_ids = [
    aws_security_group.egress.id,
    aws_security_group.ingress_internal.id,
    aws_security_group.ingress_k8s.id,
    aws_security_group.ingress_ssh.id
  ]
  availability_zone = "eu-west-2a"

  key_name = aws_key_pair.cks_key.key_name

  root_block_device {
    volume_size = 20
  }

  tags = {
    Name = "master"
    kind = "cks"
  }

  user_data = <<-EOF
    #!/bin/bash
    ### setup terminal
    apt-get install -y bash-completion binutils
    echo 'colorscheme ron' >> ~/.vimrc
    echo 'set tabstop=2' >> ~/.vimrc
    echo 'set shiftwidth=2' >> ~/.vimrc
    echo 'set expandtab' >> ~/.vimrc
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    echo 'alias k=kubectl' >> ~/.bashrc
    echo 'alias c=clear' >> ~/.bashrc
    echo 'complete -F __start_kubectl k' >> ~/.bashrc
    sed -i '1s/^/force_color_prompt=yes\n/' ~/.bashrc

    # Install kubeadm and Docker
    apt-get update
    apt-get install -y apt-transport-https curl
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
    echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list
    apt-get update
    apt-get install -y docker.io kubelet=${local.KUBE_VERSION}-00 kubeadm=${local.KUBE_VERSION}-00 kubectl=${local.KUBE_VERSION}-00 kubernetes-cni=0.8.7-00

    mkdir -p /etc/systemd/system/docker.service.d
    systemctl daemon-reload
    systemctl restart docker
    systemctl enable kubelet && systemctl start kubelet

    rm -f /root/.kube/config
    kubeadm reset -f

    # Run kubeadm
    kubeadm init --token "${local.token}" --apiserver-cert-extra-sans "${aws_eip.master.public_ip}" --pod-network-cidr 10.0.1.0/24 --node-name master --ignore-preflight-errors=NumCPU --skip-token-print
    
    mkdir -p /root/.kube
    sudo cp -i /etc/kubernetes/admin.conf /root/.kube/config

    export KUBECONFIG=/etc/kubernetes/admin.conf
    until kubectl version
    do
      sleep 2s
    done

    kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"
  EOF
}

resource "aws_instance" "worker" {
  ami                         = "ami-0244a5621d426859b"
  instance_type               = "t2.small"
  subnet_id                   = aws_subnet.cks-az-2a.id
  associate_public_ip_address = true
  vpc_security_group_ids = [
    aws_security_group.egress.id,
    aws_security_group.ingress_internal.id,
    aws_security_group.ingress_k8s.id,
    aws_security_group.ingress_ssh.id
  ]
  availability_zone = "eu-west-2a"

  key_name = aws_key_pair.cks_key.key_name

  root_block_device {
    volume_size = 20
  }

  tags = {
    Name = "worker"
    kind = "cks"
  }

  user_data = <<-EOF
  #!/bin/bash
  apt-get install -y bash-completion binutils
  echo 'colorscheme ron' >> ~/.vimrc
  echo 'set tabstop=2' >> ~/.vimrc
  echo 'set shiftwidth=2' >> ~/.vimrc
  echo 'set expandtab' >> ~/.vimrc
  echo 'source <(kubectl completion bash)' >> ~/.bashrc
  echo 'alias k=kubectl' >> ~/.bashrc
  echo 'alias c=clear' >> ~/.bashrc
  echo 'complete -F __start_kubectl k' >> ~/.bashrc
  sed -i '1s/^/force_color_prompt=yes\n/' ~/.bashrc
  
  # Install kubeadm and Docker
  apt-get update
  apt-get install -y apt-transport-https curl
  curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
  echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list
  apt-get update
  apt-get install -y docker.io kubelet=${local.KUBE_VERSION}-00 kubeadm=${local.KUBE_VERSION}-00 kubectl=${local.KUBE_VERSION}-00 kubernetes-cni=0.8.7-00

  mkdir -p /etc/systemd/system/docker.service.d
  systemctl daemon-reload
  systemctl restart docker
  systemctl enable kubelet && systemctl start kubelet

  rm -f /root/.kube/config
  kubeadm reset -f

  # Run kubeadm
  kubeadm join ${aws_instance.master.private_ip}:6443 \
    --token ${local.token} \
    --discovery-token-unsafe-skip-ca-verification \
    --node-name worker
  
  # Indicate completion of bootstrapping on this node
  touch /home/ubuntu/done
  EOF
}

resource "local_file" "key-file" {
  content         = tls_private_key.cks.private_key_pem
  file_permission = "0600"
  filename        = "${path.module}/ec2-key.pem"
}

output "master_ip" {
  value = aws_eip.master.public_ip
}

output "worker_ip" {
  value = aws_instance.worker.public_ip
}

