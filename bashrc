set +h
umask 022
export CLFS_HOST=$(echo ${MACHTYPE} | sed "s/-[^-]*/-cross/")
