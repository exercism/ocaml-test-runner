FROM ocaml/opam:debian-ocaml-4.14-afl

USER root

RUN apt-get update && \
    apt-get -y install m4 bmake cpio net-tools fswatch pkg-config jq python3-xmltodict && \
    apt-get purge --auto-remove && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/test-runner && chown -R opam:opam /opt/test-runner

RUN opam update \
 && opam install base core dune \
  calendar react \
  ounit ounit2 qcheck ezxmlm yojson \
  ppx_deriving

ENV PATH="/home/opam/.opam/4.14/bin:${PATH}"

WORKDIR /opt/test-runner
COPY . .
RUN cd runner && dune build 
RUN cp runner/_build/default/src/runner.exe bin/runner 
ENTRYPOINT ["/opt/test-runner/bin/run.sh"]
