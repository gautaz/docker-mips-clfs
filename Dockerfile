FROM alpine:3.8

ARG CLFS_ABI=N64
ARG CLFS_TARGET=mips64-linux-musl
ARG CLFS_ARCH=mips
ARG CLFS_ENDIAN=big
ARG CLFS_MIPS_LEVEL=3
ARG CLFS_FLOAT=hard

ARG BINUTILS_VERSION=2.27
ARG BUSYBOX_VERSION=1.24.2
ARG GCC_VERSION=6.2.0
ARG GMP_VERSION=6.1.1
ARG IANA_ETC_VERSION=2.30
ARG LINUX_KERNEL_VERSION=4.9.22
ARG MPC_VERSION=1.0.3
ARG MPFR_VERSION=3.1.4
ARG MUSL_VERSION=1.1.16

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

ENV CLFS_ABI=${CLFS_ABI}
ENV CLFS_TARGET=${CLFS_TARGET}
ENV CLFS_ARCH=${CLFS_ARCH}
ENV CLFS_ENDIAN=${CLFS_ENDIAN}
ENV CLFS_MIPS_LEVEL=${CLFS_MIPS_LEVEL}
ENV CLFS_FLOAT=${CLFS_FLOAT}

RUN \
    set -x && \
    sudo chown -R clfs: "${CLFS_HOME}" && \
    sudo apk add --no-cache build-base bash bzip2 coreutils curl diffutils findutils grep gzip gawk m4 ncurses-dev sed patch sudo tar texinfo xz && \
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
    test `curl -L http://patches.clfs.org/embedded-dev/iana-etc-${IANA_ETC_VERSION}-update-2.patch | tee "${CLFS}/sources/iana-etc-${IANA_ETC_VERSION}-update-2.patch" | md5sum | cut -d' ' -f1` = "8bf719b313053a482b1e878b75dfc07e" && \
    mkdir -p "${CLFS}/cross-tools/${CLFS_TARGET}" && \
    ln -sfv . "${CLFS}/cross-tools/${CLFS_TARGET}/usr"
