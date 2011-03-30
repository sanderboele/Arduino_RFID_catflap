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
  
const byte whiteLed = 13; //status LED pin
const byte motorLeft = 10; //black, L293D pin 7
const byte motorRight = 11; //red, L293D pin 3
const byte motorTime = 100; //number of msec the motor is running for flap to open or close

//define the pins where the dipswitches or regular switches are located for unlocktime
const byte DIPS[4] = { 3, 4, 5, 6 };
const byte DIPSIZE = 4;

boolean flapOpen = true; //asume that initial flap state is open, so the program closes it.
volatile byte operationalMode = 0; // 0=normal, 1=always open triggered by interrupt
volatile static unsigned long lastInterruptTime = 0; //debounce counter for operational button
byte numTags = EEPROM.read(0);

int getUnlockTime()
{
  int unlockTime = 0;
  for (int thisDip = 0; thisDip < DIPSIZE; thisDip++)
  {
    /* 
    dip 0 = 2^0 = 1
    dip 1 = 2^1 = 2
    dip 2 = 2^2 = 4
    dip 3 = 2^3 = 8
    */
    Serial.print("Dip is now: ");
    Serial.println(thisDip);
    if (digitalRead(DIPS[thisDip]) == HIGH)
    {
      byte increment = 0;
      Serial.print("Dip ");
      Serial.print(thisDip);
      Serial.println("is high!");
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
          }
        }
      }
      bytesRead = 0;
      Serial.flush(); //no historicaly buffered kitties here!
      return true;
    }
  }
}

void openFlap(byte seconds) //opens flap for the supplied amount of time
{
  digitalWrite(motorLeft, HIGH);
  delay(motorTime);
  digitalWrite(motorLeft, LOW);
  Serial.println("Flap opened");
  flapOpen = true;
  digitalWrite(whiteLed, LOW);
  delay((seconds * 1000)+10);
  digitalWrite(motorRight, HIGH);
  delay(motorTime);
  digitalWrite(motorRight, LOW);
  Serial.println("Flap closed");
  digitalWrite(whiteLed, HIGH);
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
    digitalWrite(whiteLed, LOW);
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
   digitalWrite(whiteLed, HIGH); 
  } 
}


boolean checkTag(byte tagBytes[])
{
  boolean match;
  byte numTags = EEPROM.read(0);
  if (numTags > 0)
  {
    Serial.print("Following number of tags appear to be in EEPROM: ");
    Serial.println(numTags, DEC);
    for (int tag=0; tag < numTags; tag++)
    {
      for (int i=(tag * 5)+1; i<= (tag * 5) + 5; i++)
      {  
        if (tagBytes[(i-1)%5] == EEPROM.read(i))
          match = true;
        else
        {
          match = false;
          break;
        }
      }
      if (match)
        return true;
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
       //Serial.print("With modulo= ");
       //Serial.println((i-1)%5, DEC);
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

void programmingMode()
{
  Serial.println("Entered programm mode");
  byte tagBytes[6];
  if (readTag(&tagBytes[0]))
    writeTag(tagBytes);
}

void changeOperationalMode() //toggle between normal and always open via interrupt 0 = digital pin2
{
  volatile unsigned long interruptTime = millis();
  if (interruptTime - lastInterruptTime > 500)
  {
    Serial.flush();
    if (operationalMode == 0)
    {
      operationalMode = 1; //goto always open
      Serial.println("Always open mode");
    }
    else
    {
      operationalMode = 0;  //goto normal operation
      Serial.println("Going to normal operation");
    }
    lastInterruptTime = interruptTime;
  }
}

void setup()   
{ 
  attachInterrupt(0, changeOperationalMode, RISING); //button for toggeling operational mode (dig pin 2)
  pinMode(motorLeft, OUTPUT);
  pinMode(motorRight, OUTPUT);
  pinMode(whiteLed, OUTPUT);  
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
  if (numTags == 0)
    programmingMode();
  else
  {
    if (operationalMode == 0)
      normalOperation();
    else
      openFlapPermanently();
  }
}
