FROM ocaml/opam:alpine-3.18-ocaml-4.14-afl AS builder


RUN opam update \
 && opam install base core dune \
  calendar react \
  ounit ounit2 qcheck ezxmlm yojson \
  ppx_deriving
ENV PATH="/home/opam/.opam/4.14/bin:${PATH}"

COPY . .
WORKDIR ./runner
USER root
RUN dune build
USER $CONTAINER_USER_ID

FROM ocaml/opam:alpine-3.18-ocaml-4.14-afl
WORKDIR /opt/test-runner

RUN mkdir -p /opt/test-runner && chown -R opam:opam /opt/test-runner

RUN opam update \
 && opam install dune ounit2 base qcheck react ppx_sexp_conv calendar ppx_deriving
COPY . .
COPY --from=builder /home/opam/runner/_build/default/src/runner.exe bin/runner
ENV PATH="/home/opam/.opam/4.14/bin:${PATH}"

ENTRYPOINT ["/opt/test-runner/bin/run.sh"]
