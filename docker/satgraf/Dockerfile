FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    git \
    openjdk-11-jdk
WORKDIR /home
RUN git clone https://github.com/ekuiter/SATGraf.git \
  && cd SATGraf \
  && git checkout 267701548107dbc086638b5db83092b92e2c8db0
WORKDIR /home/SATGraf
RUN chmod +x ./gradlew
RUN ./gradlew shadowJar
WORKDIR /home
COPY *.sh ./
RUN chmod +x *.sh