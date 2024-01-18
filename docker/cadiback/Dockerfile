FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    git \
    parallel
WORKDIR /home
RUN git clone https://github.com/arminbiere/cadical \
  && cd cadical \
  && git checkout e71bd58937e6513f71bd8c93d91578785c592721
WORKDIR /home/cadical
RUN ./configure && make
RUN git clone https://github.com/arminbiere/cadiback \
  && cd cadiback \
  && git checkout 2e912fb36749e3e0aa4361940cfbec3560758722
WORKDIR /home/cadiback
RUN ./configure && make
COPY *.sh ./
RUN chmod +x *.sh