FROM ubuntu:22.04

# install git and other utilities used in scripts
RUN apt-get update && apt-get install -y \
    git \
    cloc \
    curl \
    wget \
    ruby-dev \
    build-essential \
    parallel
RUN gem install youplot

WORKDIR /home
RUN git config --global --add safe.directory '*' \
    && git config --global user.email "anon@example.com" \
    && git config --global user.name "anon"