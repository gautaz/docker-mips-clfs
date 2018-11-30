FROM alpine:3.8

ENV CLFS_HOME=/home/clfs
ENV CLFS=${CLFS_HOME}/mnt

RUN \
    apk add --no-cache bash sudo && \
    addgroup clfs && \
    adduser -s /bin/bash -G clfs -D -k /dev/null clfs && \
    addgroup clfs wheel && \
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel

ADD --chown=clfs:clfs ["bashrc", "${CLFS_HOME}/.bashrc"]

USER clfs
WORKDIR "${CLFS}"

ENV PS1='\u:\w\$ '
ENV LC_ALL=POSIX
ENV PATH="${CLFS}/cross-tools/bin:${PATH}"

# clfs account permissions && CLFS host requirements
RUN \
    sudo chown -R clfs: "${CLFS_HOME}" && \
    sudo apk add --no-cache build-base bash bzip2 coreutils curl diffutils findutils grep gzip gawk m4 ncurses-dev sed patch sudo tar texinfo xz

# needed source packages
ARG BINUTILS_VERSION=2.27
ARG BUSYBOX_VERSION=1.24.2
ARG GCC_VERSION=6.2.0
ARG GMP_VERSION=6.1.1
ARG IANA_ETC_VERSION=2.30
ARG LINUX_KERNEL_VERSION=4.9.22
ARG MPC_VERSION=1.0.3
ARG MPFR_VERSION=3.1.4
ARG MUSL_VERSION=1.1.16

RUN \
    sudo apk add --no-cache curl xz && \
    mkdir -p "${CLFS}/sources" && \
    curl -L "http://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.bz2" | tar xjf - -C "${CLFS}/sources" && \
    curl -L "http://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2" | tar xjf - -C "${CLFS}/sources" && \
    curl -L "http://gcc.gnu.org/pub/gcc/releases/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.bz2" | tar xjf - -C "${CLFS}/sources" && \
    curl -L "http://ftp.gnu.org/gnu/gmp/gmp-${GMP_VERSION}.tar.bz2" | tar xjf - -C "${CLFS}/sources" && \
    curl -L "http://sethwklein.net/iana-etc-${IANA_ETC_VERSION}.tar.bz2" | tar xjf - -C "${CLFS}/sources" && \
    curl -L "http://www.kernel.org/pub/linux/kernel/v4.x/linux-${LINUX_KERNEL_VERSION}.tar.xz" | tar xJf - -C "${CLFS}/sources" && \
    curl -L "https://ftp.gnu.org/gnu/mpc/mpc-${MPC_VERSION}.tar.gz" | tar xzf - -C "${CLFS}/sources" && \
    curl -L "http://ftp.gnu.org/gnu/mpfr/mpfr-${MPFR_VERSION}.tar.bz2" | tar xjf - -C "${CLFS}/sources" && \
    curl -L "http://www.musl-libc.org/releases/musl-${MUSL_VERSION}.tar.gz" | tar xzf - -C "${CLFS}/sources" && \
    test `curl -L http://patches.clfs.org/embedded-dev/iana-etc-${IANA_ETC_VERSION}-update-2.patch | tee /tmp/iana-etc.patch | md5sum | cut -d' ' -f1` = "8bf719b313053a482b1e878b75dfc07e" && \
    patch -p1 -d "${CLFS}/sources/iana-etc-${IANA_ETC_VERSION}" < /tmp/iana-etc.patch && \
    rm /tmp/iana-etc.patch

# cross-compile tools
ARG CLFS_ABI=64
ARG CLFS_TARGET=mips64-linux-musl
ARG CLFS_ARCH=mips
ARG CLFS_ENDIAN=big
ARG CLFS_MIPS_LEVEL=3
ARG CLFS_FLOAT=hard

ENV CLFS_ABI=${CLFS_ABI}
ENV CLFS_TARGET=${CLFS_TARGET}
ENV CLFS_ARCH=${CLFS_ARCH}
ENV CLFS_ENDIAN=${CLFS_ENDIAN}
ENV CLFS_MIPS_LEVEL=${CLFS_MIPS_LEVEL}
ENV CLFS_FLOAT=${CLFS_FLOAT}

RUN \
    mkdir -p "${CLFS}/cross-tools/${CLFS_TARGET}" && \
    ln -sfv . "${CLFS}/cross-tools/${CLFS_TARGET}/usr"

# cross linux headers
RUN \
    ( \
        cd "${CLFS}/sources/linux-${LINUX_KERNEL_VERSION}" && \
        make mrproper && make ARCH=${CLFS_ARCH} headers_check && \
        make ARCH=${CLFS_ARCH} INSTALL_HDR_PATH=${CLFS}/cross-tools/${CLFS_TARGET} headers_install \
    )

