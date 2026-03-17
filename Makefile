.PHONY: ALL clean

ALL: output/floppinux.img

output/floppinux.img: build.sh syslinux.cfg
	docker build . --network=host -o type=local,dest=./output

clean:
	rm -rf build output
