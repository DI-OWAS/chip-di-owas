-- ================================================================================ --
-- NEORV32 SoC - Custom Functions Subsystem (CFS)                                   --
-- -------------------------------------------------------------------------------- --
-- Application: 16x DI-OWAS reset controller , active-low on cfs_out_o(15:0)         --
-- -------------------------------------------------------------------------------- --
-- The NEORV32 RISC-V Processor - https://github.com/stnolting/neorv32              --
-- Copyright (c) NEORV32 contributors.                                              --
-- Copyright (c) Stephan Nolting. All rights reserved.                              --
-- Licensed under the BSD-3-Clause license, see LICENSE for details.                --
-- SPDX-License-Identifier: BSD-3-Clause                                            --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

entity neorv32_cfs is
  port (
    -- global control --
    clk_i      : in  std_ulogic;                      -- global clock
    rstn_i     : in  std_ulogic;                      -- global reset, low-active, async
    -- CPU request --
    req_addr_i : in  std_ulogic_vector(15 downto 0);  -- byte address (64kB address space)
    req_data_i : in  std_ulogic_vector(31 downto 0);  -- write data
    req_ben_i  : in  std_ulogic_vector(3 downto 0);   -- byte enable
    req_stb_i  : in  std_ulogic;                      -- access request strobe
    req_rw_i   : in  std_ulogic;                      -- 0=read, 1=write
    -- CPU response --
    rsp_data_o : out std_ulogic_vector(31 downto 0);  -- read data
    rsp_ack_o  : out std_ulogic;                      -- access acknowledge
    -- CPU interrupt --
    irq_o      : out std_ulogic;                      -- interrupt request, high-active
    -- external IO --
    cfs_in_i   : in  std_ulogic_vector(255 downto 0); -- custom inputs conduit
    cfs_out_o  : out std_ulogic_vector(255 downto 0)  -- custom outputs conduit
  );
end entity;

architecture neorv32_cfs_rtl of neorv32_cfs is

  signal reset_ctrl, reset_sync : std_ulogic_vector(15 downto 0);

begin

  -- CFS IOs --------------------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  cfs_out_o(15 downto 0)   <= reset_sync;
  cfs_out_o(255 downto 16) <= (others => '0');

  -- Interrupt ------------------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  irq_o <= '0'; -- not used

  -- Read/Write Access ----------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  host_access: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      reset_ctrl <= (others => '0');
      rsp_data_o <= (others => '0');
      rsp_ack_o  <= '0';
    elsif rising_edge(clk_i) then
      -- defaults --
      rsp_data_o <= (others => '0');
      rsp_ack_o  <= req_stb_i;
      -- host access --
      if (req_stb_i = '1') and (req_ben_i = "1111") then -- full-word accesses only
        if (req_rw_i = '1') then
          reset_ctrl <= req_data_i(15 downto 0);
        else
          rsp_data_o(15 downto 0) <= reset_ctrl;
        end if;
      end if;
    end if;
  end process;


  -- Reset Synchronizers --------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  reset_buf: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      reset_sync <= (others => '0');
    elsif rising_edge(clk_i) then
      reset_sync <= not reset_ctrl;
    end if;
  end process;

end architecture;
