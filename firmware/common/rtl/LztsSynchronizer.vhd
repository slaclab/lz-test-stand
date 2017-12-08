-------------------------------------------------------------------------------
-- File       : LztsSynchronizer.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2017-11-13
-- Last update: 2017-11-13
-------------------------------------------------------------------------------
-- Description:
-------------------------------------------------------------------------------
-- This file is part of 'LZ Test Stand Firmware'.
-- It is subject to the license terms in the LICENSE.txt file found in the 
-- top-level directory of this distribution and at: 
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html. 
-- No part of 'LZ Test Stand Firmware', including this file, 
-- may be copied, modified, propagated, or distributed except according to 
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

use work.StdRtlPkg.all;
use work.AxiLitePkg.all;

library unisim;
use unisim.vcomponents.all;

entity LztsSynchronizer is
   generic (
      TPD_G             : time            := 1 ns;
      SIM_SPEEDUP_G     : boolean         := false;
      AXI_ERROR_RESP_G  : slv(1 downto 0) := AXI_RESP_DECERR_C
   );
   port (
      -- AXI-Lite Interface for local registers 
      axilClk           : in  sl;
      axilRst           : in  sl;
      axilReadMaster    : in  AxiLiteReadMasterType;
      axilReadSlave     : out AxiLiteReadSlaveType;
      axilWriteMaster   : in  AxiLiteWriteMasterType;
      axilWriteSlave    : out AxiLiteWriteSlaveType;
      -- local clock input/output
      locClk            : in  sl;
      -- Master command inputs (synchronous to clkOut)
      syncCmd           : in  sl;
      rstCmd            : in  sl;
      -- Inter-board clock and command
      clkInP            : in  sl;
      clkInN            : in  sl;
      clkOutP           : out sl;
      clkOutN           : out sl;
      cmdInP            : in  sl;
      cmdInN            : in  sl;
      cmdOutP           : out sl;
      cmdOutN           : out sl;
      -- globally synchronized outputs
      clkOut            : out sl;
      rstOut            : out sl;
      gTime             : out slv(63 downto 0);
      -- status LEDs
      clkLed            : out sl;
      cmdLed            : out sl;
      mstLed            : out sl
   );
end LztsSynchronizer;

architecture rtl of LztsSynchronizer is
   
   constant LED_TIME_C       : integer := ite(SIM_SPEEDUP_G, 100, 250000000);
   
   type MuxType is record
      gTime          : slv(63 downto 0);
      serIn          : slv(7 downto 0);
      serOut         : slv(7 downto 0);
      cmdOut         : sl;
      slaveDev       : sl;
      syncCmd        : sl;
      syncCmdCnt     : slv(15 downto 0);
      syncDet        : sl;
      syncDetDly     : slv(2 downto 0);
      syncPending    : sl;
      rstCmd         : sl;
      rstCmdCnt      : slv(15 downto 0);
      rstDet         : sl;
      rstDetDly      : slv(2 downto 0);
      rstPending     : sl;
      cmdBits        : integer range 0 to 7;
      clkLedCnt      : integer range 0 to LED_TIME_C;
      cmdLedCnt      : integer range 0 to LED_TIME_C;
      clkLed         : sl;
      cmdLed         : sl;
      badIdleCnt     : slv(15 downto 0);
      delayEn        : sl;
   end record MuxType;
   
   constant MUX_INIT_C : MuxType := (
      gTime          => (others=>'0'),
      serIn          => (others=>'0'),
      serOut         => "01010101",
      cmdOut         => '0',
      slaveDev       => '0',
      syncCmd        => '0',
      syncCmdCnt     => (others=>'0'),
      syncDet        => '0',
      syncDetDly     => "000",
      syncPending    => '0',
      rstCmd         => '0',
      rstCmdCnt      => (others=>'0'),
      rstDet         => '0',
      rstDetDly      => "000",
      rstPending     => '0',
      cmdBits        => 0,
      clkLedCnt      => 0,
      cmdLedCnt      => 0,
      clkLed         => '0',
      cmdLed         => '0',
      badIdleCnt     => (others=>'0'),
      delayEn        => '0'
   );
   
   type RegType is record
      axilReadSlave  : AxiLiteReadSlaveType;
      axilWriteSlave : AxiLiteWriteSlaveType;
      slaveDev       : sl;
      gTime          : slv(63 downto 0);
      syncCmdCnt     : slv(15 downto 0);
      rstCmdCnt      : slv(15 downto 0);
      badIdleCnt     : slv(15 downto 0);
      delayIn        : slv(8 downto 0);
      delayLd        : sl;
      delayEn        : sl;
   end record RegType;

   constant REG_INIT_C : RegType := (
      axilReadSlave  => AXI_LITE_READ_SLAVE_INIT_C,
      axilWriteSlave => AXI_LITE_WRITE_SLAVE_INIT_C,
      slaveDev       => '0',
      gTime          => (others=>'0'),
      syncCmdCnt     => (others=>'0'),
      rstCmdCnt      => (others=>'0'),
      badIdleCnt     => (others=>'0'),
      delayIn        => (others=>'0'),
      delayLd        => '0',
      delayEn        => '0'
   );
   
   signal mux     : MuxType   := MUX_INIT_C;
   signal muxIn   : MuxType;
   signal reg     : RegType   := REG_INIT_C;
   signal regIn   : RegType;
   
   signal clkInBuf         : sl;
   signal clkIn            : sl;
   signal cmdIn            : sl;
   signal cmdInDly         : sl;
   signal cmdInBuf         : sl;
   signal cmdOutBuf        : sl;
   signal muxClk           : sl;
   signal muxClkB          : sl;
   signal delayOut         : slv(8 downto 0);
   
   attribute keep : string;                        -- for chipscope
   attribute keep of muxClk : signal is "true";    -- for chipscope
   attribute keep of mux    : signal is "true";    -- for chipscope
   
