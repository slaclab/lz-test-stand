#!/usr/bin/env python3
#-----------------------------------------------------------------------------
# Title      : ePix 100a board instance
#-----------------------------------------------------------------------------
# File       : epix100aDAQ.py evolved from evalBoard.py
# Author     : Ryan Herbst, rherbst@slac.stanford.edu
# Modified by: Dionisio Doering
# Created    : 2016-09-29
# Last update: 2017-02-01
#-----------------------------------------------------------------------------
# Description:
# Rogue interface to ePix 100a board
#-----------------------------------------------------------------------------
# This file is part of the rogue_example software. It is subject to 
# the license terms in the LICENSE.txt file found in the top-level directory 
# of this distribution and at: 
#    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html. 
# No part of the rogue_example software, including this file, may be 
# copied, modified, propagated, or distributed except according to the terms 
# contained in the LICENSE.txt file.
#-----------------------------------------------------------------------------
import rogue.hardware.pgp
import pyrogue.utilities.prbs
import pyrogue.utilities.fileio
import pyrogue.gui
import surf
import threading
import signal
import atexit
import yaml
import time
import sys
import argparse
import PyQt4.QtGui
import PyQt4.QtCore
import lztsFpga as fpga
import lztsViewer as vi
import operator
#################


# Set the argument parser
parser = argparse.ArgumentParser()

parser.add_argument(
    "--l", 
    type     = int,
    required = False,
    default  = 0,
    help     = "PGP lane number",
)

parser.add_argument(
    "--type", 
    type     = str,
    required = True,
    help     = "define the PCIe card type (either pgp-gen3 or datadev-pgp2b)",
)  

# Get the arguments
args = parser.parse_args()

if ( args.type == 'pgp-gen3' ):
    pgpVc0 = rogue.hardware.pgp.PgpCard('/dev/pgpcard_0',args.l,0) # Registers for lzts board
    pgpVc1 = rogue.hardware.pgp.PgpCard('/dev/pgpcard_0',args.l,1) # Data for lzts board
    print("")
    print("PGP Card Version: %x" % (pgpVc0.getInfo().version))
    
elif ( args.type == 'datadev-pgp2b' ):
    
    #pgpVc0 = rogue.hardware.data.DataCard('/dev/datadev_0',(args.l*32)+0) # Registers for lzts board
    pgpVc0 = rogue.hardware.data.DataCard('/dev/datadev_0',(7*32)+args.l) # Registers for lzts board
    pgpVc1 = rogue.hardware.data.DataCard('/dev/datadev_0',(args.l*32)+1) # Data for lzts board
    pgpVc2 = rogue.hardware.data.DataCard('/dev/datadev_0',(args.l*32)+2) # PRBS stream
    
    #memBase = rogue.hardware.data.DataMap('/dev/datadev_0')
else:
    raise ValueError("Invalid type (%s)" % (args.type) )



# Add data stream to file as channel 1
# File writer
dataWriter = pyrogue.utilities.fileio.StreamWriter(name='dataWriter')

pyrogue.streamConnect(pgpVc1, dataWriter.getChannel(0x1))
## Add pseudoscope to file writer
#pyrogue.streamConnect(pgpVc2, dataWriter.getChannel(0x2))
#pyrogue.streamConnect(pgpVc3, dataWriter.getChannel(0x3))

cmd = rogue.protocols.srp.Cmd()
pyrogue.streamConnect(cmd, pgpVc1)

# Create and Connect SRP to VC1 to send commands
srp = rogue.protocols.srp.SrpV3()
pyrogue.streamConnectBiDir(pgpVc0,srp)


#############################################
# Microblaze console printout
#############################################
class MbDebug(rogue.interfaces.stream.Slave):

    def __init__(self):
        rogue.interfaces.stream.Slave.__init__(self)
        self.enable = False

    def _acceptFrame(self,frame):
        if self.enable:
            p = bytearray(frame.getPayload())
            frame.read(p,0)
            print('-------- Microblaze Console --------')
            print(p.decode('utf-8'))

#######################################
# Custom run control
#######################################

