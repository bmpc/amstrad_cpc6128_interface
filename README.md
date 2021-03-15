# Interface Amstrad CPC 6128 with an Arduino

The goal of this project is to interface with the Amstrad CPC 6128 expansion port using a Microcontroller (Arduino Mega) to transfer information (games :-)) between the CPC and a micro SD card.

<div style="text-align:center">
  <img src="/assets/circuit1.jpeg" alt="Breadboard circuit" width="40%" />
</div>

## Circuit and decoding logic

The Arduino Mega communicates with the CPC like any other peripheral device, using the IO port. In this case, we use port &FBD0 as its typically used for Serial communication: [http://cpctech.cpc-live.com/docs/iopord.html](http://cpctech.cpc-live.com/docs/iopord.html).

We can transfer bytes to/from peripheral devices using the **IN** and **OUT** Z80 CPU instructions:

    OUT &FBD0, value   // send byte
    value = INP(&FBD0) // receive byte

The decoding logic was implemented using just a couple of NOR gates and one AND gate with the relevant address and control lines. If bit 10 and bit 5 are reset, this means we are using an expansion peripheral and, more specifically, the serial port according to the CPC I/O port allocation. The other bits are ignored. Therefore, the decoding logic uses only these address lines.

The (**D0…D7**) are the data lines. These lines will contain the byte being transferred.

When there's an I/O request, the Z80 brings the **IOREQ** line low. The IN and OUT operations are identified by the **RD** and **WR** lines, respectively. When the CPU reads a given port with IN, the **RD** line is LOW; otherwise, it is high. 

Another important signal is the **M1** which stands for Machine cycle one. Each instruction cycle is composed of tree machine cycles: M1, M2 and M3. M1 is the "op code fetch" machine cycle. This signal is active low. We must make sure M1 is high when communicating with the Z80.

The final signal (and definitely the most interesting) is the **WAIT**. When this signal is low, it tells the CPU that the addressed memory or **I/O devices** are not ready for a data transfer. The CPU will continue to enter the WAIT state whenever this signal is active, effectively pausing the CPU.

While assembling the circuit, I discovered that some of the CPC 6128 lines required pull-up resistors. The interrupt line was being triggered without any reason because these pins were floating, namely the address lines A0, A5, A10, and the IOREQ line. I suspect this is related to the chip family I used: 74HC. Other similar projects (see references) used CMOS chips and didn't need any pull-up resistors.

Circuit components:
 - 220Ω resistor x 3
 - 10kΩ resistor x 1
 - NPN transistor x 1
 - 74HC21N x 1
 - 74HC27N x 1
 - Arduino Mega 2560 x 1
 - Breadboard x 1
 - Micro SD card reader x 1


## Synchronizing the Z80 with the arduino

Timing when communicating between Z80 IN/OUT instructions and the Arduino is critical. The Z80 is clocked at 4 MHz while the Arduino Mega (which I'm using for this project) is clocked at 16 MHz. However, this speed difference is not sufficient for the Arduino to reply to the Z80 in time or read the data bus before the Z80 moved on to do other things and released it. Hence, we must use the WAIT signal to pause the CPU while the Arduino does its job of a) putting a byte into the data bus or b) reading a byte from the data bus.

Whenever the decoding logic signals that a byte is being transferred (IN/OUT), an interrupt is triggered in the Arduino. We can then set the WAIT line LOW. Again, timing is the key. Setting the WAIT line LOW using software only after the interrupt is triggered is not an option because the Z80 WAIT state is sampled before we can reply.

Therefore, the interrupt signal itself is used to bring the WAIT line low. After this, we must find a way to release the WAIT line (set it HIGH) after the Arduino finishes processing the byte. This can be done using a transistor and a control line from the Arduino as a switch. The control line is connected to the Emitter, the interrupt line connected to the Base, and the WAIT line to the Collector.

This control line will always be active. This means the WAIT signal is also triggered if this control line is LOW and the interrupt is also triggered. When the Arduino is ready, it will bring the control line HIGH for a brief moment, giving enough time for the Z80 to process the byte (in case of an IN instruction). 

This *moment* is also crucial. If it's too long, the Arduino might not be ready to process the next interrupt. On the other hand, if it is too short, the Z80 might not have enough time to sample the data bus.

Studying the Z80 timing diagram for Input/Output cycles, we can see that the **In** is sampled from the data bus for a brief moment, and right after this, the IOREQ goes HIGH. 

I used this knowledge to release the Arduino line at just the right time. If the IOREQ line is HIGH, this means the interrupt line is no longer active. Right after pulling the control line HIGH, the interrupt line is polled continuously. When this signal changes, we can bring the control line LOW again to be ready for the next request/interrupt. Here is where we take advantage of the faster clock on the Arduino. Still, this poll needs to be done in AVR assembly to ensure the Arduino starts polling the line before the Z80 sets the IOREQ HIGH. Here is the code that releases the WAIT line:

    void releaseWaitAfterWrite() {
      __asm__ __volatile__(
        "SBI  PORTC, 0              \n" // Set bit 0 in PORTC - WAIT line HIGH 
        "SBIC PINE, 4               \n" // Skip next instruction if Bit 4 (Interrupt) is Cleared
        "RJMP .-4                   \n" // Relative Jump -4 bytes - 
        "LDI  r25, 0x00             \n" // Load r25 with 0x00 - B00000000
        "OUT  DDRA, r25             \n" // store r25 in DDRA - Set DDRA as output again (default)
        "CBI  PORTC, 0              \n" // Clear bit 0 in PORTC - WAIT line LOW 
        "SEI                        \n" // Set Global Interrupt
        
        :::"r25"
      );
    }
    

## Listing and copying files

Once we are capable of transferring bytes to and from the Arduino, we can do just about anything. I created a simple protocol to communicate with the Arduino using IN/OUT instructions. Using this protocol, I programmed two small Z80 assembly programs:
 - *dir* – lists all the files present on the root folder of the SD card
 - *copy* – which, provided with the filename as a parameter, copies the SD card file into the CPC disk drive.

Most games nowadays are compacted into ".DSK" files, a disk image format. The files must be extracted and placed on the SD card root.

Here are a couple of screenshots of these programs:

<div style="text-align:center">
  <img src="/assets/cpc_dir.jpeg" alt="dir cmd" width="60%" />
</div>

<div style="text-align:center">
  <img src="/assets/cpc_copy.jpeg" alt="copy cmd" width="60%" />
</div>

## Source code

This repository contains the following source files:
 * [cpc6128_interface.ino](/cpc6128_interface.ino) - C++ sketch responsible for communicating with the CPC and reading the micro SD card.
 * [dir.asm](/cpc_files/dir.asm) - Z80 assembly program to catalog the files on the SD card
 * [DIR.BAS](/cpc_files/DIR.BAS) - "dir" Basic entry program
 * [copy.asm](/cpc_files/copy.asm) - Z80 assembly program to copy a file by name
 * [COPY.BAS](/cpc_files/COPY.BAS) - "copy" Basic entry program


## Future work

 - Creating RSX extensions for the copy and dir programs that can be loaded automatically from the Arduino by emulating a CPC ROM. This way, there is no need to have the dir and copy programs in 3.5" disks. 
 - Creating a PCB based on an Arduino shield to make this project final and remove the breadboard (now covered in dust) from the back of my CPC.  
 - Support ".DSK" image files directly in the SD card

## Reference

 - [Universal Serial Interface for Amstrad CPC (a.k.a USIfAC)](http://retroworkbench.blogspot.com/p/universal-serial-interface-for-amstrad.html)
 - [Arduino IO card for the CPC6128](https://hackaday.io/project/169565-arduino-io-card-for-amstrad-cpc-6128)