# cross binutils
RUN \
    mkdir -p "${CLFS}/sources/binutils-build" && \
    ( \
        cd "${CLFS}/sources/binutils-build" && \
        ../binutils-${BINUTILS_VERSION}/configure \
            --prefix=${CLFS}/cross-tools \
            --target=${CLFS_TARGET} \
            --with-sysroot=${CLFS}/cross-tools/${CLFS_TARGET} \
            --disable-nls \
            --disable-multilib && \
        make configure-host && \
        make && \
        make install \
    )

# cross gcc static
RUN \
    ( \
        cd "${CLFS}/sources/gcc-${GCC_VERSION}" && \
        ln -s "${CLFS}/sources/mpfr-${MPFR_VERSION}" mpfr && \
        ln -s "${CLFS}/sources/gmp-${GMP_VERSION}" gmp && \
        ln -s "${CLFS}/sources/mpc-${MPC_VERSION}" mpc \
    ) && \
    mkdir -p "${CLFS}/sources/gcc-build" && \
    ( \
        cd "${CLFS}/sources/gcc-build" && \
        ../gcc-${GCC_VERSION}/configure \
            --prefix=${CLFS}/cross-tools \
            --build=${CLFS_HOST} \
            --host=${CLFS_HOST} \
            --target=${CLFS_TARGET} \
            --with-sysroot=${CLFS}/cross-tools/${CLFS_TARGET} \
            --disable-nls  \
            --disable-shared \
            --without-headers \
            --with-newlib \
            --disable-decimal-float \
            --disable-libgomp \
            --disable-libmudflap \
            --disable-libssp \
            --disable-libatomic \
            --disable-libquadmath \
            --disable-threads \
            --enable-languages=c \
            --disable-multilib \
            --with-mpfr-include=$(pwd)/../gcc-${GCC_VERSION}/mpfr/src \
            --with-mpfr-lib=$(pwd)/mpfr/src/.libs \
            --with-abi=${CLFS_ABI} \
            --with-arch=mips${CLFS_MIPS_LEVEL} \
            --with-float=${CLFS_FLOAT} \
            --with-endian=${CLFS_ENDIAN} && \
        make all-gcc all-target-libgcc && \
        make install-gcc install-target-libgcc \
    )

# cross musl
RUN \
    ( \
        cd "${CLFS}/sources/musl-${MUSL_VERSION}" && \
        ./configure \
            CROSS_COMPILE=${CLFS_TARGET}- \
            --prefix=/ \
            --target=${CLFS_TARGET} && \
        make && \
        DESTDIR=${CLFS}/cross-tools/${CLFS_TARGET} make install \
    )

# cross gcc final
RUN \
    rm -rf "${CLFS}/sources/gcc-build" && \
    mkdir -p "${CLFS}/sources/gcc-build" && \
    ( \
        cd "${CLFS}/sources/gcc-build" && \
        ../gcc-${GCC_VERSION}/configure \
            --prefix=${CLFS}/cross-tools \
            --build=${CLFS_HOST} \
            --host=${CLFS_HOST} \
            --target=${CLFS_TARGET} \
            --with-sysroot=${CLFS}/cross-tools/${CLFS_TARGET} \
            --disable-nls \
            --enable-languages=c \
            --enable-c99 \
            --enable-long-long \
            --disable-libmudflap \
            --disable-multilib \
            --with-mpfr-include=$(pwd)/../gcc-${GCC_VERSION}/mpfr/src \
            --with-mpfr-lib=$(pwd)/mpfr/src/.libs \
            --with-abi=${CLFS_ABI} \
            --with-arch=mips${CLFS_MIPS_LEVEL} \
            --with-float=${CLFS_FLOAT} \
            --with-endian=${CLFS_ENDIAN} && \
        make && \
        make install \
    )

# toolchain environment
ENV CC="${CLFS_TARGET}-gcc --sysroot=${CLFS}/targetfs"
# ENV CXX="${CLFS_TARGET}-g++ --sysroot=${CLFS}/targetfs"
ENV AR="${CLFS_TARGET}-ar"
ENV AS="${CLFS_TARGET}-as"
ENV LD="${CLFS_TARGET}-ld --sysroot=${CLFS}/targetfs"
ENV RANLIB="${CLFS_TARGET}-ranlib"
ENV READELF="${CLFS_TARGET}-readelf"
ENV STRIP="${CLFS_TARGET}-strip"

SHELL ["/bin/bash", "-c"]

