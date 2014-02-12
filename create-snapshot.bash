#!/usr/bin/env bash

set -e -x

mirrordir=fill-me-in-please
revdeltadir=fill-me-in-please
repodir=fill-me-in-please

tempdir=$(mktemp -d)

trap "rm -r ${tempdir}" EXIT

snapshots=( "${mirrordir}"/*.sqfs )
yesterdaysnap=${snapshots[-1]}
yesterday=${yesterdaysnap#*/portage-}
yesterday=${yesterday%.sqfs}

today=$(date --date="${yesterday} tomorrow" +%Y%m%d)

cat - Makefile.in > Makefile <<-_EOF_
	mirrordir = ${mirrordir}
	revdeltadir = ${revdeltadir}
	repodir = ${repodir}
	tempdir = ${tempdir}

	today = ${today}
	yesterday = ${yesterday}

_EOF_

revdeltas=( "${revdeltadir}"/*.sqdelta )
for (( i = ${#revdeltas[@]} - 1; i >= 0; i-- )); do
	r=${revdeltas[${i}]}
	ldate=${r#*/portage-}
	rdate=${ldate%.sqdelta}
	ldate=${ldate%-*}
	rdate=${rdate#*-}

	# ldate = newer, rdate = older
	if [[ ${ldate} == ${yesterday} ]]; then
		lsnap='${yesterdaysnap}'
	else
		lsnap="\${tempdir}/portage-${ldate}.sqfs"
	fi
	rsnap="\${tempdir}/portage-${rdate}.sqfs"

	cat >> Makefile <<_EOF_
all: \${mirrordir}/portage-${ldate}-${today}.sqdelta
\${mirrordir}/portage-${ldate}-${today}.sqdelta: \${todaysnap}
	@while [ ! -f \${tempdir}/portage-${ldate}.stamp ]; do sleep 0.3; done
	squashmerge ${lsnap} \${revdeltadir}/portage-${ldate}-${rdate}.sqdelta ${rsnap}
	touch \${tempdir}/portage-${rdate}.stamp
	squashdelta ${lsnap} \${todaysnap} \$@
	rm ${lsnap}

_EOF_
done

# last one
cat >> Makefile <<_EOF_
all: \${mirrordir}/portage-${rdate}-${today}.sqdelta
\${mirrordir}/portage-${rdate}-${today}.sqdelta: \${todaysnap}
	@while [ ! -f \${tempdir}/portage-${rdate}.stamp ]; do sleep 0.3; done
	squashdelta ${rsnap} \${todaysnap} \$@
	rm ${rsnap}
_EOF_

make ${MAKEOPTS:--j2}
