FROM ocaml/opam:alpine-3.18-ocaml-5.2 AS builder

ENV PATH="/home/opam/.opam/5.2/bin:${PATH}"

# We purposefully don't combine the opam update and opam install steps
# to allow the opam update layer to be re-used in the runner image below 
RUN opam update
RUN opam install dune yojson ezxmlm

WORKDIR /opt/test-runner
COPY runner/ .
RUN dune build

FROM ocaml/opam:alpine-3.18-ocaml-5.2 AS runner

ENV PATH="/home/opam/.opam/5.2/bin:${PATH}"

RUN opam update
RUN opam install base ounit2 ppx_deriving ppx_sexp_conv qcheck react calendar

WORKDIR /opt/test-runner

COPY --from=builder /opt/test-runner/_build/default/src/runner.exe bin/runner
COPY . .

USER root
ENTRYPOINT ["/opt/test-runner/bin/run.sh"]
