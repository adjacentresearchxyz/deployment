# Deployment 

Deployment of `NixOS` via `terraform` with monitoring and log collection

## Authenticating 
- Login to `aws-cli` 
- Symlink it to your deployment repository
- Install a `.pem` file for aws deployments
    - The key name that you used here in the AWS console will be used in the `aws_instance.machine.key_name`

## Layout
```
├── *.auto.tfvars
├── README.md
├── id_rsa.pem
├── main.tf
├── nixos
│   ├── README.md
│   ├── configuration.nix
│   ├── flake.lock
│   ├── flake.nix
│   ├── grafana
│   │   ├── dashboards
│   │   │   ├── logging.json
│   │   │   └── node_exporter.json
│   │   └── grafanaDatasources.yml
│   ├── home.nix
│   └── promtail.yaml
└── variables
    └── base.tfvars
```

- Terraform is used for deploying to various cloud environment
    - Terraform `.tfvars` files specified in the `./variables` directory for different configurations
- NixOS configurations deployed for deployment of identical systems 
    - Includes deployment and management of default services
        - `fail2ban` for basic DDOS protection
        - `grafana` with system monitoring dashboards
        - `loki` for system log collection 
        - `prometheus` for system statistics collection

## Deploying 
```
# copy `variables/base.tfvars`
cp ./variables/base.tfvars *.auto.tfvars

# enter the variables you want to deploy with into `*.auto.tfvars`
# note this is were you enter your AWS keys

# plan and then apply the configuration
terraform plan
terraform apply
```

## Future Improvements
- [ ] Docker dashboard and monitoring via `caadvvisor` 
- [ ] `configuration.nix` via `.env` file
- [ ] Automatically add new machine into a teleport instance
- [ ] Add `google cloud`, `ibm cloud`, `digital ocean` deploys
- [ ] Add alerts via Telegram into the default monitoring dashboards