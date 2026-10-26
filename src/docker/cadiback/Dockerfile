FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    git \
    build-essential \
    parallel
WORKDIR /home
RUN git clone https://github.com/arminbiere/cadical \
  && cd cadical \
  && git checkout c60730422e758ef1cebe7aeddf2dda31c996bf04
WORKDIR /home/cadical
RUN ./configure && make
WORKDIR /home
RUN git clone https://github.com/arminbiere/cadiback \
  && cd cadiback \
  && git checkout 789329d8fcda851085ed72f1b07d8c3f46243b8a
WORKDIR /home/cadiback
RUN ./configure && make
COPY ./ ./
