FROM ubuntu:14.04
ENV DEBIAN_FRONTEND=noninteractive

# install (tested) dependencies of kconfigreader
RUN apt-get update && apt-get install -y --allow-unauthenticated \
  git \
  openjdk-7-jdk \
  wget \
  parallel
COPY sbt-0.13.6.deb .
RUN dpkg -i sbt-0.13.6.deb

# install cached dependencies for offline sbt bootstrapping and compilation
COPY sbt-cache.tar.gz /tmp/
RUN echo "a42b4b0acef4aa593d36014a9b6416ee0827ecf856c753399182c2393e3e336b  /tmp/sbt-cache.tar.gz" | sha256sum -c - \
  && tar -xzf /tmp/sbt-cache.tar.gz -C /root \
  && rm /tmp/sbt-cache.tar.gz

# install (the tested version of) kconfigreader
WORKDIR /home
RUN git clone https://github.com/ckaestne/kconfigreader.git \
  && cd kconfigreader \
  && git checkout 913bf3178af5a8ac8bedc5e8733561ed38280cf9 \
  # the SYMBOL_CHOICE flag was removed in Linux 6.11 (https://github.com/torvalds/linux/commit/1da251c60def5df1475ed5e8670d7ba2b6a33983)
  && sed -i 's/val isChoice.*$/val isChoice = hasFlag(symbol, SYMBOL_CHOICE) || itemName.isEmpty/' src/main/scala/XMLDumpReader.scala \
  && sed -i 's/assert(isChoice.*$//' src/main/scala/XMLDumpReader.scala \
  && sbt mkrun

# install dependencies of analyzed projects
RUN apt-get update && apt-get install -y --allow-unauthenticated \
  flex \
  bison \
  gawk \
  build-essential \
  # some Linux versions require newer GCC
  software-properties-common \
  && add-apt-repository ppa:ubuntu-toolchain-r/test \
  && apt-get update && apt-get install -y --allow-unauthenticated \
  gcc-9 \
  g++-9 \
  # freetz-ng
  realpath \
  && update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 60 --slave /usr/bin/g++ g++ /usr/bin/g++-9

# install GNU make 4.4.1 and binutils 2.40, which is needed for newer Linux versions
RUN wget --no-check-certificate https://ftp.fau.de/gnu/make/make-4.4.1.tar.gz \
  && tar xzvf make-4.4.1.tar.gz \
  && cd make-4.4.1 \
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
RUN git config --global --add safe.directory '*' \
    && git config --global user.email "anon@example.com" \
    && git config --global user.name "anon" \
    && git config --global init.defaultBranch main

# increase memory limit and disable assertions
RUN sed -i 's/java/mem=$1; shift; java/' kconfigreader/run.sh
RUN sed -i 's/-ea -Xmx3G/-da "-Xmx${mem}G"/' kconfigreader/run.sh
