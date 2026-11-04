# syntax=docker/dockerfile:1

# Base image pinned by digest, not just by tag. A tag can be re-pointed at any
# time; a digest can't. Dependabot opens a PR when a newer digest is published.
ARG BASE_IMAGE=python:3.13-slim-trixie@sha256:ae14d4ce8771606477a81446e7ef429edd6762305fc50c84507c1041fa8285d1


# ---------------------------------------------------------------------------
# Stage 1: builder
# Has pip and build tooling. None of it ends up in the final image.
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE} AS builder

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_ROOT_USER_ACTION=ignore

# A venv without pip inside it. We drive the install with the builder's pip,
# so the copied environment carries no package manager into production.
RUN python -m venv --without-pip /opt/venv

# Copy ONLY the lock file first. This layer (and the slow install below) stays
# cached until requirements.txt changes, no matter how often the code changes.
COPY requirements.txt /tmp/requirements.txt

# --mount=type=cache keeps downloaded wheels between builds without baking
# them into a layer. --require-hashes refuses anything that doesn't match the
# lock file, so a tampered or swapped package fails the build.
RUN --mount=type=cache,target=/root/.cache/pip \
    pip --python /opt/venv/bin/python install \
        --require-hashes --no-deps --only-binary=:all: \
        -r /tmp/requirements.txt


# ---------------------------------------------------------------------------
# Stage 2: runtime
# Only what the app needs to run. Every extra binary is attack surface.
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE} AS runtime

LABEL org.opencontainers.image.title="secure-python-api" \
      org.opencontainers.image.description="Hardened, cache-friendly Python container image" \
      org.opencontainers.image.licenses="MIT"

ENV PATH="/opt/venv/bin:${PATH}" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Fixed, high UID/GID so it never collides with a real user on the host and
# Kubernetes runAsUser can match it exactly. No home dir, no login shell.
# pip is removed from the system Python too: nothing at runtime should be
# able to install packages.
RUN groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app \
 && rm -rf /usr/local/lib/python3.13/site-packages/pip* /usr/local/bin/pip*

COPY --from=builder /opt/venv /opt/venv

WORKDIR /app

# Code changes most often, so it goes last: editing main.py only rebuilds
# this one tiny layer. Owned by root and read-only, so the app user can run
# the code but can't modify it.
COPY --chown=root:root --chmod=0555 app/ ./app/

USER 10001:10001

EXPOSE 8000

# No curl/wget in the image, so the health check uses Python itself.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import sys, urllib.request; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=2).status == 200 else 1)"]

# Exec form: uvicorn is PID 1 and receives SIGTERM directly, so
# `docker stop` and Kubernetes rollouts shut it down gracefully.
ENTRYPOINT ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--no-server-header"]
