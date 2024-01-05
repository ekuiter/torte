FROM ubuntu:18.04

# install (tested) dependencies of kmax
RUN apt-get update && apt-get install -y --allow-unauthenticated \
  git \
  python3-setuptools \
  python3-dev \
  flex \
  bison \
  libssl-dev \
  libelf-dev \
  wget \
  parallel

# install (the tested version of) kmax
WORKDIR /home
# we fix z3 to an older version although we do not need it here, as 4.12.2.0 does not compile correctly
RUN git clone https://github.com/paulgazz/kmax.git \
  && cd kmax \
  && git checkout d0fe92db13ca97140385cd39977d937d1ee92d4c \
  && sed -i 's/z3-solver/z3-solver==4.11.2/' setup.py \
  && python3 setup.py install

# install dependencies of analyzed projects
RUN apt-get update && apt-get install -y --allow-unauthenticated \
  build-essential

# copy and set up
# - kextractor (which is compiled against the projects' Kconfig implementations)
# - IO scripts
COPY *.sh *.py kextractor.c ./
RUN git config --global --add safe.directory '*'
RUN chmod +x *.sh