
# Use Ubuntu as the base image
FROM ubuntu:20.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    git \
    pkg-config \
    g++ \
    qtbase5-dev \
    wget \
    make \
    curl \
    libncurses5-dev \
    libssl-dev \
    bc \
    && apt-get clean

# Set the working directory
WORKDIR /home

# Alternative to git clone: Download the repository as a tar.gz file and extract it
RUN wget -O linux.tar.gz https://github.com/delta-one/linux/archive/refs/heads/copy_patch_v6.10.tar.gz && \
    tar -xzf linux.tar.gz && \
    mv linux-copy_patch_v6.10 linux && \
    rm linux.tar.gz


# Copy the Configfix files into the kernel directory
COPY ./copyfiles.sh /home/linux/
RUN cd /home/linux && \
    ./copyfiles.sh /home/linux-6.10

# Create default kernel configuration
RUN cd /home/linux-6.10 && \
    make defconfig

# Run xconfig (optional, if a GUI is available or needed)
# RUN cd /home/linux-6.10 && \
#     make xconfig

# Export constraints to DIMACS format by running make cfoutconfig
RUN cd /home/linux-6.10 && \
    make cfoutconfig


