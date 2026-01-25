# Sample commands used for rsync
TOOLCHAIN_PATH=~/workspace/tools/arm-gnu-toolchain-12.2.rel1-x86_64-arm-none-linux-gnueabihf/bin
Obtained from doing:
```bash
cd ~/workspace
wget https://developer.arm.com/-/media/Files/downloads/gnu/12.2.rel1/binrel/arm-gnu-toolchain-12.2.rel1-x86_64-arm-none-linux-gnueabihf.tar.xz
tar -xf arm-gnu-toolchain-12.2.rel1-x86_64-arm-none-linux-gnueabihf.tar.xz
```

```bash
cd ~/workspace/kindle-bin/rsync

# Set the path to your new toolchain
TOOLCHAIN_PATH=~/workspace/arm-gnu-toolchain-12.2.rel1-x86_64-arm-none-linux-gnueabihf/bin

./configure --host=arm-none-linux-gnueabihf \
  CC="$TOOLCHAIN_PATH/arm-none-linux-gnueabihf-gcc" \
  --disable-openssl \
  --disable-xxhash \
  --disable-zstd \
  --disable-lz4

make
```

# Configure sample
```bash
./configure --host=armeb-linux-gnueabihf CC=armeb-linux-gnueabihf-gcc CXX=armeb-linux-gnueabihf-g++ --prefix=/usr/bin
```

# Little test
```bash
arm-linux-gnu-gcc -mfloat-abi=hard -mfpu=vfpv3 --sysroot=/home/{USER}/kindle-sysroot main.c -o cc-info
```

apparently many ways to do this
