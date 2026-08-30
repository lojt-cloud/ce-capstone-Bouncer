## Network design

## **VPC and subnet layout.**
A dedicated VPC (`10.0.0.0/16`) spans 3 AZs in
`eu-central-1` (`eu-central-1a/b/c`), chosen to match the ASG's minimum of
3 instances. One AZ per instance at minimum scale. Each AZ gets one
public subnet (`/24`, ALB and NAT Gateway) and one private subnet (`/24`,
app instances, RDS, ElastiCache). The CIDR avoids overlapping the
account's default VPC (`172.31.0.0/16`) in `eu-central-1`, in case of
future peering or VPC endpoints.

## **NAT Gateway.** 
A single shared NAT Gateway (in the first public subnet)
serves egress for all 3 private subnets, rather than one per AZ. 
Deliberate cost trade-off: 3 NAT Gateways would triple the ~$0.052/hour charge for
redundancy this capstone doesn't need. It's a single point of failure for
outbound internet access only. Inbound availability (ALB, app instances)
stays multi-AZ. Acceptable for a non-production workload. Gated behind
`enable_billable_resources` in `terraform/environments/dev/foundation` so
it can be torn down between work sessions and recreated for demos.

## **Terraform state architecture**

Each infrastructure layer (foundation, compute, data-tier, ...) is its own
Terraform root under `terraform/environments/dev/<layer>/`, with its own
state file, calling shared module definitions in `terraform/modules/<name>/`.

Cross-layer references go through `terraform_remote_state` only, and only
in one direction: a later layer can read an earlier layer's outputs, never
the reverse. Foundation doesn't know compute exists.

The root `terraform/main.tf` is intentionally empty — it exists only to
satisfy the project rubric's required file structure. It is not a real
entry point; each layer is applied independently from its own directory.

This trades a small amount of duplicated boilerplate (provider/backend
blocks per layer) for blast-radius containment at the state level: a
broken `terraform apply` in one layer can't corrupt another layer's state,
and layers can be planned/applied independently instead of one shared
`terraform apply` touching everything.

## **CI/CD pipeline architecture**

`terraform-plan.yml` runs on every PR touching `terraform/` and has two jobs:

- `lint-and-scan`: `terraform fmt -check`, then Checkov against the whole
  `terraform/` tree using `.checkov.yaml`. This gates the plan job.
- `plan`: runs `terraform plan` per layer using a matrix strategy
  (`matrix.layer: [foundation]`, one entry added per layer as it's built),
  scoped to that layer's directory, with results posted back as a PR
  comment.

Auth is GitHub OIDC: no long-lived AWS keys in CI. All layers currently
authenticate through one shared deploy role
(`ce-capstone-bouncer-deploy`), with each layer attaching its own scoped
IAM policy to that same role rather than getting a separate role. See
SECURITY.md for what that implies for credential blast radius.

Still open: `terraform-apply.yml` (merge-triggered apply), scheduled
drift detection, and wiring branch protection's required status check to
the plan job.