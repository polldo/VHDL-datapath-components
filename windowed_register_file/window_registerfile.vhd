library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;
use IEEE.numeric_std.all;
use WORK.all;
use WORK.log_pkg.all;

entity WINDOW_REGISTER_FILE is
 generic(	NBIT: integer := 64;
		NREG: integer := 32;
		M: integer := 8; --number of global registers
		N: integer := 8; --number of registers in each block of a window
		F: integer := 8); --number of windows
 port ( CLK: 		IN std_logic;
        RESET: 		IN std_logic;
	ENABLE: 	IN std_logic;
	RD1: 		IN std_logic;
 	RD2: 		IN std_logic;
 	WR: 		IN std_logic;
	CALL:		IN std_logic;
	RET:		IN std_logic;
 	ADD_WR: 	IN std_logic_vector(log2N(3*N+M)-1 downto 0);
 	ADD_RD1: 	IN std_logic_vector(log2N(3*N+M)-1 downto 0);
	ADD_RD2: 	IN std_logic_vector(log2N(3*N+M)-1 downto 0);
 	DATAIN: 	IN std_logic_vector(NBIT-1 downto 0);
        OUT1: 		OUT std_logic_vector(NBIT-1 downto 0);
 	OUT2: 		OUT std_logic_vector(NBIT-1 downto 0);
	FILL:		OUT std_logic;
	SPILL:		OUT std_logic);
end WINDOW_REGISTER_FILE;

architecture STRUCTURAL of WINDOW_REGISTER_FILE is

	component LOGIC_REGISTER_FILE is
 	generic(	NBIT: integer := 64;
			NREG: integer := 32;
			M: integer := 8; 
			N: integer := 8; 
			F: integer := 8); 
	 port ( CLK: 		IN std_logic;
        	RESET: 		IN std_logic;
		CALL:		IN std_logic;
		RET:		IN std_logic;
		FILL:		OUT std_logic;
		SPILL:		OUT std_logic;
		CWP:		OUT integer range 0 to F-1;
		SWP:		OUT integer range 0 to F-1;
		SWP_OFFSET:	OUT integer range 0 to N*2-1);
	end component;
	
	component ADDRESS_TRANSLATOR is
	 generic(	NBIT: integer := 64;
			NREG: integer := 32;
			M: integer := 8; 
			N: integer := 8; 
			F: integer := 8); 
 	port ( ADD_WR_IN: 	IN std_logic_vector(log2N(3*N+M)-1 downto 0);
 		ADD_RD1_IN: 	IN std_logic_vector(log2N(3*N+M)-1 downto 0);
		ADD_RD2_IN: 	IN std_logic_vector(log2N(3*N+M)-1 downto 0);
		FILL:		IN std_logic;
		SPILL:		IN std_logic;
		CWP:		IN integer range 0 to F-1;
		SWP:		IN integer range 0 to F-1;
		SWP_OFFSET:	IN integer range 0 to N*2-1;
 		ADD_WR_OUT: 	OUT std_logic_vector(log2N(NREG)-1 downto 0);
 		ADD_RD1_OUT: 	OUT std_logic_vector(log2N(NREG)-1 downto 0);
		ADD_RD2_OUT: 	OUT std_logic_vector(log2N(NREG)-1 downto 0));
	end component;

	component REGISTER_FILE is
	 generic( NBIT: integer := 64;
		  NREG: integer := 32);
 	port ( CLK: 		IN std_logic;
        	RESET: 		IN std_logic;
		ENABLE: 	IN std_logic;
		RD1: 		IN std_logic;
	 	RD2: 		IN std_logic;
	 	WR: 		IN std_logic;
	 	ADD_WR: 	IN std_logic_vector(log2N(NREG)-1 downto 0);
	 	ADD_RD1: 	IN std_logic_vector(log2N(NREG)-1 downto 0);
		ADD_RD2: 	IN std_logic_vector(log2N(NREG)-1 downto 0);
	 	DATAIN: 	IN std_logic_vector(NBIT-1 downto 0);
	        OUT1: 		OUT std_logic_vector(NBIT-1 downto 0);
	 	OUT2: 		OUT std_logic_vector(NBIT-1 downto 0));
	end component;

   signal INTERNAL_FILL, INTERNAL_SPILL : std_logic;
   signal INTERNAL_CWP, INTERNAL_SWP : integer range 0 to F-1;
   signal INTERNAL_SWP_OFFSET : integer range 0 to N*2-1;
   signal INTERNAL_ADD_WR, INTERNAL_ADD_RD1, INTERNAL_ADD_RD2 : std_logic_vector(log2N(NREG)-1 downto 0);
   signal INTERNAL_WR, INTERNAL_RD1 : std_logic;

begin 


	LOGIC_RF: LOGIC_REGISTER_FILE 
	--this component contains the logic behind the windows changing. it will manage the RET and CALL operations and output FILL and SPILL control signals.
		generic map(NBIT, NREG, M, N, F)
		port map(CLK, RESET, CALL, RET, INTERNAL_FILL, INTERNAL_SPILL, INTERNAL_CWP, INTERNAL_SWP, INTERNAL_SWP_OFFSET);

	ADDRESS_TRANS: ADDRESS_TRANSLATOR
	--this component translates the external address to physical address of the internal register file.
	--to do this, it needs the pointer to the current window (CWP) that is generated by the logic_register_file.
	--During a FILL/SPILL, thanks to the SWP and its offset, it calculates the current register of the physical register file to restore/save,
		generic map(NBIT, NREG, M, N, F)
		port map( ADD_WR, ADD_RD1, ADD_RD2, INTERNAL_FILL, INTERNAL_SPILL, INTERNAL_CWP, INTERNAL_SWP, INTERNAL_SWP_OFFSET,
			  INTERNAL_ADD_WR, INTERNAL_ADD_RD1, INTERNAL_ADD_RD2);

	RF: REGISTER_FILE --this is the standard register file described in the EX.1
		generic map(NBIT, NREG)
		port map(CLK, RESET, ENABLE, INTERNAL_RD1, RD2, INTERNAL_WR, INTERNAL_ADD_WR, INTERNAL_ADD_RD1, INTERNAL_ADD_RD2, DATAIN, OUT1, OUT2);

	--in case of a FILL the WRITE BUS will be used to restore the registers of a window, so if a FILL is executing the WR control signal must be HIGH
	--similarly during a SPILL the READ1 OUTPUT BUS will be used to read the registers by an ipothetical memory. 
	INTERNAL_WR <= WR or INTERNAL_FILL;
	INTERNAL_RD1 <= RD1 or INTERNAL_SPILL;
	FILL <= INTERNAL_FILL;
	SPILL <= INTERNAL_SPILL;

end STRUCTURAL;


configuration CFG_WINDOW_RF of WINDOW_REGISTER_FILE is
  for STRUCTURAL
  end for;
end configuration;
