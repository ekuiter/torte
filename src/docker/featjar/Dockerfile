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
# base and formula are needed by all the transformations
# bin-javasmt and formula-analysis-javasmt are used for transformation to SMT
# uvl is used for FeatJAR transformation _from_ UVL (FeatureIDE ships its own UVL support, which we use for transformation into UVL)
# feature-model and formula-analysis-sat4j are not used, but must be included because uvl depends on them
# torte-FeatJAR implements the actual transformations
RUN scripts/clone.bat \
    && git -C base checkout 45f8df8740139ea3173585ce9c38c467502c4054 \
    && git -C bin-javasmt checkout 325d7c4aef2d1b2e92fe2fb3483a4504f8fe089c \
    && git -C feature-model checkout b188320a957a4cd0215176b12d87511e958f777e \
    && git -C formula checkout 4e6c97104fb22319050366721cfbf6971d1aa24c \
    && git -C formula-analysis-javasmt checkout 26d5092afae321bfa9372c30688960d9227ac55f \
    && git -C formula-analysis-sat4j checkout 8e4aacf0911b340e5b5e90da4f74ce191dc3b0ca \
    && git -C uvl checkout b5867699e0aca973e47529406d7c4f9ec9894239 \
    && git -C torte-FeatJAR checkout c1cad89dcb47899a094538d80520b54db541cbf4
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