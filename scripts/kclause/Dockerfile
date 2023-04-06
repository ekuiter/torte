FROM ubuntu:18.04

# install (tested) dependencies of kmax/kclause and evaluation scripts
RUN apt-get update && apt-get install -y --allow-unauthenticated \
  git \
  python3-setuptools \
  python3-dev \
  flex \
  bison \
  libssl-dev \
  libelf-dev \
  wget

# install (the tested version of) kmax/kclause
WORKDIR /home
RUN git clone https://github.com/paulgazz/kmax.git \
  && cd kmax \
  && git checkout 5a8780dd9bc17341dc8e16b53224d25607ae2e7b \
  && python3 setup.py install

# install dependencies of analyzed projects
RUN apt-get update && apt-get install -y --allow-unauthenticated \
  build-essential

# copy and set up
# - kextractor (which is compiled against the projects' Kconfig implementations)
# - IO and evaluation scripts
COPY *.sh kclause/*.sh kclause/*.py kclause/kextractor.c ./
RUN chmod +x *.sh \
    && git config --global --add safe.directory '*'