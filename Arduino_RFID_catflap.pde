#include <EEPROM.h>

/*
Some of this is written by Sander Boele <sanderboele@gmail.com>, some other code is stolen from the
internet and is written by various authors. Thank you!

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

*/
const byte redLed = 11; 
const byte greenLed = 12; //status LED pin
const byte blueLed = 13;

const byte motorLeft = 9; //black, L293D pin 7
const byte motorRight = 10; //red, L293D pin 3
const byte motorTime = 100; //number of msec the motor is running for flap to open or close

//digital pin 2 and 3 are interrupts 0 and 1 for operationalmode and programming mode

//define the pins where the dipswitches or regular switches are located for unlocktime
const byte DIPS[4] = { 4, 5, 6, 7 };
const byte DIPSIZE = 4;

const int DEBOUNCE_TIME = 500; //msec debounce timer

boolean flapOpen = true; //asume that initial flap state is open, so the program closes it.
volatile byte operationalMode = 0; // 0=normal, 1=always open, 2=programming mode triggered by interrupt

volatile static unsigned long lastInterruptTime = 0;
volatile static unsigned long lastInterruptTime2 = 0;

int getUnlockTime()
{
  //reads the unlocktime from a dipswitch, or some other switches.
  int unlockTime = 0;
  for (int thisDip = 0; thisDip < DIPSIZE; thisDip++)
  {
    /* 
    dip 0 = 2^0 = 1
    dip 1 = 2^1 = 2
    dip 2 = 2^2 = 4
    dip 3 = 2^3 = 8
    */
    if (digitalRead(DIPS[thisDip]) == HIGH)
    {
      byte increment = 0;
      switch (thisDip)
      {
        case 0:
          increment = 1;
          break;
        case 1:
          increment = 2;
          break;
        case 2:
          increment = 4;
          break;
        case 3:
          increment = 8;
          break;
      }
      unlockTime = unlockTime + increment; 
    }
  }
  return unlockTime;
}  
//adapted from the Arduino playground http://www.arduino.cc/playground/Code/ID12
bool readTag(byte *tagBytes)
{
  byte val = 0;
  byte checksum = 0;
  byte bytesRead = 0;
  byte tempByte = 0;
  char tagValue[11];
  if (Serial.available() > 0)
  {
    if ((val = Serial.read()) == 2) 
    {
      bytesRead = 0;
      while (bytesRead < 12) 
      {
        if( Serial.available() > 0) 
        { 
          val = Serial.read();
          if((val == 0x0D)||(val == 0x0A)||(val == 0x03)||(val == 0x02)) 
            break;
          if (bytesRead < 10)
            tagValue[bytesRead] = val;
          if ((val >= '0') && (val <= '9')) 
            val = val - '0';
          else if ((val >= 'A') && (val <= 'F')) 
            val = 10 + val - 'A';
          if (bytesRead & 1 == 1) 
          {
            tagBytes[bytesRead >> 1] = (val | (tempByte << 4));
            if (bytesRead >> 1 != 5) 
              checksum ^= tagBytes[bytesRead >> 1];
            else
              tempByte = val;
          }
          bytesRead++;
          if (bytesRead == 12) 
          {
            tagValue[10] = '\0';  
            Serial.print("Tag value: ");
            Serial.println(tagValue);
            Serial.print("Checksum: ");
            Serial.print(tagBytes[5], HEX);
            Serial.println(tagBytes[5] == checksum ? " -- passed." : " -- error.");
            Serial.print("Tagbyte value: ");
            for (int k=0; k<=5; k++)
              Serial.print(tagBytes[k], HEX);
            Serial.println();
            if (tagBytes[5] == checksum)
              return true;
          }
        }
      }
      bytesRead = 0;
    }
  }
  return false;
}

void openFlap(byte seconds) //opens flap for the supplied amount of time
{
  digitalWrite(motorLeft, HIGH);
  delay(motorTime);
  digitalWrite(motorLeft, LOW);
  Serial.println("Flap opened");
  digitalWrite(redLed, LOW);
  digitalWrite(greenLed, HIGH);
  flapOpen = true;
  delay((seconds * 1000)+10);
  digitalWrite(motorRight, HIGH);
  delay(motorTime);
  digitalWrite(motorRight, LOW);
  Serial.println("Flap closed");
  digitalWrite(redLed, HIGH);
  digitalWrite(greenLed, LOW);
  flapOpen = false;
} 

void openFlapPermanently()
{
  if (!flapOpen)
  {
    Serial.println("Opening flap permanently.");
    digitalWrite(motorLeft, HIGH);
    delay(motorTime);
    digitalWrite(motorLeft, LOW);
    flapOpen = true;
    digitalWrite(redLed, LOW);
    digitalWrite(greenLed, HIGH);
  }
}

