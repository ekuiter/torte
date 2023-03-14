FROM ubuntu:22.04

WORKDIR /home
RUN apt-get update && apt-get install -y \
    git \
    openjdk-11-jdk \
    bc
# todo: pin exact versions of repositories
RUN git clone https://github.com/FeatureIDE/FeatJAR.git
WORKDIR /home/FeatJAR
COPY featjar/repo.txt scripts/
RUN scripts/clone.bat \
    && ./gradlew assemble
COPY featjar/transform transform
RUN ./gradlew assemble
WORKDIR /home
COPY *.sh featjar/*.sh ./
RUN chmod +x *.sh