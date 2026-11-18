#!/usr/bin/env bash

# Synopsis:
# Runs at image build. For each library set used by the track's exercises,
# builds a template exercise with dune and saves the ocamlopt arguments dune
# used, one per line, in /opt/test-runner/fast-path/<libraries>.
# The runner's fast path (runner/src/fast.ml) passes these arguments to a
# single ocamlopt call, which compiles and links a solution without dune.
# Solutions using any other library set fall back to dune.

set -euo pipefail

out_dir=/opt/test-runner/fast-path
mkdir -p "${out_dir}"

for libraries in "base ounit2" "base calendar ounit2" "base ounit2 react" "base qcheck ounit2"; do
    dir=$(mktemp -d)
    cat > "${dir}/dune" <<EOF
(executable
 (name test)
 (libraries ${libraries}))

(alias
  (name    runtest)
  (deps    (:x test.exe))
  (action  (run %{x})))

(alias
  (name    buildtest)
  (deps    (:x test.exe)))

(env
  (dev
    (flags (:standard -warn-error -A))))
EOF
    echo '(lang dune 1.1)' > "${dir}/dune-project"
    echo 'let () = ()' > "${dir}/test.ml"

    log=$(cd "${dir}" && dune build ./test.exe --display verbose 2>&1)

    # The native compile of test.ml gives the flags and the include folders.
    compile=$(grep -- 'ocamlopt.opt .* -impl test.ml)$' <<< "${log}" \
        | sed -e 's/.*ocamlopt\.opt //' -e 's/)$//' \
              -e 's| -I .test.eobjs/byte -I .test.eobjs/native||' \
              -e 's| -cmi-file .test.eobjs/byte/test.cmi||' \
              -e 's| -o .test.eobjs/native/test.cmx -c -impl test.ml$||')
    # The link gives the libraries' archives in dune's order.
    link=$(grep -- 'ocamlopt.opt .* -o test.exe ' <<< "${log}" \
        | sed -e 's/.* -o test\.exe //' -e 's| .test.eobjs/native/test.cmx)$||')

    # Linking with mold instead of ld takes about a tenth of the time. The
    # test executable stays the same program, so results don't change.
    args="${compile} -ccopt -fuse-ld=mold -o test.exe ${link}"
    if [[ -z "${compile}" || -z "${link}" || "${args}" == *eobjs* ]]; then
        echo "Could not read dune's ocamlopt arguments for: ${libraries}" >&2
        echo "${log}" >&2
        exit 1
    fi

    tr ' ' '\n' <<< "${args}" > "${out_dir}/${libraries// /-}"
    rm -rf "${dir}"
done
