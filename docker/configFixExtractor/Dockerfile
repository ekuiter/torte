# Use Ubuntu as the base image
FROM ubuntu:20.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install necessary dependencies, including CA certificates
RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    g++ \
    qtbase5-dev \
    git \
    wget \
    xz-utils \
    build-essential \
    ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Set the working directory
WORKDIR /home

# Alternative to git clone: Download the repository as a tar.gz file and extract it
RUN wget -O linux.tar.gz https://github.com/delta-one/linux/archive/refs/heads/copy_patch_v6.10.tar.gz && \
    tar -xzf linux.tar.gz && \
    mv linux-copy_patch_v6.10 linux && \
    rm linux.tar.gz


