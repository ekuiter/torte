FROM ubuntu:22.04

WORKDIR /home
RUN apt-get update && apt-get install -y \
    git \
    openjdk-11-jdk
# todo: pin exact versions of repositories
RUN git clone https://github.com/FeatureIDE/FeatJAR.git
COPY featjar2/repo.txt FeatJAR/scripts/
RUN cd FeatJAR \
    && scripts/clone.bat \
    && ./gradlew assemble
# as these repositories are under active development and unstable, we check out tested commits
# RUN git clone https://github.com/skrieter/spldev.git \
#     && git -C spldev checkout 60a888cecadaf7ded42c2ba740335ba2c3a5c148
# WORKDIR /home/spldev
# RUN git clone https://github.com/skrieter/util.git \
#     && git -C util checkout 31c03516e1401c74c1f5132b04ae31bb95547591
# RUN git clone https://github.com/skrieter/evaluation.git \
#     && git -C evaluation checkout bdb7a6eb400b7fa3f3c1a2df04ee2cd66a041e78
# RUN git clone https://github.com/skrieter/formula.git \
#     && git -C formula checkout 0e2294e04dcfdc04d234253278389bb1691ce44b
# RUN git clone https://github.com/skrieter/formula-analysis.git \
#     && git -C formula-analysis checkout 048b1c4408c741147974d701ca456300088aec99
# RUN git clone https://github.com/skrieter/formula-analysis-javasmt.git \
#     && git -C formula-analysis-javasmt checkout 2f06d45b9d4468d1ca41e736b6bf5c2f4d3174dc
# RUN git clone https://github.com/skrieter/javasmt-native.git \
#     && git -C javasmt-native checkout 58cca175e9c52e9d72e908fa0a4ba2de6ecc0acb
# RUN printf "util\nevaluation\nformula\nformula-analysis\nformula-analysis-javasmt\njavasmt-native" > build.cfg \
#     && ./build.sh -c
#COPY featjar/evaluation-cnf ./evaluation-cnf
#RUN mvn install -f evaluation-cnf/pom.xml
#WORKDIR /home
#COPY *.sh featjar/*.sh ./
#RUN chmod +x *.sh