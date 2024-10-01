# platform-override=linux/amd64
FROM ubuntu:22.04

WORKDIR /home
RUN apt-get update && apt-get install -y \
    git \
    wget \
    openjdk-11-jdk \
    parallel
RUN git clone https://github.com/FeatureIDE/FeatJAR.git
WORKDIR /home/FeatJAR
RUN git checkout e27aea72d97b590ff35006f75e43742cbef30886
COPY repo.txt scripts/
RUN scripts/clone.bat \
    && git -C base checkout d807fd6a497f9fd553edd5b0268ec49e6b86be7b \
    && git -C bin-javasmt checkout 50bca897d98e78d6bdbb33fbc5b320745729e033 \
    && git -C formula checkout 471854b5c28303c7636fe8104dc87259b09506be \
    && git -C formula-analysis-javasmt checkout 33cd6c96a49e3dfd82a95801b39cbca46e665b04 \
    && git -C gradle-plugins checkout 4a3bb36564e44ae3253774075ad23cbb2d87a52f
WORKDIR /home/FeatJAR/gradle/wrapper
RUN wget https://services.gradle.org/distributions/gradle-8.0.2-bin.zip \
    && sed -i 's/distributionUrl=.*/distributionUrl=gradle-8.0.2-bin.zip/' gradle-wrapper.properties
WORKDIR /home/FeatJAR
RUN ./gradlew assemble
COPY transform transform
RUN ./gradlew assemble
WORKDIR /home