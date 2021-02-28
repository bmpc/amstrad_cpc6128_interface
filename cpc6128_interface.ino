
#include <SPI.h>
#include <SD.h>

//#define DEBUG 1 // debug on USB Serial

#ifdef DEBUG
  #define DEBUG_PRINT(x)  Serial.print (x)
  #define DEBUG_PRINT_HEX(x)  Serial.print (x, HEX)
  #define DEBUG_PRINTLN(x)  Serial.println (x)
  #define DEBUG_PRINTLN_HEX(x)  Serial.println (x, HEX)
#else
  #define DEBUG_PRINT(x)
  #define DEBUG_PRINT_HEX(x)
  #define DEBUG_PRINTLN(x)
  #define DEBUG_PRINTLN_HEX(x)
#endif

/*
   SD card attached to SPI bus as follows (mega):
 ** MOSI - pin 50
 ** MISO - pin 51
 ** CLK - pin 52
 ** CS - pin 53 (for MKRZero SD: SDCARD_SS_PIN)
*/

// Pin Mapping
#define DATA_0 22 // PA0
#define DATA_1 23 // PA1
#define DATA_2 24 // PA2
#define DATA_3 25 // PA3
#define DATA_4 26 // PA4
#define DATA_5 27 // PA5
#define DATA_6 28 // PA6
#define DATA_7 29 // PA7

#define INT     2 // PE4

#define WAIT   37 // PC0
#define RD     36 // PC1
#define BRST   35 // PC2
#define ADDR_0 34 // PC3

#define FILE_BUFFER 128

#define CMD_DIR 1
#define CMD_COPY 2

volatile byte iorequest = 0;

byte cmd = 0; // current command: 1 - dir() ; 2 - copy()

class FileBuffer {
  char mFilename[12];
  uint8_t mFilenameIndex = 0;
  uint16_t mFileCursor = 0;
  uint16_t mBufferIndex = 0;
  uint16_t mFileSize = 0;
  bool mReady = false;

  File mFile;
  byte mBuffer[FILE_BUFFER];

  bool openFile() {
    mFile = SD.open(mFilename);
    if (mFile && mFile.available()) {
      mFileSize = mFile.size();
      DEBUG_PRINT("Opening file '");
      DEBUG_PRINT(mFilename);
      DEBUG_PRINT("' with size = ");
      DEBUG_PRINTLN(mFileSize);
      return true;
    } else {
      DEBUG_PRINT("File not found - ");
      DEBUG_PRINTLN(mFilename);
      return false;
    }
  }

public:
  FileBuffer() {
  }

  void appendToFilename(char c) {
    mFilename[mFilenameIndex++] = c;
  }

  void reset() {
    memset(mFilename, 0, 12);
    mFilenameIndex = 0;
    mFileCursor = 0;
    mBufferIndex = 0;
    mFileSize = 0;
    mFile.close();
    mReady = false;
  }

  uint16_t getFileSize() {
    return mFileSize;
  }

  byte getNextByte() {
    if (mReady && (mFileCursor < (mFileSize + 2))) { // +2 from file size word
      // add file size on the first 2 bytes
      
      if (mFileCursor == 0 || mBufferIndex == FILE_BUFFER) {
        DEBUG_PRINT("Buffering file content. Current Position: ");
        mBufferIndex = 0;
        DEBUG_PRINTLN(mFileCursor);
        mFile.read(mBuffer, FILE_BUFFER); // fill buffer
      }

      byte b;
      if (mFileCursor == 0) {
        b = (uint8_t) (mFileSize >> 8); // high byte
      } else if (mFileCursor == 1) {
        b = (uint8_t) (mFileSize & 0x00FF); // low byte
      } else {
        b = mBuffer[mBufferIndex++];  
      }

      mFileCursor++;
      return b;
    } else {
      DEBUG_PRINTLN("Error - no more data!");
      return 0;
    }
  }

  bool hasMoreBytes() {
    return mFileCursor < (mFileSize + 2);
  }

  void init() {
    mFilename[mFilenameIndex] = 0;

    mReady = openFile();
  }

  bool exists() {
    return mReady;
  }
};


class FileInfo {
private:
  char mFilename[12];
  uint8_t mSize = 0;
  uint8_t mFilenameIndex = 0;

public:
  FileInfo() {  
  }
  
