FROM ocaml/opam:debian-ocaml-4.14-afl

RUN sudo apt-get update && \
    sudo apt-get -y install m4 bmake cpio net-tools fswatch pkg-config jq && \
    sudo apt-get purge --auto-remove && \
    sudo apt-get clean && \
    sudo rm -rf /var/lib/apt/lists/*

RUN opam update
RUN opam install base calendar dune ounit react qcheck

ENV PATH="/home/opam/.opam/4.14/bin:${PATH}"

WORKDIR /opt/test-runner
COPY . .
ENTRYPOINT ["/opt/test-runner/bin/run.sh"]
