# pluskb-protocol-analyzer

A protocol analyzer for Macintosh Plus/512k/128k keyboards.


## HOWTO

### Requirements

* PIC
   * Microchip MPASM (bundled with MPLAB)
      * Note that you **must** use MPLAB X version 5.35 or earlier or MPLAB 8 as later versions of MPLAB X have removed MPASM
   * A PIC12F1501 microcontroller
   * A device to program the PIC with
* Python
   * Python 3.x
   * PySerial


### Steps

* Build the code using Microchip MPASM and download the result into a PIC12F1501.
* Connect the Tx line to a UART on a PC.
* Run the Python code.


### Example

```
$ python3 -i analyzer-pluskb.py
>>> import serial
>>> KeyboardAnalyzer(serial.Serial(port='/dev/ttyS0', baudrate=115200, timeout=1)).run()
```


## Serial Protocol

* Uses 8-N-1 at 115200 baud.
* Analyzer sends the keyboard bytes as received.
   * It is not possible for a third party observer on the bus to know whether the Macintosh or the keyboard is driving the data line.
      * The Python code infers this from the LSb of the bytes received (the keyboard sets it, the Macintosh clears it).
      * This does not cover some of the bytes sent on powerup.
