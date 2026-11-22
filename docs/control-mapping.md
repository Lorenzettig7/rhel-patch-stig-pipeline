# Control mapping

How artifacts produced by this pipeline map to NIST SP 800-53 Rev. 5 control families.

Two identifier schemes matter here and they are not interchangeable. **CCE** (Common
Configuration Enumeration, NIST) names a configuration setting; this is what SSG content
ships, and the CCE for every open finding is recorded in
[`exceptions-poam.csv`](exceptions-poam.csv) alongside its DISA STIG ID. **CCI** (Control
Correlation Identifier, DISA) is what maps a STIG check to an 800-53 control — those
references were removed from upstream SSG content in release 0.1.77 and live in DISA's
own STIG XCCDF, so a full CCI-to-800-53 trace requires that content rather than the
scanner output. The mapping below is therefore by artifact, not derived automatically
from identifiers.

| Control | Artifact | Where it lives |
|---|---|---|
| **CM-2** Baseline configuration | Terraform defining the fleet; `scap-security-guide` pinned to the version installed on each host; SSG remediation playbooks vendored into the repo rather than fetched at runtime | `terraform/`, `ansible/remediation/` |
| **CM-3** Configuration change control | Every infrastructure and configuration change is a reviewable diff. `terraform plan` and `ansible-playbook --check --diff` run before apply | `evidence/patch-checkmode.txt`, git history |
| **CM-6** Configuration settings | DISA STIG profile applied via SSG; deviations recorded with justification, compensating control, owner and milestone | `docs/exceptions-poam.csv`, `ansible/evidence/*/` |
| **CM-7** Least functionality | STIG remediation removes unneeded packages and disables unused services | `evidence/stig-remediate-rhel9-canary.txt` |
| **RA-5** Vulnerability monitoring and scanning | Pre- and post-patch advisory counts by severity; OpenSCAP XCCDF results and HTML reports per scan | `ansible/reports/`, `ansible/evidence/` |
| **SI-2** Flaw remediation | `rhel_patch` role: security-only updates, ring rollout, reboot detection, post-patch verification | `ansible/roles/rhel_patch/` |
| **SI-02(07)** Root cause analysis *(added in 800-53 Release 5.2.0, Aug 2025)* | Post-patch verification halts the rollout on failure and still writes a report, so the failing state is captured rather than lost | `ansible/roles/rhel_patch/tasks/verify.yml` |
| **SI-7** Software or information integrity | `gpgcheck=1` enforced on every repository by STIG remediation; package signatures verified at install | STIG rule `ensure_gpgcheck_globally_activated` |
| **IA-5** Authenticator management | GRUB superuser password stored as a PBKDF2 hash in Ansible Vault; the task that writes it uses `no_log`; the vault password file is gitignored | `ansible/roles/grub_hardening/`, `ansible/inventory/group_vars/all/vault.yml` |
| **SC-28** Protection of information at rest | Evidence bucket encrypted with a customer-managed KMS key with rotation enabled; EBS volumes encrypted | `terraform/s3_evidence.tf`, `terraform/fleet.tf` |
| **AU-2 / AU-6** Event logging and audit review | auditd rules applied by STIG remediation; patch and scan runs produce timestamped artifacts per host | `ansible/evidence/`, `ansible/reports/` |
| **AC-6** Least privilege | Security group restricted to a single administrative CIDR; IMDSv2 required; custom RBAC rather than broad roles | `terraform/network.tf`, `terraform/fleet.tf` |
| **CP-9** System backup | Pre-patch EBS snapshot per host, tagged and waited on before patching begins | `ansible/playbooks/tasks/pre_patch_snapshot.yml` |

## Gaps in this mapping

Three controls this pipeline touches but does not yet satisfy to a program standard:

- **CM-2** — the baseline is defined in code but applied post-boot. A golden image built
  by Packer would make the baseline the artifact itself rather than a state converged to
  after launch.
- **CM-3** — changes are reviewable but apply runs from a workstation. A pipeline with an
  approval gate and no long-lived cloud credentials (OIDC) is the production shape.
- **AU-6** — audit records exist per run but are not aggregated. Shipping auditd and run
  logs to a central store is required for review at fleet scale.

## Where this differs from a program environment

The RMF process (NIST SP 800-37) runs Prepare, Categorize, Select, Implement, Assess,
Authorize, Monitor. This pipeline sits in Implement and Monitor. In a DoD program:

- The baseline would be **tailored to the system categorization** and the deviations
  documented once at program level, not per host.
- Findings would be tracked in **eMASS**, reviewed by the ISSO, with residual risk
  accepted by the Authorizing Official.
- Scanning would use **SCC** alongside or instead of OpenSCAP, producing `.ckl`
  checklists as the assessor-facing artifact.
- Content would come from **Satellite content views**, promoted Dev → Test → Prod, with
  export/import across an air gap where required.
