#!/usr/bin/env bash

saveenv=${1:-build.env}

echo "INFO: Saving toolchain build environment variables into $saveenv"

rm -f $saveenv
touch $saveenv
for enval in TOOLTYPE TOOLHOST TOOLVER MULTILIBGEN DOMULTILIB \
    DOCONF DOSTRIP DOLLVM DOBUILD DOARCHIVE DOLIBNCRT DOLIBDEBUG \
    LIBNCRTBLDCFG DODOC DOCLEAN DEFRVCFG DOPYTHON JOBS DOREBUILD ; do
    # save environment variable
    echo "$enval=\"`printenv $enval`"\" >> $saveenv
done

exit 0