class MyRunControl(pyrogue.RunControl):
    def __init__(self,name):
        pyrogue.RunControl.__init__(self,name=name,description='Run Controller LZTS', rates={1:'1 Hz', 10:'10 Hz', 30:'30 Hz'})
        self._thread = None

    def _setRunState(self,dev,var,value,changed):
        if changed: 
            if self.runState.get(read=False) == 'Running': 
                self._thread = threading.Thread(target=self._run) 
                self._thread.start() 
            else: 
                self._thread.join() 
                self._thread = None 

    def _run(self):
        self.runCount.set(0) 
        self._last = int(time.time()) 
 
 
        while (self.runState.value() == 'Running'): 
            delay = 1.0 / ({value: key for key,value in self.runRate.enum.items()}[self._runRate]) 
            time.sleep(delay) 
            self.root.Trigger() 
  
            self._runCount += 1 
            if self._last != int(time.time()): 
                self._last = int(time.time()) 
                self.runCount._updated() 
            
##############################
# Set base
##############################
class LztsBoard(pyrogue.Root):
    def __init__(self, cmd, dataWriter, srp, **kwargs):
        
        pyrogue.Root.__init__(self, name='lztsBoard', description='LZTS Board')
        
        self.add(dataWriter)

        # Add Devices
        self.add(fpga.Lzts(name='Lzts', offset=0, memBase=srp, hidden=False, enabled=True))

        @self.command()
        def Trigger():
            cmd.sendCmd(0, 0)
        
        self.add(MyRunControl('runControl'))
        #self.add(pyrogue.RunControl(name='runControl', rates={1:'1 Hz', 10:'10 Hz',30:'30 Hz'}, cmd=cmd.sendCmd(0, 0)))
        
        # Export remote objects
        self.start(pyroGroup='lztsGui')





# Create board
LztsBoard = LztsBoard(cmd, dataWriter, srp)

#enable all needed devices
LztsBoard.Lzts.PwrReg.enable.set(True)
LztsBoard.Lzts.SadcPatternTester.enable.set(True)
for i in range(4):
    LztsBoard.Lzts.SlowAdcConfig[i].enable.set(True)
    LztsBoard.Lzts.SlowAdcReadout[i].enable.set(True)
for i in range(8):
    LztsBoard.Lzts.SadcBufferWriter[i].enable.set(True)

# find all delay lane registers
delayRegs = LztsBoard.Lzts.find(name="DelayAdc*")
dmodeRegs = LztsBoard.Lzts.find(name="DMode*")
invertRegs = LztsBoard.Lzts.find(name="Invert*")
convertRegs = LztsBoard.Lzts.find(name="Convert*")
# find all ADC settings registers
adcRegs8 = LztsBoard.Lzts.find(name="AdcReg_0x0008")
adcRegsF = LztsBoard.Lzts.find(name="AdcReg_0x000F")
adcRegs10 = LztsBoard.Lzts.find(name="AdcReg_0x0010")
adcRegs11 = LztsBoard.Lzts.find(name="AdcReg_0x0011")
adcRegs15 = LztsBoard.Lzts.find(name="AdcReg_0x0015")

#initial configuration for the slow ADC
LztsBoard.Lzts.PwrReg.EnDcDcAp3V7.set(True)
LztsBoard.Lzts.PwrReg.EnDcDcAp2V3.set(True)
LztsBoard.Lzts.PwrReg.EnLdoSlow.set(True)
LztsBoard.Lzts.PwrReg.SADCCtrl1.set(0)
LztsBoard.Lzts.PwrReg.SADCCtrl2.set(0)
LztsBoard.Lzts.PwrReg.SADCRst.set(0xf)
time.sleep(1.0)
LztsBoard.Lzts.PwrReg.SADCRst.set(0x0)
time.sleep(1.0)
for reg in dmodeRegs:
   reg.set(0x3)      # deserializer dmode 0x3
for reg in invertRegs:
   reg.set(0x0)      # do not invert data for pattern testing
for reg in convertRegs:
   reg.set(0x0)      # do not convert data for pattern testing
#for reg in adcRegs8:
#   reg.set(0x10)     # ADC binary data format
for reg in adcRegsF:
   reg.set(0x66)     # ADC single pattern
