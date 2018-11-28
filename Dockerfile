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

# cross gcc
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
