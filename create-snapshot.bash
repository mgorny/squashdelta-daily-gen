#!/usr/bin/env bash

# Copyright (c) 2014-2015, Michał Górny
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

shopt -s nullglob
set -e -x

source /usr/local/bin/mastermirror/rsync-gen.vars

# Final deltas get mirrored out here.
mirrordir=${UPLOAD}/squashfs
# We keep deltas around here to generate larger deltas, but may not be mirrored.
revdeltadir=${BASE}/squashfs-tmp
# FINALDIR is where the master gentoo-x86 copy of the tree is located.
repodir=${FINALDIR}

# GPG key ID to sign with
signkeyid="DCD05B71EAB94199527F44ACDB6B8C1F96D8BF6D"

# Deltas to keep before cleanup
cleanupno=180

if [[ ! -d $revdeltadir ]]; then
	mkdir -p "$revdeltadir"
fi

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
fi

today=$(date +%Y%m%d)
todaysnap=${mirrordir}/${reponame}-${today}.sqfs

# take today's snapshot
mksquashfs "${repodir}" "${tempdir}"/${reponame}-${today}.sqfs \
	${mksquashfs_options}
mv "${tempdir}"/${reponame}-${today}.sqfs "${mirrordir}"/

if [[ ${yesterday} ]]; then
	# create rev-delta from today to yesterday
	squashdelta "${todaysnap}" "${yesterdaysnap}" \
		"${revdeltadir}"/${reponame}-${today}-${yesterday}.sqdelta

	# create deltas from previous days to today
	revdeltas=( "${revdeltadir}"/*.sqdelta )
	lastdelta=$(( ${#revdeltas[@]} - ${cleanupno} ))
	for (( i = ${#revdeltas[@]} - 1; i >= 0; i-- )); do
		[[ ${i} != ${lastdelta} ]] || break

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
fi

# create checksums for snapshot and deltas
cd "${mirrordir}"
sha512sum *.sqfs *.sqdelta | \
	gpg --yes -u "${signkeyid}" --clearsign \
	--comment "Date: ${today}" --output sha512sum.txt.tmp -
mv sha512sum.txt.tmp sha512sum.txt