  FileInfo(char* filename, uint32_t size) {
      strcpy(mFilename, filename);
      mSize = size;
  }
  
  bool available() {
    return strlen(mFilename) > 0 && mFilenameIndex < 12; // < 12 including the suffix byte for size in kb
  }

  char nextChar() {
    if (available()) {
      if (mFilenameIndex == 11) {
        mFilenameIndex++;
        return mSize == 0 ? 1 : mSize;
      }
      return mFilename[mFilenameIndex++];
    } else {
      return 0;
    }
  }
};

// File iterator to send filenames to CPC. It keeps the state of the what was already sent and the current file.
class FileIterator {
private:
  File mRoot;
  FileInfo mFileInfo;

  void nextFile(FileInfo* outFileInfo) {
    while (true) {
      File entry =  mRoot.openNextFile();
      if (! entry) {
        // no more files
        outFileInfo = nullptr;
        break;
      }
      // ignores files bigger than 255 KB
      int sizeInKb = entry.size() / 1024;
      if (!entry.isDirectory() && (sizeInKb <= 255)) {
        char normalizedName[12];
        normalizeFilename(entry.name(), normalizedName);
        *outFileInfo = FileInfo(normalizedName, (uint8_t) sizeInKb);
        break;
      }

      entry.close();
    }
  }

  void normalizeFilename(char* name, char* outNormalizedName) {
    int name_len = strlen(name);

    // find last '.' char index
    int i_sep = name_len - 1;
    while (name[i_sep] != '.' && i_sep >= 0) {
      i_sep--;
    }

    // initialize array with spaces
    for (int i=0;i<11;i++) {
        outNormalizedName[i] = 0x20;
    }
    outNormalizedName[11] = 0;

    // set extension part
    for (int j=8, i=i_sep+1; j < 11 && i < name_len; j++, i++) {
      outNormalizedName[j] = name[i];
    }
    
    // set name part
    for (int j=0; j < i_sep; j++) {
      outNormalizedName[j] = name[j];
    }    
  }

public:
  FileIterator() {
  }

  void init(File root) {
    mRoot = root;
  }
  
  // closes the root file 
  void release() {
    mRoot.close();
  }

  char nextByte() {
    if (!mFileInfo.available()) {
      nextFile(&mFileInfo);
      if (!mFileInfo.available()) {
        return 0;
      }
    }
    return mFileInfo.nextChar();
  }

  bool hasBytes() {
    if (!mFileInfo.available()) {
      nextFile(&mFileInfo);
      if (!mFileInfo.available()) {
        return false;
      }
    }
    return true;
  }
};

FileIterator fileIterator;
FileBuffer fileBuffer;

void setup() {

  pinMode(ADDR_0, INPUT);
  pinMode(INT, INPUT_PULLUP);
  pinMode(RD, INPUT);
  
  digitalWrite(BRST, HIGH);
  pinMode(BRST, OUTPUT);
  
  digitalWrite(WAIT, LOW);
  pinMode(WAIT, OUTPUT);
  
  for ( int pin = DATA_7; pin >= DATA_0; pin-- ) {
    pinMode(pin, INPUT);
  }

  pinMode(LED_BUILTIN, OUTPUT);

  attachInterrupt(digitalPinToInterrupt(INT), ioreq, RISING);

  // Open serial communications and wait for port to open:
  Serial.begin(9600);
  while (!Serial) {
    ; // wait for serial port to connect. Needed for native USB port only
  }

  if (!SD.begin(53)) {
    DEBUG_PRINTLN("SD card initialization failed!");
    while (1);
  }
  DEBUG_PRINTLN("SD card initialization complete.");
}

void ioreq() {
  iorequest++;
}

void loop() {
  if (iorequest == 1) {
    if (digitalRead(ADDR_0) == HIGH) {
      if (digitalRead(RD) == HIGH) {
        // Byte sent from cpc to control port
        readControlPort();
      } else {
        // Byte was requested by cpc from the control port
        writeToControlPort();        
      }
    } else {
      if (digitalRead(RD) == HIGH) {
        // Byte sent from cpc to data port
        readDataPort();
      } else {
        // Byte was requested by cpc from the data port
        writeToDataPort();
      }
    }

    iorequest = 0;
  }
}

