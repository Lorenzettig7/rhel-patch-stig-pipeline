# RHEL Patch & STIG Compliance Pipeline

Automated OS patching and DISA STIG hardening for a mixed RHEL 8 / RHEL 9 fleet on AWS,
where the compliance evidence is produced by the pipeline rather than assembled by hand.

Built as a working reference for DevSecOps patch operations: ring-based rollout, reboot
detection, post-patch verification, SCAP scanning before and after, and a POA&M-style
exceptions register for every finding left open.

---

## Results

### Patching

| Metric | Value |
|---|---|
| Security advisories pending at baseline | 350 (RHEL 9.4), 358 (RHEL 8.8) |
| Critical advisories | 2 (RHEL 9), 4 (RHEL 8) |
| Advisories remaining after patch run | 0 on all four hosts |
| Kernel, RHEL 9 | `5.14.0-427.126.1.el9_4` → `5.14.0-741.24.1.el9_9` |
| Kernel, RHEL 8 | `4.18.0-477.97.1.el8_8` → `4.18.0-553.187.1.el8_10` |
| Fleet patch window | 61 min for 4 hosts, of which **42 min was EBS snapshots** |
| Patch time per host | ~8 min |

### STIG compliance (rhel9-canary)

| Stage | Score | Failures | CAT I open |
|---|---|---|---|
| Baseline, stock AMI | 46.3% | 256 | 5 |
| After SSG STIG remediation | 95.4% | 24 | 5 |
| After custom GRUB remediation | **96.0%** | **22** | **3** |
| After patching the hardened host | 96.0% | 22 | 3 |

**No configuration drift from patching.** A hardened host was patched through 350
advisories including a kernel update and reboot. The post-patch scan returned the
identical finding set. This was one cycle on one host — the scan still belongs after
every patch window, because a package update can replace a file SSG owns.

---

## Architecture

```
Terraform ──> VPC, 4 EC2 hosts (RHEL 8.8 + 9.4), KMS, versioned S3 evidence bucket
                 │  tagged PatchRing=canary|ring1, OS=rhel8|rhel9
                 ▼
Ansible dynamic inventory (amazon.aws.aws_ec2)
   groups derived from EC2 tags: ring_canary, ring_ring1, os_rhel8, os_rhel9
                 │
    ┌────────────┼────────────────────┐
    ▼            ▼                    ▼
rhel_patch   SSG STIG playbook   grub_hardening
 role         (vendored)          role (custom)
    │            │                    │
    └────────────┴────────────────────┘
                 ▼
         OpenSCAP evaluation ──> XCCDF results + HTML report
                 ▼
         docs/exceptions-poam.csv   docs/control-mapping.md
```

**Patch rings are modelled in the inventory, not the playbook.** EC2 tags drive group
membership, so the rollout strategy is a property of the fleet rather than something
hard-coded. Adding a host to a ring is a tag change.

---

## Design decisions

**Pay-as-you-go RHEL AMIs with RHUI, not BYOS.** Removes subscription registration as a
failure mode. RHUI stands in for what Satellite does in a program environment, and the
substitution is called out rather than hidden.

**Security-only patching by default.** `patch_security_only: true`, with `patch_exclude`
available for kernel holds. Full updates are a deliberate opt-in.

**Reboot only when required.** `dnf needs-restarting -r` returns 1 when a reboot is
needed; the role reboots on that signal rather than unconditionally, then verifies the
running kernel matches the newest installed.

**Canary ring at `serial: 1`, then 50% batches, `max_fail_percentage: 0`.** One failure
stops the rollout before the next batch starts. `any_errors_fatal` on the canary play
aborts the whole run before ring1 is touched.

**Pre-patch EBS snapshot per host**, togglable via `patch_snapshot_enabled` and the
`snapshot` tag, so snapshots can run as a standalone pre-window job.

**SSG-generated remediation over hand-written tasks.** The `scap-security-guide` package
ships Ansible playbooks tagged by rule ID and STIG ID, maintained jointly with DISA, and
idempotent since SSG 0.1.79. The tradeoff is less control over individual tasks.

**One exceptions list, no scanner tailoring.** Rules that are skipped during remediation
are left visible as failures in the scan. A tailored 100% would hide them. 96% with 22
documented exceptions is the more honest artifact and the one an assessor can audit.

**Secrets through Ansible Vault.** The GRUB password hash lives in an encrypted vault
file; the vault password file is gitignored. The task that writes it uses `no_log`.

**In-place patching for long-lived hosts, image replacement for everything rebuildable.**
Immutable golden images suit stateless autoscaled tiers. In-place suits stateful,
long-lived, or air-gapped systems, which is where most RHEL in defence actually sits. A
mature program does both.

---

## Findings left open

All 22 remaining findings trace to five root causes. Full detail in
[`docs/exceptions-poam.csv`](docs/exceptions-poam.csv).

