library ieee;
use ieee.std_logic_1164.all;

entity RM_IHPSG13_2P_1024x32_c2_bm_bist is
    port (
        -- Port A
        A_CLK       : in  std_logic;
        A_MEN       : in  std_logic;
        A_WEN       : in  std_logic;
        A_REN       : in  std_logic;
        A_ADDR      : in  std_logic_vector(9 downto 0);
        A_DIN       : in  std_logic_vector(31 downto 0);
        A_DLY       : in  std_logic;
        A_DOUT      : out std_logic_vector(31 downto 0);
        A_BM        : in  std_logic_vector(31 downto 0);

        A_BIST_CLK  : in  std_logic;
        A_BIST_EN   : in  std_logic;
        A_BIST_MEN  : in  std_logic;
        A_BIST_WEN  : in  std_logic;
        A_BIST_REN  : in  std_logic;
        A_BIST_ADDR : in  std_logic_vector(9 downto 0);
        A_BIST_DIN  : in  std_logic_vector(31 downto 0);
        A_BIST_BM   : in  std_logic_vector(31 downto 0);

        -- Port B
        B_CLK       : in  std_logic;
        B_MEN       : in  std_logic;
        B_WEN       : in  std_logic;
        B_REN       : in  std_logic;
        B_ADDR      : in  std_logic_vector(9 downto 0);
        B_DIN       : in  std_logic_vector(31 downto 0);
        B_DLY       : in  std_logic;
        B_DOUT      : out std_logic_vector(31 downto 0);
        B_BM        : in  std_logic_vector(31 downto 0);

        B_BIST_CLK  : in  std_logic;
        B_BIST_EN   : in  std_logic;
        B_BIST_MEN  : in  std_logic;
        B_BIST_WEN  : in  std_logic;
        B_BIST_REN  : in  std_logic;
        B_BIST_ADDR : in  std_logic_vector(9 downto 0);
        B_BIST_DIN  : in  std_logic_vector(31 downto 0);
        B_BIST_BM   : in  std_logic_vector(31 downto 0)
    );
end entity RM_IHPSG13_2P_1024x32_c2_bm_bist;

-- no architecture = intentional blackbox
architecture blackbox of RM_IHPSG13_2P_1024x32_c2_bm_bist is
begin
end;
