# Container layer

The VM fleet is patched in place by `rhel_patch`. Containers are patched differently:
the fix goes into the **image**, and the running container is replaced, never updated.

| Piece | Where |
|---|---|
| FastAPI service (`/healthz`, `/version`) | `app/main.py`, `app/requirements.txt` |
| Image definition | `app/Containerfile` |
| Build → scan → SBOM → push → sign → attest | `.github/workflows/image.yml` |

## Why patching means rebuild and redeploy

`microdnf update` runs in the Containerfile, so every build picks up the current
errata for the base layer. Running `microdnf update` inside a live pod would also
apply the fix, but then nothing in Git describes what is actually running: the image
digest in the deployment manifest, its SBOM and its scan results all describe the
unpatched image, and the change is lost the next time the pod restarts. Rebuilding
keeps one chain of evidence: commit → image digest → Trivy result → SBOM →
signature. To patch, you rebuild (or let the next commit rebuild) and roll out the
new digest.

The Trivy gate fails the build on any CRITICAL or HIGH finding that has a fix
available. Findings with no fix yet are reported but don't block, because no rebuild
could resolve them.

## Why images are signed by digest

A tag like `demo-api:<sha>` is a mutable pointer: anyone with push access can move it
to different content. A digest (`@sha256:…`) is the content hash of the manifest
itself. Signing the tag would only prove the tag pointed at *something* signed at
some point. Signing the digest binds the signature, and the SPDX SBOM attestation,
to exactly those bytes. The signing is keyless: cosign uses the workflow's GitHub
OIDC identity, and the certificate is logged in Sigstore's Rekor transparency log.
To check an image yourself:

```sh
cosign verify ghcr.io/lorenzettig7/rhel-patch-stig-pipeline/demo-api@sha256:<digest> \
  --certificate-identity https://github.com/Lorenzettig7/rhel-patch-stig-pipeline/.github/workflows/image.yml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

`IMAGE_DIGEST` (shown by `/version`) is set at deploy time from that same digest
reference. An image can't contain its own digest.

## What Iron Bank would change

The Containerfile follows the Iron Bank convention (`BASE_REGISTRY` / `BASE_IMAGE` /
`BASE_TAG`), so moving to a hardened base is a build-argument change, not a rewrite:

- **`BASE_REGISTRY=registry1.dso.mil`**, with `BASE_IMAGE=ironbank/redhat/ubi/ubi9-minimal`
  and a pinned `BASE_TAG`. Pulling from Registry1 requires a Platform One account and
  credentials in CI.
- **Continuous scanning upstream.** Iron Bank rescans its images continuously and
  publishes findings and justifications. This pipeline's Trivy gate then becomes a
  second check, not the only one.
- **The hardened UBI9 base** that DISA's *Container Hardening Process Guide*
  recommends building on, in place of the stock `registry.access.redhat.com` UBI.
  STIG-relevant configuration is already applied upstream before your layers go on.

## Architecture: arm64 locally, amd64 in CI

A `docker build` on Apple Silicon produces an **arm64** image. The GitHub-hosted
runner produces **amd64**. Their digests, package builds and sometimes their scan
results differ, so a local scan doesn't prove the CI image is clean. The next step is
`docker buildx build --platform linux/amd64,linux/arm64`, which pushes a multi-arch
index, then signs and attests that index digest.
