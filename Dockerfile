FROM ubuntu:26.04 AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential bc flex bison cpio xz-utils wget curl \
    fakeroot dosfstools syslinux mtools libelf-dev libssl-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work
COPY . .
RUN ./build.sh

FROM scratch AS output
COPY --from=build /work/output/ /
