#! /bin/bash

export PATH=/bin:/usr/bin:/usr/sbin:/sbin:/usr/local/bin
. /home/bryan/auto-build/auto-build.conf

current_ts=$(date +%s)

compile() {
  MAKEJOBS="-j4" ./configure && \
  cd $GIT_WORK_TREE && \
  $MAKE
  return $?
}

process_ref() {
  my_BIN_PATH=$1
  my_SRC_PATH=$2
  symlink=$3

  if ! [ -d "${my_BIN_PATH}" ]; then
    mkdir -p ${my_BIN_PATH} > /dev/null 2>&1
  fi

  cp ${PKG_NAME} ${PKG_NAME}.${UNAME}-${TAG} && \
  tar -czvf ${PKG_NAME}.${UNAME}-${TAG}.tar.gz ${PKG_NAME}.${UNAME}-${TAG} && \
  mv ${PKG_NAME}.${UNAME}-${TAG}.tar.gz ${my_BIN_PATH}/ && \
  # Only symlink full releases \
  [ $symlink -eq 1 ] && \
  echo ${PKG_NAME}.${UNAME}-${TAG}.tar.gz > ${my_BIN_PATH}/${PKG_NAME}.${UNAME}-latest.txt

  ### Do source

  #ln -fs ${PKG_NAME}.${UNAME}-${TAG}.tar.gz ${my_BIN_PATH}/${PKG_NAME}.${UNAME}-latest.tar.gz
  # scp
  if [ -f Makefile -a "$DO_SRC" = "1" ]; then
    if ! [ -d "${my_SRC_PATH}" ]; then
      mkdir -p ${my_SRC_PATH} > /dev/null 2>&1
    fi
    $MAKE distrib && \
    tar -czvf ${PKG_NAME}-${TAG}.tar.gz ${PKG_NAME}-${TAG} && \
    mv ${PKG_NAME}-${TAG}.tar.gz ${my_SRC_PATH}/ && \
    # Only symlink full releases \
    [ $symlink -eq 1 ] && \
    echo ${PKG_NAME}-${TAG}.tar.gz > ${my_SRC_PATH}/${PKG_NAME}-latest.txt && \
    echo ${PKG_NAME}-${TAG}.tar.gz > ${my_SRC_PATH}/${PKG_NAME}-${TAG}.txt
    #ln -fs ${PKG_NAME}-${TAG}.tar.gz ${my_SRC_PATH}/${PKG_NAME}-latest.tar.gz && \
    # scp
  fi
}

rebuild() {
	ref=$1
	cd $GIT_WORK_TREE
	${GIT} clean -ffdx
	${GIT} checkout -f $ref
	TAG=$(${GIT} describe $ref)
        UNAME=$(uname -s)

        is_tagged=0
        ### Is this a tag?
        ${GIT} describe --exact-match $ref > /dev/null 2>&1
        if [ $? -eq 0 ]; then
          is_tagged=1
        fi

        ref_is_tag=0
        if [ "$ref" = "$TAG" ]; then
          ref_is_tag=1
        fi

        compile
        if [ $? -eq 0 ]; then
          if [ $ref_is_tag -eq 0 ]; then
            ### Process branch
            process_ref ${BIN_PATH}/${ref} ${SRC_PATH}/${ref} 1
          fi

          ### Is this a tag?
          if [ $is_tagged -eq 1 ]; then
            ! (echo "$TAG"|grep -q -- "-rc[0-9]*\$") && symlink=1 || symlink=0
            process_ref ${BIN_PATH}/tags ${SRC_PATH}/tags $symlink
          fi
        fi

	${GIT} clean -ffdx
}

sync() {
  redo=1
  while [ $redo -eq 1 ]; do
    eval $@
    if [ $? -eq 0 ]; then
      redo=0
    else
      sleep 20
    fi
  done
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
		QUEUE_TS=$(grep "^${ref} " ${AUTO_BUILD_DIR}/queue|awk '{print $2}')
		if [ $((${current_ts} - ${QUEUE_TS})) -gt $((${QUEUE_MINUTES} * 60)) ]; then
			rebuilt=1
			rebuild $ref
			### Remove ref from queue
			$SED -i -e "/^${ref}\ /d" ${AUTO_BUILD_DIR}/queue
		fi
	done

	if [ $rebuilt -eq 1 ]; then
          if [ $DO_SRC -eq 1 ]; then
#            echo rsync -avHc -e "ssh -i $SSH_KEY" ${SRC_PATH}/ ${SITE_MAIN}/src/
            echo "Rsyncing Source to mirror"
            sync "rsync -avHc --del --exclude '*.txt' -e 'ssh -i $SSH_KEY' ${SRC_PATH}/ ${SITE_MIRROR}/src/"
          fi
#          echo rsync -avHc --del -e "ssh -i $SSH_KEY" ${BIN_PATH}/ ${SITE_MAIN}/bins/$(uname -s)/
#          echo rsync -avHc -e "ssh -i $SSH_KEY" ${FILE_PATH}/ ${SITE_MAIN}/
          echo "Rsyncing Binary metadata to main site"
          sync "rsync -avHc --exclude '*.tar.gz' --include '*.txt' -e 'ssh -i $SSH_KEY' ${FILE_PATH}/ ${SITE_MAIN}/"
          echo "Rsyncing Binaries to mirror"
          sync "rsync -avHc --del --exclude '*.txt' -e 'ssh -i $SSH_KEY' ${BIN_PATH}/ ${SITE_MIRROR}/bins/$(uname -s)/"
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

