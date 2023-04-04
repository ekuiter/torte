FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    git \
    openjdk-11-jdk \
    bc
WORKDIR /home
# todo: pin exact versions of repositories
RUN git clone https://github.com/ekuiter/SATGraf.git
WORKDIR /home/SATGraf
RUN chmod +x ./gradlew
RUN ./gradlew shadowJar
WORKDIR /home
COPY *.sh satgraf/*.sh ./
RUN chmod +x *.sh