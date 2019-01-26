OpenOCD `remote_bitbang` Server
===============================

This folder contains a code for an OpenOCD `remote_bitbang` server.

`remote_bitbang` is an OpenOCD method to communicate simple commands to control
a JTAG interface through a remote process. In connection to a RISC-V Debug Module
design we may use the method to connect OpenOCD to a simulated Debug Module, and
hence test early on if the Debug Module works with OpenOCD.

An example here uses Verilator as the simulation engine. Its advantage is that we
can drive the simulated Debug Module directly from C/C++. With commercial simulation
engines, one would need to use either DPI or VPI interface.

Usage
-----

Three processes need to run:

- `remote_bitbang` server (we pair the bitbang server with the Verilator Debug
  Module model into a single process; with a commercial simulation engine there
  would be two process, one for the server and the other for simulation)

- OpenOCD server (that will connect to the `remote_bitbang` server)

- telnet session (that will connect to the OpenOCD server)

```
# Prerequisites
# -------------
sudo apt-get install libtool automake

# Install OpenOCD
# ---------------
cd ...
git clone  https://github.com/riscv/riscv-openocd && cd riscv-openocd
./bootstrap
./configure --enable-remote_bitbang
make

# Build Verilator model
# ---------------------
cd .../test/openocd/verilator
make build

...
```