# target filesystem
RUN \
    mkdir -pv ${CLFS}/targetfs/{bin,boot,dev,etc,home,lib/{firmware,modules}} && \
    mkdir -pv ${CLFS}/targetfs/{mnt,opt,proc,sbin,srv,sys} && \
    mkdir -pv ${CLFS}/targetfs/var/{cache,lib,local,lock,log,opt,run,spool} && \
    install -dv -m 0750 ${CLFS}/targetfs/root && \
    install -dv -m 1777 ${CLFS}/targetfs/{var/,}tmp && \
    mkdir -pv ${CLFS}/targetfs/usr/{,local/}{bin,include,lib,sbin,share,src} && \
    ln -svf ../proc/mounts ${CLFS}/targetfs/etc/mtab

ADD --chown=clfs:clfs ["targetfs/passwd", "${CLFS}/targetfs/etc/passwd"]
ADD --chown=clfs:clfs ["targetfs/group", "${CLFS}/targetfs/etc/group"]

RUN \
    touch ${CLFS}/targetfs/var/log/lastlog && \
    chmod -v 664 ${CLFS}/targetfs/var/log/lastlog && \
    cp -v ${CLFS}/cross-tools/${CLFS_TARGET}/lib64/libgcc_s.so.1 ${CLFS}/targetfs/lib/ && \
    ${CLFS_TARGET}-strip ${CLFS}/targetfs/lib/libgcc_s.so.1

RUN \
    ( \
        cd "${CLFS}/sources/musl-${MUSL_VERSION}" && \
        ./configure \
            CROSS_COMPILE=${CLFS_TARGET}- \
            --prefix=/ \
            --disable-static \
            --target=${CLFS_TARGET} && \
        make && \
        DESTDIR=${CLFS}/targetfs make install-libs \
    )

RUN \
    ( \
        cd "${CLFS}/sources/busybox-${BUSYBOX_VERSION}" && \
        make distclean && \
        make ARCH="${CLFS_ARCH}" defconfig && \
        sed -i 's/\(CONFIG_\)\(.*\)\(INETD\)\(.*\)=y/# \1\2\3\4 is not set/g' .config && \
        sed -i 's/\(CONFIG_IFPLUGD\)=y/# \1 is not set/' .config && \
        sed -i 's/\(CONFIG_FEATURE_WTMP\)=y/# \1 is not set/' .config && \
        sed -i 's/\(CONFIG_FEATURE_UTMP\)=y/# \1 is not set/' .config && \
        sed -i 's/\(CONFIG_UDPSVD\)=y/# \1 is not set/' .config && \
        sed -i 's/\(CONFIG_TCPSVD\)=y/# \1 is not set/' .config && \
        make ARCH="${CLFS_ARCH}" CROSS_COMPILE="${CLFS_TARGET}-" && \
        make ARCH="${CLFS_ARCH}" CROSS_COMPILE="${CLFS_TARGET}-"\
            CONFIG_PREFIX="${CLFS}/targetfs" install && \
        cp -v examples/depmod.pl ${CLFS}/cross-tools/bin && \
        chmod -v 755 ${CLFS}/cross-tools/bin/depmod.pl \
    )

RUN \
    ( \
        cd "${CLFS}/sources/iana-etc-${IANA_ETC_VERSION}" && \
        make get && \
        make STRIP=yes && \
        make DESTDIR=${CLFS}/targetfs install \
    )

ADD --chown=clfs:clfs ["targetfs/fstab", "${CLFS}/targetfs/etc/fstab"]

ARG CLFS_PLATFORM=rbtx49xx

RUN \
    sudo apk add --no-cache bc && \
    ( \
        cd "${CLFS}/sources/linux-${LINUX_KERNEL_VERSION}" && \
        make mrproper && \
        make ARCH=${CLFS_ARCH} CROSS_COMPILE=${CLFS_TARGET}- ${CLFS_PLATFORM}_defconfig && \
        make ARCH=${CLFS_ARCH} CROSS_COMPILE=${CLFS_TARGET}- && \
        make ARCH=${CLFS_ARCH} CROSS_COMPILE=${CLFS_TARGET}- \
            INSTALL_MOD_PATH=${CLFS}/targetfs modules_install \
    )

RUN "${CLFS_TARGET}-objcopy" -S -O srec "${CLFS}/sources/linux-${LINUX_KERNEL_VERSION}/vmlinux" "${CLFS}/targetfs/boot/vmlinux.srec"

RUN \
    curl -L "http://git.clfs.org/?p=bootscripts-embedded.git;a=snapshot;h=HEAD;sf=tgz" | tar xzf - -C "${CLFS}/sources" && \
    ( \
        cd "${CLFS}/sources/bootscripts-embedded" && \
        make DESTDIR=${CLFS}/targetfs install-bootscripts \
    )
