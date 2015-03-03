#!/usr/bin/env bash

shopt -s nullglob
set -e -x

mirrordir=fill-me-in-please
revdeltadir=fill-me-in-please
repodir=fill-me-in-please

algo='-comp lzo -Xcompression-level 4'
mksquashfs_options="-no-xattrs -force-uid portage -force-gid portage ${algo}"

[[ -d ${mirrordir} ]]
[[ -d ${revdeltadir} ]]
[[ -d ${repodir} ]]

reponame=$(<"${repodir}"/profiles/repo_name)

[[ ${reponame} ]]

tempdir=$(mktemp -d)

trap "rm -r ${tempdir}" EXIT

snapshots=( "${mirrordir}"/${reponame}-*.sqfs )

if [[ ${snapshots[@]} ]]; then
	yesterdaysnap=${snapshots[-1]}
	yesterday=${yesterdaysnap#*/${reponame}-}
	yesterday=${yesterday%.sqfs}

	today=$(date --date="${yesterday} tomorrow" +%Y%m%d)
else
	# when there's no yesterday, trust in the clock
	today=$(date +%Y%m%d)
fi

todaysnap=${mirrordir}/${reponame}-${today}.sqfs

# take today's snapshot
mksquashfs "${repodir}" "${tempdir}"/${reponame}-${today}.sqfs \
	${mksquashfs_options}
mv "${tempdir}"/${reponame}-${today}.sqfs "${mirrordir}"/

[[ ! ${yesterday} ]] && exit 0

# create rev-delta from today to yesterday
squashdelta "${todaysnap}" "${yesterdaysnap}" \
	"${revdeltadir}"/${reponame}-${today}-${yesterday}.sqdelta

# create deltas from previous days to today

revdeltas=( "${revdeltadir}"/*.sqdelta )
for (( i = ${#revdeltas[@]} - 1; i >= 0; i-- )); do
	r=${revdeltas[${i}]}
	ldate=${r#*/${reponame}-}
	rdate=${ldate%.sqdelta}
	ldate=${ldate%-*}
	rdate=${rdate#*-}

	# ldate = newer, rdate = older

	if [[ ${rdate} == ${yesterday} ]]; then
		# we have yesterday's snapshot already, so use it
		rsnap=${yesterdaysnap}
	else
		# otherwise, we need to reconstruct the snap
		if [[ ${ldate} == ${yesterday} ]]; then
			lsnap=${yesterdaysnap}
		else
			lsnap=${tempdir}/${reponame}-${ldate}.sqfs
		fi
		rsnap=${tempdir}/${reponame}-${rdate}.sqfs

		squashmerge "${lsnap}" "${r}" "${rsnap}"
		rm "${lsnap}"
	fi

	squashdelta "${rsnap}" "${todaysnap}" "${tempdir}"/${reponame}-${rdate}-${today}.sqdelta
	mv "${tempdir}"/${reponame}-${rdate}-${today}.sqdelta "${mirrordir}"/
done

# remove the last snapshot used
rm "${rsnap}"

# finally, clean up the old deltas
rm -f "${mirrordir}"/${reponame}-*-${yesterday}.sqdelta

# create checksums for snapshot and deltas
cd "${mirrordir}"
sha512sum *.sqfs *.sqdelta | \
	gpg --yes --clearsign --output sha512sum.txt.tmp -
mv sha512sum.txt.tmp sha512sum.txt