void writeToControlPort() {
  DEBUG_PRINTLN("Writing to Control Port...");
  
  byte byte_to_send;

  switch(cmd) {
    case CMD_DIR:
      byte_to_send = fileIterator.hasBytes() ? 1 : 0;

      if (byte_to_send == 0) {
        fileIterator.release();
      }
      break;
    case CMD_COPY:
      byte_to_send = fileBuffer.exists() ? 1 : 0;

      if (!fileBuffer.exists()) {
        fileBuffer.reset();
      }

      break;
    default:
      break;
  }

  DEBUG_PRINT("[CTR] <-- 0x");
  DEBUG_PRINTLN_HEX(byte_to_send);

  writeByte(byte_to_send);

  releaseWaitAfterWrite();
}

void readControlPort() {
  DEBUG_PRINTLN("Reading from Control Port...");

  cmd = readByte();

  // assert command
  switch(cmd) {
    case CMD_DIR:
      DEBUG_PRINTLN("Received CPC command [DIR]");
      fileIterator.init(SD.open("/"));
      
      break;
   case CMD_COPY:
      DEBUG_PRINTLN("Received CPC command [COPY]");
      break;
    default:
      break; 
  }

  releaseWaitAfterRead();
}

void writeToDataPort() {
  DEBUG_PRINTLN("Writing to Data Port...");
      
  byte byte_to_send;
  switch(cmd) {
    case CMD_DIR:
      byte_to_send = fileIterator.nextByte();
      break;
    case CMD_COPY:
      byte_to_send = fileBuffer.getNextByte();

      if (!fileBuffer.hasMoreBytes()) {
        fileBuffer.reset();
      }
      break;
    default:
      break;
  } 

  DEBUG_PRINT("[DATA] <-- 0x");
  DEBUG_PRINTLN_HEX(byte_to_send);

  writeByte(byte_to_send);

  releaseWaitAfterWrite();
}

void readDataPort() {
  DEBUG_PRINTLN("Reading from Data Port...");

  byte b = readByte();
  
  if (cmd == CMD_COPY) {
    DEBUG_PRINT("[DATA] --> 0x");
    DEBUG_PRINTLN_HEX(b);

    fileBuffer.appendToFilename(b);

    if (b == 0) {
      fileBuffer.init();
    }
  }

  releaseWaitAfterRead();
}

byte readByte() {
  byte recvByte=0;
  __asm__ __volatile__(
      ".equ PORTA, 0x02           \n"
      ".equ PORTC, 0x08           \n"
      ".equ DDRA,  0x01           \n"
      ".equ PINA,  0x00           \n"
      ".equ PINE,  0x0c           \n"
      "CLI                        \n" // Clear Global Interrupt
      "LDI  r24, 0                \n" // Load r24 with 0
      "OUT  DDRA, r24             \n" // Set all pins to inputs
      "IN   %0, PINA              \n" // read PINA (0-7) to <<VAR>>
      
      : "=d" (recvByte)::"r24"
  );
  return recvByte;
}

void releaseWaitAfterRead() {
  __asm__ __volatile__(
      "SBI  PORTC, 0              \n" // Set bit 0 in PORTC - WAIT line HIGH 
      "SBIC PINE, 4               \n" // Skip next instruction if Bit 4 (Interrupt) is Cleared
      "RJMP .-4                   \n" // Relative Jump -4 bytes - 
      "CBI  PORTC, 0              \n" // Clear bit 0 in PORTC - WAIT line LOW
      "SEI                        \n" // Set Global Interrupt
  );
}

void writeByte(byte toSend) {
  __asm__ __volatile__(
      ".equ PORTA, 0x02           \n"
      ".equ PORTC, 0x08           \n"
      ".equ DDRA,  0x01           \n"
      ".equ PINE,  0x0c           \n"
      "CLI                        \n" // Clear Global Interrupt
      "LDI  r25, 0xFF             \n" // Load r25 with 0xFF - B11111111
      "OUT  DDRA, r25             \n" // store r25 in DDRA - Set DDRA as output
      "MOV  r25, %0               \n" // move byte register to r25
      "OUT  PORTA, r25            \n" // Write byte to PORTA
        
      ::"r" (toSend):"r25"
  );
}

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
