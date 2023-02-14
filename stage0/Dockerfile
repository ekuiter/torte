FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --allow-unauthenticated \
    git \
    dos2unix \
    cloc
WORKDIR /home
COPY setup.sh .
RUN find . -type f -name "*.sh" -exec bash -c "chmod +x {} && dos2unix {}" \;