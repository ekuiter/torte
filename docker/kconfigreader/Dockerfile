FROM ubuntu:14.04

# install (tested) dependencies of kconfigreader
RUN apt-get update && apt-get install -y --allow-unauthenticated \
  git \
  openjdk-7-jdk \
  wget \
  parallel
COPY sbt-0.13.6.deb .
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

# install GNU make 4.4.0.90 and binutils 2.40, which is needed for newer Linux versions
RUN wget --no-check-certificate https://alpha.gnu.org/gnu/make/make-4.4.0.90.tar.gz \
  && tar xzvf make-4.4.0.90.tar.gz \
  && cd make-4.4.0.90 \
  && ./configure \
  && make \
  && make install
RUN wget --no-check-certificate https://ftp.fau.de/gnu/binutils/binutils-2.35.tar.gz \
  && tar xzvf binutils-2.35.tar.gz \
  && cd binutils-2.35 \
  && ./configure \
  && make \
  && make install

# copy and set up
# - dumpconf (which is compiled against the projects' Kconfig implementations)
# - CNF transformer
COPY TransformIntoDIMACS.scala kconfigreader/src/main/scala/
RUN cd kconfigreader && sbt mkrun
COPY dumpconf.c ./
RUN git config --global --add safe.directory '*'