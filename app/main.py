"""Minimal demo API for the image-layer patching pipeline."""

import os

from fastapi import FastAPI

app = FastAPI(title="demo-api")


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/version")
def version() -> dict[str, str]:
    # The digest isn't known until after the image is pushed, so it is injected
    # at deploy time (e.g. from the pinned image@sha256 reference).
    return {"image_digest": os.environ.get("IMAGE_DIGEST", "unknown")}
