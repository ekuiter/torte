FROM ubuntu:22.04

WORKDIR /home
RUN apt-get update && apt-get install -y \
    git \
    openjdk-11-jdk
# todo: pin exact versions of repositories
RUN git clone https://github.com/FeatureIDE/FeatJAR.git
WORKDIR /home/FeatJAR
COPY featjar/repo.txt scripts/
# increment to re-clone, todo: replace by exact versions
RUN echo 1
RUN scripts/clone.bat \
    && ./gradlew assemble
COPY featjar/transform transform
RUN ./gradlew assemble
WORKDIR /home
COPY *.sh ./
RUN chmod +x *.sh