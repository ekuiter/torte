FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    default-jre \
    libgmpxx4ldbl \
    libmpfr6 \
    lib32z1 \
    # ugly hack required for sharpsat-td
    && ln -s /usr/lib/x86_64-linux-gnu/libmpfr.so.6 /usr/lib/x86_64-linux-gnu/libmpfr.so.4
WORKDIR /home
COPY ./ ./