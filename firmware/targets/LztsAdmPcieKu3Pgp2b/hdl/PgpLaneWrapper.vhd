-------------------------------------------------------------------------------
-- File       : PgpLaneWrapper.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2017-10-26
-- Last update: 2018-02-20
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
-- This file is part of 'SLAC PGP Gen3 Card'.
-- It is subject to the license terms in the LICENSE.txt file found in the 
-- top-level directory of this distribution and at: 
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html. 
-- No part of 'SLAC PGP Gen3 Card', including this file, 
-- may be copied, modified, propagated, or distributed except according to 
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

use work.StdRtlPkg.all;
use work.BuildInfoPkg.all;
use work.AxiLitePkg.all;
use work.AxiStreamPkg.all;
use work.AxiPciePkg.all;

library unisim;
use unisim.vcomponents.all;

entity PgpLaneWrapper is
   generic (
      TPD_G            : time             := 1 ns;
      REFCLK_WIDTH_G   : positive         := 2;
      AXI_BASE_ADDR_G  : slv(31 downto 0) := (others => '0'));
   port (
      -- QSFP[0] Ports
      qsfp0RefClkP    : in  slv(REFCLK_WIDTH_G-1 downto 0);
      qsfp0RefClkN    : in  slv(REFCLK_WIDTH_G-1 downto 0);
      qsfp0RxP        : in  slv(3 downto 0);
      qsfp0RxN        : in  slv(3 downto 0);
      qsfp0TxP        : out slv(3 downto 0);
      qsfp0TxN        : out slv(3 downto 0);
      -- QSFP[1] Ports
      qsfp1RefClkP    : in  slv(REFCLK_WIDTH_G-1 downto 0);
      qsfp1RefClkN    : in  slv(REFCLK_WIDTH_G-1 downto 0);
      qsfp1RxP        : in  slv(3 downto 0);
      qsfp1RxN        : in  slv(3 downto 0);
      qsfp1TxP        : out slv(3 downto 0);
      qsfp1TxN        : out slv(3 downto 0);
      -- DMA Interface (dmaClk domain)
      dmaClk          : in  sl;
      dmaRst          : in  sl;
      dmaObMasters    : in  AxiStreamMasterArray(7 downto 0);
      dmaObSlaves     : out AxiStreamSlaveArray(7 downto 0);
      dmaIbMasters    : out AxiStreamMasterArray(7 downto 0);
      dmaIbSlaves     : in  AxiStreamSlaveArray(7 downto 0);
      -- AXI-Lite Interface (axilClk domain)
      axilClk         : in  sl;
      axilRst         : in  sl;
      axilReadMaster  : in  AxiLiteReadMasterType;
      axilReadSlave   : out AxiLiteReadSlaveType;
      axilWriteMaster : in  AxiLiteWriteMasterType;
      axilWriteSlave  : out AxiLiteWriteSlaveType);
end PgpLaneWrapper;

architecture mapping of PgpLaneWrapper is

   function TdestRoutes return Slv8Array is
      variable retConf : Slv8Array(6 downto 0);
   begin
      for i in 6 downto 0 loop
         retConf(i) := toSlv((32*7)+i, 8);
      end loop;
      return retConf;
   end function;

   constant NUM_AXI_MASTERS_C : natural := 8;

   constant AXI_CONFIG_C : AxiLiteCrossbarMasterConfigArray(NUM_AXI_MASTERS_C-1 downto 0) := genAxiLiteConfig(NUM_AXI_MASTERS_C, AXI_BASE_ADDR_G, 20, 16);

   signal axilWriteMasters : AxiLiteWriteMasterArray(NUM_AXI_MASTERS_C-1 downto 0);
   signal axilWriteSlaves  : AxiLiteWriteSlaveArray(NUM_AXI_MASTERS_C-1 downto 0);
   signal axilReadMasters  : AxiLiteReadMasterArray(NUM_AXI_MASTERS_C-1 downto 0);
   signal axilReadSlaves   : AxiLiteReadSlaveArray(NUM_AXI_MASTERS_C-1 downto 0);

   signal pgpRefClk : slv(7 downto 0);
   signal pgpRxP    : slv(7 downto 0);
   signal pgpRxN    : slv(7 downto 0);
   signal pgpTxP    : slv(7 downto 0);
   signal pgpTxN    : slv(7 downto 0);

   signal regObMasters : AxiStreamMasterArray(6 downto 0);
   signal regObSlaves  : AxiStreamSlaveArray(6 downto 0);
   signal regIbMasters : AxiStreamMasterArray(6 downto 0);
   signal regIbSlaves  : AxiStreamSlaveArray(6 downto 0);

   signal drpClk   : sl;
   signal drpReset : sl;
   signal drpRst   : sl;

   signal refClk : slv((2*REFCLK_WIDTH_G)-1 downto 0);

   attribute dont_touch           : string;
   attribute dont_touch of refClk : signal is "TRUE";

