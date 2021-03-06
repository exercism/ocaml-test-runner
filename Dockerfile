# Install dependencies
FROM ocaml/opam2:ubuntu-18.04-ocaml-4.07

USER root

RUN sudo apt-get update && \
    sudo apt-get -y install m4 bmake cpio net-tools fswatch pkg-config jq && \
    apt-get purge --auto-remove && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /home/opam/opam-repository

# TODO: figure out how to not do this
RUN git pull && \
    git checkout c23c1a7071910f235d5bc173cbadb97cd450e9fb

WORKDIR /home/opam

RUN opam update && \
    opam install dune fpath ocamlfind ounit qcheck react ppx_deriving ppx_let \
    ppx_sexp_conv yojson ocp-indent calendar getopts merlin yaml ezjsonm mustache

# TODO: figure out how to simplify the below
RUN ln -s /home/opam/.opam /root/.opam
SHELL ["/bin/bash", "--login" , "-c"]
ENV OPAM_SWITCH_PREFIX='/home/opam/.opam/4.07'
ENV CAML_LD_LIBRARY_PATH='/home/opam/.opam/4.07/lib/stublibs:/home/opam/.opam/4.07/lib/ocaml/stublibs:/home/opam/.opam/4.07/lib/ocaml'
ENV OCAML_TOPLEVEL_PATH='/home/opam/.opam/4.07/lib/toplevel'
ENV MANPATH=':/root/.opam/4.07.1/man:/home/opam/.opam/4.07/man'
ENV PATH='/home/opam/.opam/4.07/bin:/root/.opam/4.07.1/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'

COPY . /opt/test-runner
WORKDIR /opt/test-runner
ENTRYPOINT ["/opt/test-runner/bin/run.sh"]
