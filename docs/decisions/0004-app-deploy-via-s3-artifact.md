# ADR 0004: App code deploys via S3 artifact + instance refresh

## Status
Accepted

## Context
The compute module needed a way to get Flask app code onto EC2 instances,
and a way to redeploy it later without necessarily re-running Terraform.
Two options: bake the app source into the launch template's user_data via
Terraform templatefile (zero new AWS resources, but couples every app-only
change to a Terraform apply and a new launch template version), or package
app/src as a zip in a private S3 bucket, have user_data pull it on boot,
and have a standalone deploy.sh script re-upload + trigger an ASG instance
refresh independent of Terraform state.

## Decision
S3 artifact + instance refresh. Terraform creates and owns the bucket
(versioned, SSE-S3, public access blocked, lifecycle rule); the *initial*
artifact is uploaded by Terraform itself via the archive_file + s3_object
resources, so a fresh `terraform apply` always produces a bootable ASG.
`app/deploy.sh` handles all subsequent app-only deploys independently.

## Consequences
- App releases don't require a Terraform apply, matching how a real CI/CD
  deploy step would eventually work.
- One extra AWS resource (S3 bucket) and its own IAM read policy on the
  app role, versus the zero-new-resources alternative.
- Bootstrap ordering matters: the very first launch depends on Terraform
  having already uploaded app.zip, which it does via the archive_file
  data source at apply time.