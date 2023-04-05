FROM ubuntu:14.04

# install (tested) dependencies of kconfigreader and evaluation scripts
RUN apt-get update && apt-get install -y --allow-unauthenticated \
  git \
  openjdk-7-jdk \
  wget
COPY kconfigreader/sbt-0.13.6.deb .
RUN dpkg -i sbt-0.13.6.deb

# install (the tested version of) kconfigreader
WORKDIR /home
RUN git clone https://github.com/ckaestne/kconfigreader.git \
  && cd kconfigreader \
  && git checkout 913bf3178af5a8ac8bedc5e8733561ed38280cf9 \
  && sbt mkrun

# install dependencies of analyzed projects
RUN apt-get update && apt-get install -y --allow-unauthenticated \
  flex \
  bison \
  build-essential \
  # some Linux versions require newer GCC
  software-properties-common \
  && add-apt-repository ppa:ubuntu-toolchain-r/test \
  && apt-get update && apt-get install -y --allow-unauthenticated \
  gcc-9 \
  g++-9 \
  && update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 60 --slave /usr/bin/g++ g++ /usr/bin/g++-9

# copy and set up
# - dumpconf (which is compiled against the projects' Kconfig implementations)
# - evaluation scripts
# - CNF transformer
COPY kconfigreader/TransformIntoDIMACS.scala kconfigreader/src/main/scala/
RUN cd kconfigreader && sbt mkrun
COPY *.sh kconfigreader/dumpconf.c ./
RUN chmod +x *.sh \
    && git config --global --add safe.directory '*'