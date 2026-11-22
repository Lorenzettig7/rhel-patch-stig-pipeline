import glob, gzip, re, csv, sys, xml.etree.ElementTree as ET
NS = '{http://checklists.nist.gov/xccdf/1.2}'

SOURCES = [
    ("RHEL 9", "rhel9-canary", "ansible/evidence/post_patch_hardened/**/*results.xml*"),
    ("RHEL 8", "rhel8-canary", "ansible/evidence/rhel8_hardened3/**/*results.xml*"),
]

GROUPS = [
 (re.compile(r'^(fips_|sysctl_crypto_fips|configure_crypto_policy|harden_sshd_(ciphers|macs))'), 'FIPS',
  "FIPS must be enabled at install time. Red Hat tooling reports that 'update-crypto-policies --set FIPS' is not sufficient for FIPS compliance, and fips-mode-setup is deprecated on RHEL 9 for converting an existing system. SSH cipher and MAC findings are downstream of the crypto policy.",
  "System-wide crypto policy at DEFAULT; SSH key-based authentication only; host reachable from a single administrative CIDR.",
  "Enable fips=1 in the image build (kickstart)"),
 (re.compile(r'(^partition_for_|home_directory_on_separate_partition)'), 'PARTITION',
  "Marketplace AMI provisions a single root filesystem. Separate partitions cannot be created on a running host without destructive repartitioning.",
  "Disk utilisation monitored; auditd space_left_action configured; log rotation enforced.",
  "Define partition layout in the Packer image build"),
 (re.compile(r'^sudo_'), 'AUTOMATION',
  "Passwordless sudo is required by the Ansible automation account. Applying this rule removes become capability and breaks the patch and compliance pipeline that enforces every other control.",
  "Automation account is key-only, restricted to one source CIDR; all sudo invocations logged to auditd.",
  "Dedicated automation account with vaulted become password under AAP"),
 (re.compile(r'^sysctl_user_max_user_namespaces'), 'CONTAINER_CONFLICT',
  "Disabling user namespaces breaks rootless container workloads on this platform. SSG marks this rule no_remediation. Direct conflict between the STIG requirement and the container runtime.",
  "Containers run non-root with dropped capabilities and read-only root filesystems under Pod Security Standards restricted.",
  "AO risk acceptance, or migrate affected workloads"),
 (re.compile(r'.*'), 'SITE_SPECIFIC',
  "SSG ships no automated remediation; the required values are organisation-defined (authorized user list, DNS servers, firewall zone, PKI certificate mapping).",
  "Values supplied from the program system security plan at onboarding.",
  "Populate from program SSP"),
]

def load(p):
    return ET.parse(gzip.open(p) if p.endswith('.gz') else p)

w = csv.writer(sys.stdout)
w.writerow(['os','host','rule_id','stig_id','cce','severity','title','root_cause',
            'status','justification','compensating_control','owner','milestone'])

total = 0
for osname, host, pattern in SOURCES:
    files = glob.glob(pattern, recursive=True)
    if not files:
        print(f"MISSING: {pattern}", file=sys.stderr); continue
    t = load(files[0])
    meta = {}
    for r in t.iter(NS+'Rule'):
        rid = r.get('id').split('_rule_')[-1]
        stig = ''
        for ref in r.findall(NS+'reference'):
            m = re.search(r'RHEL-\d\d-\d+', (ref.text or ''))
            if m: stig = m.group(0); break
        # SSG ships CCE identifiers (NIST Common Configuration Enumeration).
        # CCIs (DISA Control Correlation Identifiers, which map to 800-53) were
        # removed from upstream SSG content in 0.1.77; they live in DISA's STIG XCCDF.
        cces = [i.text for i in r.findall(NS+'ident') if (i.text or '').startswith('CCE-')]
        meta[rid] = (stig, ';'.join(cces[:2]), (r.find(NS+'title').text or '').strip(), r.get('severity',''))
    n = 0
    for rr in t.iter(NS+'rule-result'):
        if rr.find(NS+'result').text != 'fail': continue
        rid = rr.get('idref').split('_rule_')[-1]
        stig, cce, title, sev = meta.get(rid, ('','','',rr.get('severity','')))
        for pat, cause, just, comp, mile in GROUPS:
            if pat.search(rid):
                w.writerow([osname, host, rid, stig, cce, sev, title, cause,
                            'Open - accepted', just, comp, 'ISSO', mile])
                n += 1; break
    print(f"{osname}: {n} findings", file=sys.stderr)
    total += n
print(f"total: {total}", file=sys.stderr)
