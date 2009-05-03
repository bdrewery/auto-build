#! /bin/bash

. /home/bryan/auto-build/auto-build.conf

current_ts=$(date +%s)

rebuild() {
	tag=$1
	cd $GIT_WORK_TREE
	${GIT} clean -fdx
	${GIT} checkout -f $tag
	./configure && \
	cd $GIT_WORK_TREE && \
	$MAKE && \
	tar -czvf ${PKG_NAME}.$(uname -s)-${tag}.tar.gz ${PKG_NAME} && \
	mv ${PKG_NAME}.$(uname -s)-${tag}.tar.gz ${BIN_PATH}/
	# scp
	if [ -f Makefile ]; then
		$MAKE distrib && \
		tar -czvf ${PKG_NAME}-$(${GIT} describe).tar.gz ${PKG_NAME}-$(${GIT} describe) && \
		mv ${PKG_NAME}-$(${GIT} describe).tar.gz ${SRC_PATH}/
		# scp
	fi
	${GIT} clean -fdx
}

critical_section() {
	for ref in $(awk '{print $1}' ${AUTO_BUILD_DIR}/queue); do
		QUEUE_TS=$(grep "^\<${ref}\>" ${AUTO_BUILD_DIR}/queue|awk '{print $2}')
		if [ $((${current_ts} - ${QUEUE_TS})) -gt $((${QUEUE_MINUTES} * 60)) ]; then
			rebuild $ref
			### Remove tag from queue
			$SED -i -e "/^${ref}\ /d" ${AUTO_BUILD_DIR}/queue
		fi
	done
}

lockfile=${AUTO_BUILD_DIR}/.lock

if [ ! -e $lockfile ]; then
	trap "rm -f $lockfile; exit" INT TERM EXIT
	touch $lockfile

	critical_section;

	rm -f $lockfile
	trap - INT TERM EXIT
else
	echo "Already running!"
fi

