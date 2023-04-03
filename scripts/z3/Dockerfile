FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    bc \
    python3 \
    python3-pip \
    && python3 -mpip install z3-solver==4.11.2
# todo: upgrade z3 to 4.12.1, see https://github.com/Z3Prover/z3/issues/6577

WORKDIR /home
COPY *.sh z3/*.py ./
RUN chmod +x *.sh