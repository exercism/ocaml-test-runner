FROM ocaml/opam:debian-ocaml-4.14-afl

USER root

RUN apt-get update && \
    apt-get -y install m4 bmake cpio net-tools fswatch pkg-config jq && \
    apt-get purge --auto-remove && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN opam update
RUN opam install base calendar dune ounit react qcheck

ENV PATH="/home/opam/.opam/4.14/bin:${PATH}"

WORKDIR /opt/test-runner
COPY . .
ENTRYPOINT ["/opt/test-runner/bin/run.sh"]
