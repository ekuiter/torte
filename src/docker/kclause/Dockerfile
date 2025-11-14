FROM ubuntu:22.04

# kmax and system (e.g., Linux) dependencies
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --allow-unauthenticated \
  git \
  python3-setuptools \
  pipx \
  python3-dev \
  flex \
  bison \
  bc \
  libssl-dev \
  libelf-dev \
  wget \
  parallel \
  cmake \
  build-essential

# install (the tested version of) kmax
WORKDIR /home
# we fix z3 to an older version although we do not need it here, as 4.12.2.0 does not compile correctly
RUN git clone https://github.com/paulgazz/kmax.git \
  && cd kmax \
  && git checkout 414adb9d409f1a20e019d49a822c290b8863c469 \
  && sed -i 's/z3-solver/z3-solver==4.11.2/' setup.py \
  && python3 setup.py install

# copy and set up
# - kextractor (which is compiled against the projects' Kconfig implementations)
# - IO scripts
COPY *.sh *.py kextractor.c ./
RUN git config --global --add safe.directory '*' \
    && git config --global user.email "anon@example.com" \
    && git config --global user.name "anon" \
    && git config --global init.defaultBranch main
RUN chmod +x *.sh