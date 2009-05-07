#! /bin/bash

export PATH=/bin:/usr/bin:/usr/sbin:/sbin:/usr/local/bin
. /home/bryan/auto-build/auto-build.conf

current_ts=$(date +%s)

rebuild() {
	ref=$1
	cd $GIT_WORK_TREE
	${GIT} clean -fdx
	${GIT} checkout -f $ref
	TAG=$(${GIT} describe $ref)
        UNAME=$(uname -s)
	### Is this a tag or a branch?
	${GIT} describe --exact-match $ref > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		my_BIN_PATH=${BIN_PATH}/tags
		my_SRC_PATH=${SRC_PATH}/tags
	else
		my_BIN_PATH=${BIN_PATH}/${ref}
		my_SRC_PATH=${SRC_PATH}/${ref}
	fi

	if ! [ -d "${my_BIN_PATH}" ]; then
		mkdir -p ${my_BIN_PATH} > /dev/null 2>&1
	fi

	./configure && \
	cd $GIT_WORK_TREE && \
	$MAKE && \
        mv ${PKG_NAME} ${PKG_NAME}.${UNAME}-${TAG} && \
	tar -czvf ${PKG_NAME}.${UNAME}-${TAG}.tar.gz ${PKG_NAME}.${UNAME}-${TAG} && \
	mv ${PKG_NAME}.${UNAME}-${TAG}.tar.gz ${my_BIN_PATH}/
	# scp
	if [ -f Makefile -a "$DO_SRC" = "1" ]; then
		if ! [ -d "${my_SRC_PATH}" ]; then
			mkdir -p ${my_SRC_PATH} > /dev/null 2>&1
		fi
		$MAKE distrib && \
		tar -czvf ${PKG_NAME}-${TAG}.tar.gz ${PKG_NAME}-${TAG} && \
		mv ${PKG_NAME}-${TAG}.tar.gz ${my_SRC_PATH}/
		# scp
	fi
	${GIT} clean -fdx
}

critical_section() {
	if ! [ -d "${BIN_PATH}" ]; then
		mkdir -p ${BIN_PATH}
	fi

	if ! [ -d "${SRC_PATH}" ]; then
		mkdir -p ${SRC_PATH}
	fi

	rebuilt=0
	for ref in $(awk '{print $1}' ${AUTO_BUILD_DIR}/queue); do
		QUEUE_TS=$(grep "^\<${ref}\> " ${AUTO_BUILD_DIR}/queue|awk '{print $2}')
		if [ $((${current_ts} - ${QUEUE_TS})) -gt $((${QUEUE_MINUTES} * 60)) ]; then
			rebuilt=1
			rebuild $ref
			### Remove ref from queue
			$SED -i -e "/^${ref}\ /d" ${AUTO_BUILD_DIR}/queue
		fi
	done

	if [ -n "${POST_CMD}" -a $rebuilt -eq 1 ]; then
		eval $POST_CMD
	fi
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

