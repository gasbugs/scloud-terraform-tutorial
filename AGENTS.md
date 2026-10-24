# Repository Guidelines

## Project Structure & Module Organization

Root-level `*.tf` files define the Samsung Cloud Platform SSH VM stack: `network.tf` and `compute.tf` create resources, `variables.tf` defines inputs, and `outputs.tf` exposes connection details. Start local inputs from `terraform.tfvars.example`. `scripts/` contains the SCP CLI to Terraform credential sync helper. `labs/ynat-full-finetune/` contains Python training code, Dockerfiles, and its own shell helpers. Root `SCLOUD_*_TUTORIAL.md` files document the related hands-on workflows. There is no dedicated test or asset directory; generated lab bundles and evidence stay local.

## Build, Test, and Development Commands

- `cp terraform.tfvars.example terraform.tfvars` — create local inputs; set your own zone, image ID, and SSH `/32` address.
- `./scripts/sync-scp-cli-terraform-config.sh` — copy configured `scp-cli` credentials into the provider's expected files under `~/.scpconf`.
- `terraform init` — install the locked providers. This repository requires Terraform 1.13 through 1.x.
- `terraform fmt -check && terraform validate` — check HCL formatting and configuration before review.
- `terraform plan -out=tfplan` — inspect proposed cloud changes. Apply a reviewed plan with `terraform apply tfplan`; this creates billable resources.

## Coding Style & Naming Conventions

Use `terraform fmt` for HCL layout and `snake_case` for variables and local resource names. Python lab code uses four-space indentation and `snake_case` functions and files. Bash helpers use `.sh` filenames, `set -euo pipefail`, and quoted variable expansions. Keep examples and commands consistent with the relevant tutorial.

## Testing Guidelines

There is no test framework or coverage threshold. Run `terraform fmt -check` and `terraform validate` for Terraform changes. Run `PYTHONDONTWRITEBYTECODE=1 python3 labs/ynat-full-finetune/check_offline.py` for Python syntax and small offline assertions; it does not test Docker, downloads, GPU training, or SCP. Check edited shell scripts with `bash -n path/to/script.sh`. Record any live cloud checks separately from local checks.

## Commit & Pull Request Guidelines

Recent commits use concise imperative subjects, such as `Align training runtime and upload code`; a `docs:` prefix also appears, but is not required. In a pull request, summarize changed resources or tutorial steps, include validation commands and results, and link a relevant issue when one exists. Include screenshots only when they clarify a visual documentation change.

## Security & Configuration

Never commit credentials, `terraform.tfvars`, Terraform state or plans, PEM keys, or lab data and evidence. Keep SCP credentials in the documented local config files, and restrict inbound SSH to one public IPv4 `/32`.
