How to run a container (e.g. based on public nginx image from Docker Hub) in AWS Fargate

    export AWS_PROFILE=test

    terraform init

    terraform workspace new test1
    terraform apply -auto-approve

    sleep 40
    curl -v http://$(terraform output loadbalancer_dns_name)/

    terraform workspace new test2
    terraform apply -auto-approve

    sleep 40
    curl -v http://$(terraform output loadbalancer_dns_name)/

    terraform destroy -auto-approve

    terraform workspace select test1

    terraform destroy -auto-approve
