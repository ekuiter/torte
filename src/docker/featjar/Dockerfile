# platform-override=linux/amd64
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    wget \
    openjdk-21-jdk-headless \
    parallel \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /home
# Build the adapter against the pinned FeatJAR monorepo.
RUN git clone https://github.com/FeatureIDE/FeatJAR.git \
    && cd FeatJAR \
    && git checkout 74699308f4e834fe912d947ab8a36fcdaeecf01b
WORKDIR /home/FeatJAR
RUN git clone https://github.com/ekuiter/torte-FeatJAR.git \
    && git -C torte-FeatJAR checkout 92a430e07d430338643addd543e536443bae7f7e
WORKDIR /home
COPY *.sh ./
RUN chmod +x *.sh \
    && ./gradle_proxy.sh
WORKDIR /home/FeatJAR
RUN ./gradlew -p torte-FeatJAR shadowJar --no-daemon --max-workers=2
WORKDIR /home
