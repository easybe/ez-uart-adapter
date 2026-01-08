# EZ USB-UART Adapter

This CH340C-based board can automatically power up a (5V) target when
starting a serial console session. This is achieved by leveraging the
fact that DTR/ is automatically asserted when opening a port with a
terminal emulator like `picocom` or `screen`.

To check the design, run:

    make check

To generate the files for manufacturing:

    make fab
