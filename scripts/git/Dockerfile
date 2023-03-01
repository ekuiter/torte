FROM ubuntu:22.04

# install git and other utilities used in scripts
RUN apt-get update && apt-get install -y \
    git \
    cloc \
    curl \
    wget

WORKDIR /home
COPY *.sh git/*.sh ./
RUN chmod +x *.sh \
    && git config --global --add safe.directory '*' \
    && git config --global user.email "anon@example.com" \
    && git config --global user.name "anon"