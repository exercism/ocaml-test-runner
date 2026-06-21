# ---- builder: full OCaml dev image; builds the runner and the files we keep ----
# Using the "no flat float array" based image which is OCaml compiled with
# --disable-flat-float-array. This gives a container smaller image overall
# but disables OCaml's optimization for float arrays. Does not prevent
# float arrays from being used.
FROM docker.io/ocaml/opam:debian-13-ocaml-5.4-no-flat-float-array@sha256:dfe7ce9fdd804f98768e9c3038531f9b4d9e91bc413dea3bf6c3526aaf21f768 AS builder

ENV PATH="/home/opam/.opam/5.4/bin:${PATH}"

# We purposefully don't combine the opam update and opam install steps
# to allow the opam update layer to be re-used.
RUN opam update

# Install everything the runtime needs: the build tool (dune) and every library
# an exercise solution may use, plus the runner's own build dependencies (yojson,
# ezxmlm). opam puts all of this under /home/opam/.opam/5.4 (the OCaml compiler,
# libraries and tools), which the runner stage copies as-is.
RUN opam install dune ounit2 yojson ezxmlm \
                 base ppx_deriving ppx_sexp_conv qcheck react calendar

WORKDIR /opt/test-runner

# Set owner to opam for the dune commands
RUN chown -R opam:opam /opt/test-runner

COPY runner/ .
RUN dune test && dune build

# Delete files the runner does not need: opam's download cache and its copy of
# the package index, plus man pages and docs. The compiler and libraries stay.
RUN opam clean -a \
 && rm -rf /home/opam/.opam/download-cache /home/opam/.opam/repo \
           /home/opam/.opam/5.4/man /home/opam/.opam/5.4/doc

# ---- runner: slim base + the OCaml files from the builder + a C toolchain ----
# Pinned Debian 13 (trixie) slim, matching the lean/racket/vlang test runners.
FROM debian:trixie-slim@sha256:109e2c65005bf160609e4ba6acf7783752f8502ad218e298253428690b9eaa4b AS runner

# dune compiles each solution to native code at runtime, so a C toolchain is
# needed: gcc + binutils (as/ld) + libc headers. make: the exercise Makefiles
# invoke `dune runtest`. libzstd-dev: OCaml 5 links against zstd using `-lzstd`.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        gcc binutils libc6-dev make libzstd-dev \
 && rm -rf /var/lib/apt/lists/*

# Copy the OCaml compiler, libraries and tools built above. They record this
# directory as their location, so they must land at the same path here.
COPY --from=builder /home/opam/.opam/5.4 /home/opam/.opam/5.4

# In the builder these variables are set automatically; the slim image has no
# OCaml tooling to set them, so point dune and the compiler at the copied files
# by hand.
ENV DUNE_CACHE="disabled" \
    PATH="/home/opam/.opam/5.4/bin:${PATH}" \
    OPAM_SWITCH_PREFIX="/home/opam/.opam/5.4" \
    OCAMLPATH="/home/opam/.opam/5.4/lib" \
    OCAMLFIND_CONF="/home/opam/.opam/5.4/lib/findlib.conf" \
    CAML_LD_LIBRARY_PATH="/home/opam/.opam/5.4/lib/stublibs:/home/opam/.opam/5.4/lib/ocaml/stublibs:/home/opam/.opam/5.4/lib/ocaml"

WORKDIR /opt/test-runner

COPY --from=builder /opt/test-runner/_build/default/src/runner.exe bin/runner
COPY . .

ENTRYPOINT ["/opt/test-runner/bin/run.sh"]