begin

   U_DRP_CLK : BUFGCE_DIV
      generic map (
         BUFGCE_DIVIDE => 8)
      port map (
         I   => dmaClk,
         CE  => '1',
         CLR => '0',
         O   => drpClk);

   U_RstSync : entity work.RstSync
      generic map (
         TPD_G => TPD_G)
      port map (
         clk      => drpClk,
         asyncRst => dmaRst,
         syncRst  => drpReset);

   U_RstPipe : entity work.RstPipeline
      generic map (
         TPD_G => TPD_G)
      port map (
         clk    => drpClk,
         rstIn  => drpReset,
         rstOut => drpRst);

   ------------------------
   -- Common PGP Clocking
   ------------------------
   GEN_REFCLK :
   for i in REFCLK_WIDTH_G-1 downto 0 generate

      U_QsfpRef0 : IBUFDS_GTE3
         generic map (
            REFCLK_EN_TX_PATH  => '0',
            REFCLK_HROW_CK_SEL => "00",  -- 2'b00: ODIV2 = O
            REFCLK_ICNTL_RX    => "00")
         port map (
            I     => qsfp0RefClkP(i),
            IB    => qsfp0RefClkN(i),
            CEB   => '0',
            ODIV2 => open,
            O     => refClk((2*i)+0));

      U_QsfpRef1 : IBUFDS_GTE3
         generic map (
            REFCLK_EN_TX_PATH  => '0',
            REFCLK_HROW_CK_SEL => "00",  -- 2'b00: ODIV2 = O
            REFCLK_ICNTL_RX    => "00")
         port map (
            I     => qsfp1RefClkP(i),
            IB    => qsfp1RefClkN(i),
            CEB   => '0',
            ODIV2 => open,
            O     => refClk((2*i)+1));
   end generate GEN_REFCLK;

   --------------------------------
   -- Mapping QSFP[1:0] to PGP[7:0]
   --------------------------------
   MAP_QSFP : for i in 3 downto 0 generate
      -- QSFP[0] to PGP[3:0]
      pgpRefClk(i+0) <= refClk(0);
      pgpRxP(i+0)    <= qsfp0RxP(i);
      pgpRxN(i+0)    <= qsfp0RxN(i);
      qsfp0TxP(i)    <= pgpTxP(i+0);
      qsfp0TxN(i)    <= pgpTxN(i+0);
      -- QSFP[1] to PGP[7:4]
      pgpRefClk(i+4) <= refClk(1);
      pgpRxP(i+4)    <= qsfp1RxP(i);
      pgpRxN(i+4)    <= qsfp1RxN(i);
      qsfp1TxP(i)    <= pgpTxP(i+4);
      qsfp1TxN(i)    <= pgpTxN(i+4);
   end generate MAP_QSFP;

   ---------------------
   -- AXI-Lite Crossbar
   ---------------------
   U_XBAR : entity work.AxiLiteCrossbar
      generic map (
         TPD_G              => TPD_G,
         NUM_SLAVE_SLOTS_G  => 1,
         NUM_MASTER_SLOTS_G => NUM_AXI_MASTERS_C,
         MASTERS_CONFIG_G   => AXI_CONFIG_C)
      port map (
         axiClk              => axilClk,
         axiClkRst           => axilRst,
         sAxiWriteMasters(0) => axilWriteMaster,
         sAxiWriteSlaves(0)  => axilWriteSlave,
         sAxiReadMasters(0)  => axilReadMaster,
         sAxiReadSlaves(0)   => axilReadSlave,
         mAxiWriteMasters    => axilWriteMasters,
         mAxiWriteSlaves     => axilWriteSlaves,
         mAxiReadMasters     => axilReadMasters,
         mAxiReadSlaves      => axilReadSlaves);

   ------------
   -- PGP Lanes
   ------------
   GEN_LANE : for i in 6 downto 0 generate

      U_Lane : entity work.PgpLane
         generic map (
            TPD_G            => TPD_G,
            LANE_G           => i,
            AXI_BASE_ADDR_G  => AXI_CONFIG_C(i).baseAddr)
         port map (
            -- DRP Clock and Reset
            drpClk          => drpClk,
            drpRst          => drpRst,
            -- PGP Serial Ports
            pgpRxP          => pgpRxP(i),
            pgpRxN          => pgpRxN(i),
            pgpTxP          => pgpTxP(i),
            pgpTxN          => pgpTxN(i),
            pgpRefClk       => pgpRefClk(i),
            -- DMA Interface (dmaClk domain)
            dmaClk          => dmaClk,
            dmaRst          => dmaRst,
            dmaObMaster     => dmaObMasters(i),
            dmaObSlave      => dmaObSlaves(i),
            dmaIbMaster     => dmaIbMasters(i),
            dmaIbSlave      => dmaIbSlaves(i),
            -- SRPv3 Tap Interface (dmaClk domain)
            regObMaster     => regObMasters(i),
            regObSlave      => regObSlaves(i),
            regIbMaster     => regIbMasters(i),
            regIbSlave      => regIbSlaves(i),
            -- AXI-Lite Interface (axilClk domain)
            axilClk         => axilClk,
            axilRst         => axilRst,
            axilReadMaster  => axilReadMasters(i),
            axilReadSlave   => axilReadSlaves(i),
            axilWriteMaster => axilWriteMasters(i),
            axilWriteSlave  => axilWriteSlaves(i));

   end generate GEN_LANE;

   ------------------------------
   -- Terminate Unused GT Channel
   ------------------------------
   U_Gthe3ChannelDummy : entity work.Gthe3ChannelDummy
      generic map (
         TPD_G   => TPD_G,
         WIDTH_G => 1)
      port map (
         refClk   => axilClk,
         gtRxP(0) => pgpRxP(7),
         gtRxN(0) => pgpRxN(7),
         gtTxP(0) => pgpTxP(7),
         gtTxN(0) => pgpTxN(7));

   ------------------------
   -- DeMux the SRPv3 Streams
   ------------------------         
   U_DeMux : entity work.AxiStreamDeMux
      generic map (
         TPD_G         => TPD_G,
         NUM_MASTERS_G => 7,
         MODE_G        => "INDEXED",
         PIPE_STAGES_G => 1,
         TDEST_HIGH_G  => 3,
         TDEST_LOW_G   => 0)
      port map (
         -- Clock and reset
         axisClk      => dmaClk,
         axisRst      => dmaRst,
         -- Slave         
         sAxisMaster  => dmaObMasters(7),
         sAxisSlave   => dmaObSlaves(7),
         -- Masters
         mAxisMasters => regObMasters,
         mAxisSlaves  => regObSlaves);

   ------------------------
   -- Mux the SRPv3 Streams
   ------------------------
   U_Mux : entity work.AxiStreamMux
      generic map (
         TPD_G                => TPD_G,
         NUM_SLAVES_G         => 7,
         MODE_G               => "ROUTED",
         TDEST_ROUTES_G       => TdestRoutes,
         ILEAVE_EN_G          => true,
         ILEAVE_ON_NOTVALID_G => false,
         ILEAVE_REARB_G       => 128,
         PIPE_STAGES_G        => 1)
      port map (
         -- Clock and reset
         axisClk      => dmaClk,
         axisRst      => dmaRst,
         -- Slaves
         sAxisMasters => regIbMasters,
         sAxisSlaves  => regIbSlaves,
         -- Master
         mAxisMaster  => dmaIbMasters(7),
         mAxisSlave   => dmaIbSlaves(7));

end mapping;
