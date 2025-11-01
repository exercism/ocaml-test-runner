# Using the "no flat float array" based image which is OCaml compiled with
# --disable-flat-float-array. This gives a container smaller image overall
# but disables OCaml's optimization for float arrays. Does not prevent
# float arrays from being used.
FROM docker.io/ocaml/opam:debian-13-ocaml-5.4-no-flat-float-array AS builder

ENV PATH="/home/opam/.opam/5.4/bin:${PATH}"

# We purposefully don't combine the opam update and opam install steps
# to allow the opam update layer to be re-used in the runner image below 
RUN opam update
RUN opam install dune ounit2 yojson ezxmlm

WORKDIR /opt/test-runner

# Set owner to opam for the dune commands
RUN chown -R opam:opam /opt/test-runner

COPY runner/ .
RUN dune test && dune build

FROM docker.io/ocaml/opam:debian-13-ocaml-5.4-no-flat-float-array AS runner

ENV PATH="/home/opam/.opam/5.4/bin:${PATH}"

RUN opam update
RUN opam install base dune ounit2 ppx_deriving ppx_sexp_conv qcheck react calendar

WORKDIR /opt/test-runner

COPY --from=builder /opt/test-runner/_build/default/src/runner.exe bin/runner
COPY . .

USER root
ENTRYPOINT ["/opt/test-runner/bin/run.sh"]