void closeFlap()
{
 if (flapOpen)
 {
   Serial.println("Closing flap.");
   digitalWrite(motorRight, HIGH);
   delay(motorTime);
   digitalWrite(motorRight, LOW);
   flapOpen = false;
   digitalWrite(greenLed, LOW);
   digitalWrite(redLed, HIGH); 
  } 
}

boolean checkTag(byte tagBytes[])
{
  boolean match = false;
  byte numTags = EEPROM.read(0);
  if (numTags > 0)
  {
    Serial.print("Following number of tags appear to be in EEPROM: ");
    Serial.println(numTags, DEC);
    for (int tag=0; tag < numTags; tag++)
    {
      Serial.print("Checking tag # ");
      Serial.println(tag);
      for (int i=(tag * 5)+1; i<= (tag * 5) + 5; i++)
      {  
        if (tagBytes[(i-1)%5] == EEPROM.read(i))
          match = true;
        else
        {
          Serial.println("tag NOT in EEPROM");
          match = false;
          break;
        }
      }
      if (match)
      { 
        Serial.println("tag found in EEPROM");
        return true;
      }
    }
  }
  else
    Serial.println("No tags in EEPROM");
  return false;
}

void writeTag(byte tagValue[])
{  
  /* The first value in EEPROM is the number of learned tags
   (#tags * 5) + 1 is the first position to write a new tag to */

   byte numTags = EEPROM.read(0);
   if (!(checkTag(tagValue))) //if the tag is not already in EEPROM
   {
     EEPROM.write(0, numTags+1);
     for (int i=(numTags * 5) +1; i<= (numTags * 5) + 5; i++)
     {  
       Serial.print("Now writing to EEPROM location: ");
       Serial.print(i, DEC);
       Serial.print(" with value: ");
       Serial.println(tagValue[(i-1)%5], HEX);
       EEPROM.write(i, tagValue[(i-1)%5]);
     }
   }
}

void normalOperation()
{
  byte tagBytes[6];
  if (flapOpen)
    closeFlap();
  while (readTag(&tagBytes[0]))
  {
    if (checkTag(tagBytes))
    {
      Serial.println("Authorized tag");
      openFlap(getUnlockTime());
    }
    else
      Serial.println("Tag not authorized");
    Serial.flush();
  }
}


void hitProgrammingMode()
{
  unsigned long interruptTime2 = millis(); 
  if (interruptTime2 - lastInterruptTime2 > DEBOUNCE_TIME)
  {
    operationalMode = 2;
    lastInterruptTime2 = interruptTime2;
  }
}

void programmingMode()
{
  byte tagBytes[6]= {0,0,0,0,0,0};
  Serial.println("Programming mode");
  byte numTags = EEPROM.read(0);
  Serial.print("Following nr of tags in EEPROM: ");
  Serial.println(numTags, DEC);
  byte newNumTags = numTags;
  digitalWrite(redLed, LOW);
  digitalWrite(greenLed, LOW);
  digitalWrite(blueLed, HIGH);
  unsigned long startTime = millis();
  while ((newNumTags == numTags) &&  (millis() < (startTime + 10000)))
  {
    if (readTag(&tagBytes[0]))
      writeTag(tagBytes);
    newNumTags = EEPROM.read(0);
  }
  operationalMode = 0;
  digitalWrite(blueLed, LOW);
  digitalWrite(redLed, HIGH);
}

void changeOperationalMode() //toggle between normal and always open via interrupt 0 = digital pin2
{
  unsigned long interruptTime = millis();
  
  if (interruptTime - lastInterruptTime > DEBOUNCE_TIME)
  {
    Serial.println("changeOperationalMode triggered");
    Serial.flush();
    if (operationalMode == 0)
    {
      operationalMode = 1; //goto always open
      Serial.println("Always open mode");
    }
    else
    {
      operationalMode = 0; //goto normal
      Serial.println("Going to normal operation");
    }
    lastInterruptTime = interruptTime;
  }
}

void setup()   
{ 
  attachInterrupt(0, changeOperationalMode, RISING); //button for toggeling operational mode (dig pin 2)
  attachInterrupt(1, hitProgrammingMode, RISING); //button for toggeling to programming mode (dig pin 3)
  pinMode(motorLeft, OUTPUT);
  pinMode(motorRight, OUTPUT);
  pinMode(greenLed, OUTPUT);  
  pinMode(redLed, OUTPUT);  
  pinMode(blueLed, OUTPUT);  
  Serial.begin(9600);
  Serial.println("Program started");
  digitalWrite(motorRight, LOW);
  digitalWrite(motorLeft, LOW);
  for (int thisDip = 0; thisDip < DIPSIZE; thisDip++)
    pinMode(DIPS[thisDip], INPUT);
}

void loop()
{
  byte numTags = EEPROM.read(0);
  if (operationalMode == 0 && numTags > 0)
    normalOperation();
  else if (operationalMode == 1 && numTags > 0)
    openFlapPermanently();
  else
    programmingMode();
}