for reg in adcRegs15:
   reg.set(0x1)      # ADC DDR mode

LztsBoard.Lzts.SadcPatternTester.Samples.set(0xffff)
LztsBoard.Lzts.SadcPatternTester.Mask.set(0xffff)

delays = [0 for x in range(512)]

fileName = 'SADC_Delays_DeviceDna' + hex(LztsBoard.Lzts.AxiVersion.DeviceDna.get()) + '.csv'
f = open(fileName, 'a')

#iterate all ADCs
for adcNo in range(0, 8):
   # iterate all lanes on 1 ADC channel
   for lane in range(0, 8):
      print("ADC %d Lane %d" %(adcNo, lane))
      # iterate all delays
      for delay in range(0, 512):
         # set tester channel
         LztsBoard.Lzts.SadcPatternTester.Channel.set(adcNo)
         # set delay
         delayRegs[lane+adcNo*8].set(delay)
         
         pattern = 2**(lane*2)
         
         # set pattern output in ADC
         adcRegs10[int(adcNo/2)].set((pattern&0xFF00)>>8)
         adcRegs11[int(adcNo/2)].set(pattern&0xFF)
         # set tester pattern
         LztsBoard.Lzts.SadcPatternTester.Pattern.set(pattern)
         # toggle request bit
         LztsBoard.Lzts.SadcPatternTester.Request.set(False)
         LztsBoard.Lzts.SadcPatternTester.Request.set(True)
         # wait until test done
         while LztsBoard.Lzts.SadcPatternTester.Done.get() != 1:
            pass
         passed = not LztsBoard.Lzts.SadcPatternTester.Failed.get()
         
         #print(int(passed), end='', flush=True)
         
         # shift pattern for next bit test (2 bits per lane)
         pattern = pattern << 1;
         
         # set pattern output in ADC
         adcRegs10[int(adcNo/2)].set((pattern&0xFF00)>>8)
         adcRegs11[int(adcNo/2)].set(pattern&0xFF)
         # set tester pattern
         LztsBoard.Lzts.SadcPatternTester.Pattern.set(pattern)
         # toggle request bit
         LztsBoard.Lzts.SadcPatternTester.Request.set(False)
         LztsBoard.Lzts.SadcPatternTester.Request.set(True)
         # wait until test done
         while LztsBoard.Lzts.SadcPatternTester.Done.get() != 1:
            pass
         passed = passed and not LztsBoard.Lzts.SadcPatternTester.Failed.get()
         #passed = not LztsBoard.Lzts.SadcPatternTester.Failed.get()
         
         #print(int(passed), end='', flush=True)
         
         delays[delay] = int(passed)

      #print('\n')
      
      # find best delay setting
      lengths = []
      starts = []
      stops = []
      length = 0
      start = -1
      started = 0
      setDelay = 0
      for i in range(5, 512):
         # find a vector of ones minimum width 5
         if delays[i] == 1 and delays[i-1] == 1 and delays[i-2] == 1 and delays[i-3] == 1 and delays[i-4] == 1 and delays[i-5] == 1:
            started = 1
            length+=1
            if start < 0:
               start = i - 5
         elif delays[i] == 0 and delays[i-1] == 1 and delays[i-2] == 1 and delays[i-3] == 1 and delays[i-4] == 1 and delays[i-5] == 1:
            lengths.append(length+5)
            starts.append(start)
            stops.append(i-1)
            length = 0
            start = -1
            started = 0
         elif started == 1 and i == 511:
            lengths.append(length+5)
            starts.append(start)
            stops.append(i-1)
      
      # find the longest vector of ones
      if len(lengths) > 0:
         index, value = max(enumerate(lengths), key=operator.itemgetter(1))
         setDelay = int(starts[index]+(stops[index]-starts[index])/2)
      else:
         print('ADC %d, Lane %d FAILED!' %(adcNo, lane))
         setDelay = 0
      
      print('Delay %d' %(setDelay))
      f.write('%d,' %(setDelay))
      
      # set best delay
      delayRegs[lane+adcNo*8].set(setDelay)

#close the file
f.write('\n')
f.close()



LztsBoard.stop()
exit()