begin
   
   U_IBUFGDS_1 : IBUFGDS
   port map (
      I  => clkInP,
      IB => clkInN,
      O  => clkInBuf
   );
   
   U_BUFG_1 : BUFG
   port map (
      I => clkInBuf,
      O => clkIn
   );
   
   U_BUFGMUX_1 : BUFGMUX
   port map (
      O  => muxClk,
      I0 => locClk,
      I1 => clkInBuf,
      S  => reg.slaveDev
   );
   
   clkOut <= muxClk;
   
   U_IBUFDS_1 : IBUFDS
   port map (
      I  => cmdInP,
      IB => cmdInN,
      O  => cmdInBuf
   );
   
   U_IDDRE_1 : IDDRE1
   port map (
      C  => muxClk,
      CB => muxClkB,
      R  => '0',
      D  => cmdInBuf,
      Q1 => cmdIn,
      Q2 => open
   );
   muxClkB <= not muxClk;
   
   
   IDELAYE3_U : IDELAYE3
   generic map (
      CASCADE => "NONE",            -- Cascade setting (MASTER, NONE, SLAVE_END, SLAVE_MIDDLE)
      DELAY_FORMAT => "COUNT",      -- Units of the DELAY_VALUE (COUNT, TIME)
      DELAY_SRC => "DATAIN",        -- Delay input (DATAIN, IDATAIN)
      DELAY_TYPE => "VAR_LOAD",     -- Set the type of tap delay line (FIXED, VARIABLE, VAR_LOAD)
      IS_CLK_INVERTED => '0',       -- Optional inversion for CLK
      IS_RST_INVERTED => '0',       -- Optional inversion for RST
      REFCLK_FREQUENCY => 250.0,    -- IDELAYCTRL clock input frequency in MHz (200.0-2400.0)
      UPDATE_MODE => "ASYNC")       -- Determines when updates to the delay will take effect (ASYNC, MANUAL, SYNC)
   port map (
      CASC_IN     => '0',           -- 1-bit input: Cascade delay input from slave ODELAY CASCADE_OUT 
      CASC_OUT    => open,          -- 1-bit output: Cascade delay output to ODELAY input cascade 
      CASC_RETURN => '0',           -- 1-bit input: Cascade delay returning from slave ODELAY DATAOUT 
      DATAIN      => cmdIn,         -- 1-bit input: Data input from the logic 
      IDATAIN     => '0',           -- 1-bit input: Data input from the IOBUF
      DATAOUT     => cmdInDly,      -- 1-bit output: Delayed data output 
      CLK         => axilClk,       -- 1-bit input: Clock input 
      EN_VTC      => '0',           -- 1-bit input: Keep delay constant over VT 
      INC         => '0',           -- 1-bit input: Increment / Decrement tap delay input 
      CE          => '0',           -- 1-bit input: Active high enable increment/decrement input 
      LOAD        => reg.delayLd,   -- 1-bit input: Load DELAY_VALUE input 
      RST         => axilRst,       -- 1-bit input: Asynchronous Reset to the DELAY_VALUE
      CNTVALUEIN  => reg.delayIn,   -- 9-bit input: Counter value input 
      CNTVALUEOUT => delayOut       -- 9-bit output: Counter value output 
   );  
   
   
   U_ClkOutBufDiff_1 : entity work.ClkOutBufDiff
   generic map (
      XIL_DEVICE_G => "ULTRASCALE")
   port map (
      clkIn   => muxClk,
      clkOutP => clkOutP,
      clkOutN => clkOutN
   );
   
   -- register logic (axilClk domain)
   -- patern serdes logic (muxClk domain)
   comb : process (axilRst, axilReadMaster, axilWriteMaster, reg, mux, cmdIn, cmdInDly, syncCmd, rstCmd, delayOut) is
      variable vreg        : RegType := REG_INIT_C;
      variable vmux        : MuxType := MUX_INIT_C;
      variable regCon      : AxiLiteEndPointType;
   begin
      -- Latch the current value
      vreg := reg;
      vmux := mux;
      
      ------------------------------------------------
      -- cross domian sync
      ------------------------------------------------
      vreg.gTime      := mux.gTime;
      vreg.syncCmdCnt := mux.syncCmdCnt;
      vreg.rstCmdCnt  := mux.rstCmdCnt;
      vreg.badIdleCnt := mux.badIdleCnt;
      vmux.slaveDev   := reg.slaveDev;
      vmux.delayEn    := reg.delayEn;
      
      ------------------------------------------------
      -- register access (axilClk domain)
      ------------------------------------------------
      
      -- Determine the transaction type
      axiSlaveWaitTxn(regCon, axilWriteMaster, axilReadMaster, vreg.axilWriteSlave, vreg.axilReadSlave);
      
      axiSlaveRegister (regCon, x"000", 0, vreg.slaveDev);
      axiSlaveRegisterR(regCon, x"004", 0, reg.gTime(31 downto 0));
      axiSlaveRegisterR(regCon, x"008", 0, reg.gTime(63 downto 32));
      axiSlaveRegisterR(regCon, x"00C", 0, reg.rstCmdCnt);
      axiSlaveRegisterR(regCon, x"010", 0, reg.syncCmdCnt);
      axiSlaveRegisterR(regCon, x"014", 0, reg.badIdleCnt);
      axiSlaveRegister (regCon, x"018", 0, vreg.delayEn);
      axiSlaveRegister (regCon, x"01C", 0, vreg.delayIn);
      axiSlaveRegisterR(regCon, x"01C", 0, delayOut);
      
      if reg.delayIn /= delayOut then
         vreg.delayLd := '1';
      else
         vreg.delayLd := '0';
      end if;
      
      -- Closeout the transaction
      axiSlaveDefault(regCon, vreg.axilWriteSlave, vreg.axilReadSlave, AXI_ERROR_RESP_G);
      
      ------------------------------------------------
      -- Serial pattern in/out logic (muxClk domain)
      ------------------------------------------------
      
      -- clear strobes
      vmux.syncDet := '0';
      vmux.rstDet  := '0';
      vmux.syncDetDly(0) := '0';
      vmux.syncDetDly(1) := mux.syncDetDly(0);
      vmux.syncDetDly(2) := mux.syncDetDly(1);
      vmux.rstDetDly(0)  := '0';
      vmux.rstDetDly(1)  := mux.rstDetDly(0);
      vmux.rstDetDly(2)  := mux.rstDetDly(1);
      
      ------------------------------------------------
      -- slave logic
      ------------------------------------------------
      
      if mux.slaveDev = '1' then
         -- repeat cmdIn
         vmux.cmdOut := cmdIn;
         -- decode cmdIn and look for reser/sync
         if mux.delayEn = '0' then
            vmux.serIn  := mux.serIn(6 downto 0) & cmdIn;
         else
            vmux.serIn  := mux.serIn(6 downto 0) & cmdInDly;
         end if;
         if mux.serIn = "00001111" then
            vmux.syncDet := '1';
         elsif mux.serIn = "00110011" then
            vmux.rstDet := '1';
         end if;
         -- reset unused logic
         vmux.cmdBits := 0;
         vmux.serOut  := "01010101";
      end if;
      
      ------------------------------------------------
      -- master logic
      ------------------------------------------------
      
      if mux.slaveDev = '0' then
         -- clear unused de-serializer
         vmux.serIn  := (others=>'0');
         -- look for master commands
         if rstCmd = '1' then
            vmux.rstCmd := '1';
         elsif syncCmd = '1' then
            vmux.syncCmd := '1';
         end if;
         -- generate patterns
         if mux.cmdBits = 0 then
            vmux.cmdBits := 7;
            -- register commands or idle once every 8 cycles
            if mux.rstCmd = '1' then
               vmux.rstPending := '1';
               vmux.rstCmd  := '0';
               vmux.serOut  := "00110011";
            elsif mux.syncCmd = '1' then
               vmux.syncPending := '1';
               vmux.syncCmd := '0';
               vmux.serOut  := "00001111";
            else
               vmux.serOut  := "01010101";
            end if;
         else
            vmux.cmdBits := mux.cmdBits - 1;
            vmux.serOut  := mux.serOut(6 downto 0) & mux.serOut(7);
         end if;
         
         -- execute command locally after they are serialized to slaves
         if mux.cmdBits = 0 then
            if mux.rstPending = '1' then
               vmux.rstDetDly(0) := '1';
               vmux.rstPending   := '0';
            elsif mux.syncPending = '1' then
               vmux.syncDetDly(0) := '1';
               vmux.syncPending   := '0';
            end if;
         end if;
         -- delay local command detect in master
         vmux.rstDet  := mux.rstDetDly(2);
         vmux.syncDet := mux.syncDetDly(2);
         -- register serial output
         vmux.cmdOut := mux.serOut(7);
      end if;
      
      ------------------------------------------------
      -- master/slave common logic
      ------------------------------------------------
      
      -- synchronous global timer
      if mux.syncDet = '1' or mux.rstDet = '1' then
         vmux.gTime := (others=>'0');
      else
         vmux.gTime := mux.gTime + 1;
      end if;
      
      -- command counters
      if mux.syncDet = '1' then
         vmux.syncCmdCnt := mux.syncCmdCnt + 1;
      end if;
      if mux.rstDet = '1' then
         vmux.rstCmdCnt := mux.rstCmdCnt + 1;
      end if;
      
      -- bad idle counter
      if mux.syncDet = '1' or mux.rstDet = '1' then
         vmux.badIdleCnt  := (others=>'0');
      elsif mux.slaveDev = '1' then
         if mux.serIn(0) = mux.serIn(1) and mux.badIdleCnt /= 2**mux.badIdleCnt'length-1 then
            vmux.badIdleCnt  := vmux.badIdleCnt + 1;
         end if;
      else
         if mux.serOut(0) = mux.serOut(1) and mux.badIdleCnt /= 2**mux.badIdleCnt'length-1 then
            vmux.badIdleCnt  := vmux.badIdleCnt + 1;
         end if;
      end if;
      
      -- LED timers
      if mux.syncDet = '1' or mux.rstDet = '1'  then
         vmux.clkLedCnt := 0;
         vmux.clkLed    := '1';
      elsif mux.clkLedCnt >= LED_TIME_C then
         vmux.clkLedCnt := 0;
         vmux.clkLed    := not mux.clkLed;
      else
         vmux.clkLedCnt := mux.clkLedCnt + 1;
      end if;
      
      if mux.syncDet = '1' or mux.rstDet = '1' then
         vmux.cmdLedCnt := LED_TIME_C;
         vmux.cmdLed    := '1';
      elsif mux.cmdLedCnt > 0 then
         vmux.cmdLedCnt := mux.cmdLedCnt - 1;
      else
         vmux.cmdLed := '0';
      end if;
      
      ------------------------------------------------
      -- Reset
      ------------------------------------------------
      
      if (axilRst = '1') then
         vreg := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle      
      regIn <= vreg;
      muxIn <= vmux;

      -- Outputs
      axilWriteSlave <= reg.axilWriteSlave;
      axilReadSlave  <= reg.axilReadSlave;
      gTime          <= mux.gTime;
      rstOut         <= mux.rstDet;
      clkLed         <= mux.clkLed;
      cmdLed         <= mux.cmdLed;
      mstLed         <= not mux.slaveDev;
   end process comb;

   seqR : process (axilClk) is
   begin
      if (rising_edge(axilClk)) then
         reg <= regIn after TPD_G;
      end if;
   end process seqR;
   
   seqM : process (muxClk) is
   begin
      if (rising_edge(muxClk)) then
         mux <= muxIn after TPD_G;
      end if;
   end process seqM;
   
   -- clock out command on falling edge
   U_ODDRE_1 : ODDRE1
   generic map (
      IS_C_INVERTED  => '1'
   )
   port map (
      C  => muxClk,
      SR => '0',
      D1 => mux.cmdOut,
      D2 => mux.cmdOut,
      Q  => cmdOutBuf
   );
   
   
   U_OBUFDS_1 : OBUFDS
   port map (
      I  => cmdOutBuf,
      OB => cmdOutN,
      O  => cmdOutP
   );

end rtl;
