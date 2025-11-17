# platform-override=linux/amd64
FROM ubuntu:22.04

WORKDIR /home
RUN apt-get update && apt-get install -y \
    git \
    wget \
    openjdk-17-jdk \
    parallel
RUN git clone https://github.com/FeatureIDE/FeatJAR.git
WORKDIR /home/FeatJAR
RUN git checkout 3fc8d663ba3aafc0d1e1222d18dee2a651ef3a8c
COPY repo.txt scripts/
RUN scripts/clone.bat \
    && git -C base checkout 45f8df8740139ea3173585ce9c38c467502c4054 \
    && git -C bin-javasmt checkout 325d7c4aef2d1b2e92fe2fb3483a4504f8fe089c \
    && git -C formula checkout ccb8c82daa60ff96977fd73a2bb8c7b8b166e236 \
    && git -C formula-analysis-javasmt checkout 26d5092afae321bfa9372c30688960d9227ac55f
WORKDIR /home
COPY *.sh ./
RUN chmod +x *.sh \
    && ./gradle_proxy.sh
WORKDIR /home/FeatJAR/gradle/wrapper
RUN wget https://services.gradle.org/distributions/gradle-9.1.0-bin.zip \
    && sed -i 's/distributionUrl=.*/distributionUrl=gradle-9.1.0-bin.zip/' gradle-wrapper.properties
WORKDIR /home/FeatJAR
RUN ./gradlew assemble
WORKDIR /home