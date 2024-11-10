# Base image
FROM ubuntu:20.04

# Set environment variable to disable interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies for kernel build and Configfix
RUN apt-get update && \
    apt-get install -y \
    pkg-config \
    g++ \
    qtbase5-dev \
    wget \
    build-essential \
    libncurses-dev \
    libssl-dev \
    libelf-dev \
    bc \
    git \
    flex \
    bison

# Clone the Configfix repository and checkout the desired version
RUN wget -O linux.tar.gz https://github.com/delta-one/linux/archive/refs/heads/copy_patch_v6.10.tar.gz && \
    tar -xzf linux.tar.gz && \
    mv linux-copy_patch_v6.10 linux && \
    rm linux.tar.gz

# Download and extract the kernel source code (v6.10)
RUN wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.10.tar.xz -P /home/linux && \
    tar -xvf /home/linux/linux-6.10.tar.xz -C /home/linux



# Make the script executable and run it
RUN  cp -r /linux/scripts/kconfig /home/linux/linux-6.10/scripts

# Create the default kernel configuration
RUN cd /home/linux/linux-6.10 && make defconfig

# Run the configuration interface
#RUN cd /home/linux/linux-6.10 && make cfoutconfig

# Optional: expose an entrypoint to allow further configuration or building
ENTRYPOINT ["/bin/bash"]

