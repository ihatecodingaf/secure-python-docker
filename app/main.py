"""A deliberately small API. The point of this repo is the container, not the app."""

import os
import platform

from fastapi import FastAPI

app = FastAPI(title="secure-python-api", docs_url=None, redoc_url=None)


@app.get("/")
def root() -> dict:
    return {
        "service": "secure-python-api",
        "python": platform.python_version(),
        # Handy when you want to prove the container is not running as root.
        "uid": os.getuid(),
    }


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "ok"}
