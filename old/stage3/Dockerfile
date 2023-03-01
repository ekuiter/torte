FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --allow-unauthenticated \
    default-jre \
    libgmpxx4ldbl \
    libmpfr6 \
    lib32z1 \
    bc \
    dos2unix \
    # ugly hack required for sharpsat-td
    && ln -s /usr/lib/x86_64-linux-gnu/libmpfr.so.6 /usr/lib/x86_64-linux-gnu/libmpfr.so.4
WORKDIR /home
COPY ./ ./
RUN find . -type f -name "*.sh" -exec bash -c "chmod +x {} && dos2unix {}" \;