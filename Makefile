.PHONY: all clean

all: output/floppinux.img

output/floppinux.img: Dockerfile build.sh syslinux.cfg $(shell find rootfs_overrides -type f)
	docker build . --network=host -o type=local,dest=./output

clean:
	rm -rf build output
