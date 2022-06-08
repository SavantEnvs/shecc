FROM --platform=linux/amd64 ubuntu:20.04 as builder

RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential qemu-user

ADD . /shecc
WORKDIR /shecc
RUN make config ARCH=arm
RUN make

RUN mkdir -p /deps
RUN ldd /shecc/out/shecc | tr -s '[:blank:]' '\n' | grep '^/' | xargs -I % sh -c 'cp % /deps;'

FROM ubuntu:20.04 as package

COPY --from=builder /deps /deps
COPY --from=builder /shecc/out/shecc /shecc/out/shecc
ENV LD_LIBRARY_PATH=/deps
