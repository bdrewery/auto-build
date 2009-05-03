#! /bin/bash

. /home/bryan/auto-build/auto-build.conf

chmod u+x ${AUTO_BUILD_DIR}/hooks/post-update > /dev/null 2>&1
if ! [ -L ${GIT_DIR}/hooks/post-update ]; then
	rm -f ${GIT_DIR}/hooks/post-update > /dev/null 2>&1
	ln -s ${AUTO_BUILD_DIR}/hooks/post-update ${GIT_DIR}/hooks/post-update
fi

### Auto install the crontab too
TMPFILE=`mktemp /tmp/auto-build.XXXXXX` || exit 1
cat > $TMPFILE << EOF
$(crontab -l | sed -e "/${AUTO_BUILD_DIR//\//\\/}/run_queue.sh/d")
*/5 * * * * nice ${AUTO_BUILD_DIR}/run_queue.sh > /dev/null 2>&1
EOF
crontab $TMPFILE > /dev/null 2>&1
rm -f $TMPFILE > /dev/null 2>&1