| Root cause | Findings | Why open | Where it gets fixed |
|---|---|---|---|
| FIPS | 8 (3 CAT I) | FIPS must be enabled at install time. Red Hat's own tooling reports that `update-crypto-policies --set FIPS` is not sufficient for compliance, and `fips-mode-setup` is deprecated on RHEL 9 for converting a running system. The SSH cipher and MAC findings are all downstream of the crypto policy. | `fips=1` in the image build |
| Partitioning | 6 | Marketplace AMI provisions a single root filesystem; separate partitions cannot be created on a running host without destructive repartitioning. | Partition layout in the Packer build |
| Automation access | 2 | Passwordless sudo is what the Ansible account depends on. Applying the rule removes `become` and breaks the pipeline that enforces every other control. | Dedicated automation account with a vaulted become password under AAP |
| Site-specific values | 5 | SSG ships no remediation — authorized user list, DNS servers, PKI certificate mapping are organisation-defined. | Populated from the program SSP |
| Container conflict | 1 | Disabling user namespaces breaks rootless containers. SSG marks the rule `no_remediation`. A genuine conflict between the STIG and the platform's container runtime. | AO risk acceptance, or migrate the workload |

**There is no passing percentage.** An ATO decision turns on whether every finding is
remediated or documented with a justification, compensating control, owner and milestone —
not on a score. A host at 80% with a complete POA&M is in better standing than one at 98%
with undocumented gaps. The DISA SCAP benchmark also only automates part of each STIG, so
a scan score never covers the whole requirement set.

---

## Limitations

- **Four hosts, not four hundred.** The ring design is correct but untested at scale.
  At scale you would hit SSH fan-out limits (`forks`, pipelining, `strategy: free`) and
  repository bandwidth before you hit anything else.
- **Snapshots consumed 69% of the patch window.** Measured, not estimated. In production
  the snapshot is a separate pre-window job, or you rely on AMI-level backup.
- **`serial: "50%"` can leave a partial state.** If a host fails mid-batch, its peer can
  be left updated but not rebooted. The snapshot covers rollback; the partial state is real.
- **Hardening runs post-boot.** There is a window between instance launch and remediation
  where the host is non-compliant. An image pipeline removes it.
- **Content comes from RHUI, which always serves current.** A routine security patch run
  moved RHEL 9.4 to 9.9 and RHEL 8.8 to 8.10. In a program with an application support
  matrix, that is what Satellite content views or EUS repos exist to prevent.
- **Evidence is OpenSCAP XCCDF and HTML, not `.ckl`.** Assessors expect STIG Viewer
  checklists, typically produced by DISA's SCC.
- **Idempotency of `rhel_patch` is asserted by design** (`changed_when: false` on every
  read-only task) **but not yet proven by a second full run against the fleet.**
- **Images built locally are arm64.** CI builds amd64; multi-arch via `docker buildx`
  is not implemented.

---

## What I would do next

1. **Packer golden image** — bakes in the hardening and closes the FIPS and partition
   findings at build time, which is 14 of the 22 open items.
2. **Satellite content views** — pin a dated package set per lifecycle environment so
   Dev, Test and Prod receive byte-identical content, and support air-gapped import.
3. **AWX / AAP** — scheduling, RBAC, credential vaulting, and job logs that double as
   audit evidence.
4. **SSM instead of SSH** — removes inbound 22 entirely.
5. **SCC scanning and `.ckl` export** — assessor-grade artifacts alongside OpenSCAP.
6. **Scheduled re-hardening** — a `grub2-tools` update restores the stock `01_users`.
   Configuration drifts back whenever a package updates a file it owns, which is the
   continuous-monitoring case in one sentence.
7. **Molecule and CI gates** — lint, idempotency test, check-mode run, then apply behind
   an approval.

---

## Repository layout

```
terraform/           VPC, fleet, KMS, S3 evidence bucket
ansible/
  inventory/         aws_ec2 dynamic inventory, group_vars (incl. vault)
  roles/rhel_patch/  precheck → patch → reboot → verify → report
  roles/grub_hardening/  custom remediation SSG does not ship
  playbooks/         patch.yml, stig_scan.yml, harden_grub.yml
  remediation/       vendored SSG STIG playbooks (version-pinned)
  evidence/          fetched XCCDF results and HTML reports per scan
  reports/           per-host patch reports
docs/
  exceptions-poam.csv    22 findings with justification and milestone
  control-mapping.md     artifacts mapped to NIST 800-53 controls
evidence/            run logs
```

---

## Running it

```bash
# Infrastructure
cd terraform
terraform apply -var "my_ip_cidr=$(curl -s https://checkip.amazonaws.com)/32"

# Patch, canary ring first
cd ../ansible
ansible-playbook playbooks/patch.yml

# Baseline scan, harden, rescan
ansible-playbook playbooks/stig_scan.yml -e scan_label=baseline
ansible-playbook remediation/rhel9-playbook-stig.yml -l os_rhel9 --become \
  --skip-tags "sudo_remove_nopasswd,sudo_remove_no_authenticate,sudo_require_reauthentication,disallow_bypass_password_sudo,fips_custom_stig_sub_policy,configure_crypto_policy"
ansible-playbook playbooks/harden_grub.yml
ansible-playbook playbooks/stig_scan.yml -e scan_label=hardened
```

### Environment

| Component | Version |
|---|---|
| SCAP Security Guide | 0.1.82 |
| SCAP profile | `xccdf_org.ssgproject.content_profile_stig` |
| OpenSCAP | 1.3.14 |
| Terraform | 1.6+, AWS provider ~> 5.0 |

STIG benchmark versions are whatever ships with the `scap-security-guide` package
installed on each host. Confirm with `oscap info` rather than trusting a figure quoted
anywhere, including here.
