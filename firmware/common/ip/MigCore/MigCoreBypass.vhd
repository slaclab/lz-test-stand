-------------------------------------------------------------------------------
-- File       : MigCoreWrapper.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2017-04-21
-- Last update: 2017-04-26
-------------------------------------------------------------------------------
-- Description:
-------------------------------------------------------------------------------
-- This file is part of 'SLAC Firmware Standard Library'.
-- It is subject to the license terms in the LICENSE.txt file found in the 
-- top-level directory of this distribution and at: 
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html. 
-- No part of 'SLAC Firmware Standard Library', including this file, 
-- may be copied, modified, propagated, or distributed except according to 
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

use work.StdRtlPkg.all;
use work.AxiLitePkg.all;
use work.AxiPkg.all;

entity MigCoreWrapper is
   generic (
      TPD_G : time := 1 ns);
   port (
      -- AXI Slave
      axiClk           : out   sl;
      axiRst           : out   sl;
      axiReadMaster    : in    AxiReadMasterType;
      axiReadSlave     : out   AxiReadSlaveType;
      axiWriteMaster   : in    AxiWriteMasterType;
      axiWriteSlave    : out   AxiWriteSlaveType;
      -- DDR PHY Ref clk
      c0_sys_clk_p     : in    sl;
      c0_sys_clk_n     : in    sl;
      -- DRR Memory interface ports
      c0_ddr4_dq       : inout slv(63 downto 0);
      c0_ddr4_dqs_c    : inout slv(7 downto 0);
      c0_ddr4_dqs_t    : inout slv(7 downto 0);
      c0_ddr4_adr      : out   slv(16 downto 0);
      c0_ddr4_ba       : out   slv(1 downto 0);
      c0_ddr4_bg       : out   slv(0 to 0);
      c0_ddr4_reset_n  : out   sl;
      c0_ddr4_act_n    : out   sl;
      c0_ddr4_ck_t     : out   slv(0 to 0);
      c0_ddr4_ck_c     : out   slv(0 to 0);
      c0_ddr4_cke      : out   slv(0 to 0);
      c0_ddr4_cs_n     : out   slv(0 to 0);
      c0_ddr4_dm_dbi_n : inout slv(7 downto 0);
      c0_ddr4_odt      : out   slv(0 to 0);
      calibComplete    : out   sl);
end MigCoreWrapper;

architecture mapping of MigCoreWrapper is

begin

   axiClk <= '0';
   axiRst <= '1';

   axiReadSlave  <= AXI_READ_SLAVE_FORCE_C;
   axiWriteSlave <= AXI_WRITE_SLAVE_FORCE_C;

   c0_ddr4_adr     <= (others => '1');
   c0_ddr4_ba      <= (others => '1');
   c0_ddr4_bg      <= (others => '1');
   c0_ddr4_reset_n <= '1';
   c0_ddr4_act_n   <= '1';
   c0_ddr4_ck_t    <= (others => '0');
   c0_ddr4_ck_c    <= (others => '1');
   c0_ddr4_cke     <= (others => '1');
   c0_ddr4_cs_n    <= (others => '1');
   c0_ddr4_odt     <= (others => '1');
   calibComplete   <= '0';

end mapping;