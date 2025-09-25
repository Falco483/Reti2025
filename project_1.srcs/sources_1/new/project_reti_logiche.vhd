library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity project_reti_logiche is
    port (
        i_clk : in std_logic;
        i_rst : in std_logic;
        i_start : in std_logic;
        i_add : in std_logic_vector(15 downto 0);
        o_done : out std_logic;
        o_mem_addr : out std_logic_vector(15 downto 0);
        i_mem_data : in std_logic_vector(7 downto 0);
        o_mem_data : out std_logic_vector(7 downto 0);
        o_mem_we : out std_logic;
        o_mem_en : out std_logic
    );
end project_reti_logiche;

architecture project_reti_logiche_arch of project_reti_logiche is

    -- ============================
    -- DEFINIZIONE TIPI E STATI
    -- ============================
    
    type state_type is (
        IDLE,           
        READ_K1,
        READ_K2,
        READ_S,
        SET_S,
        SETTLE_S,
        LOAD_COEFF,
        SETTLE_COEFF,
        INIT_PROCESSING,
        PROCESSING,     
        DONE_STATE      
    );
    
    type coeff_array is array (0 to 6) of signed(7 downto 0);
    type data_buffer is array (0 to 6) of signed(7 downto 0);
    
    -- =====================
    -- SEGNALI INTERNI
    -- =====================
    
    signal current_state : state_type;
    signal next_state : state_type;
    
    -- Parametri
    signal K : std_logic_vector(15 downto 0);
    signal filter_select : std_logic;
    signal base_address : std_logic_vector(15 downto 0);
    signal current_index : integer := 0;
    
    -- Coefficienti e buffer
    signal coefficients : coeff_array;
    signal data_window : data_buffer := (others => (others => '0'));
    signal coeff_counter : integer := 0;
    
    -- Processing control
    signal processing_phase : integer := 0; -- 0=load, 1=calc, 2=norm, 3=write
    signal processing_counter : integer := 0;
    signal buffer_index : integer := 3;
    
    -- Computation signals
    signal temp_sum : signed(31 downto 0);
    signal normalized_result : signed(7 downto 0);
    
    -- Segnali memoria
    signal mem_addr_int : std_logic_vector(15 downto 0);
    signal mem_data_out_int : std_logic_vector(7 downto 0);
    signal mem_we_int : std_logic;
    signal mem_en_int : std_logic;
    signal done_int : std_logic;

begin

    -- =======================
    --   ASSEGNAZIONI OUTPUT
    -- =======================
    
    o_mem_addr <= mem_addr_int;
    o_mem_data <= mem_data_out_int;
    o_mem_we <= mem_we_int;
    o_mem_en <= mem_en_int;
    o_done <= done_int;

    -- ===============================
    --  PROCESSO: AGGIORNAMENTO STATO
    -- ===============================
    
    state_update_process : process(i_clk, i_rst, i_start)
    begin
        if i_rst = '1' then
            current_state <= IDLE;
        elsif rising_edge(i_clk) then
            current_state <= next_state;
            
            case next_state is
                when IDLE =>
                    if i_start = '1' then
                        next_state <= READ_K1;
                    end if;
                    
                when READ_K1 =>
                    next_state <= READ_K2;
                    
                when READ_K2 =>
                    next_state <= READ_S;
                    
                when READ_S =>
                    next_state <= SET_S;
                    
                when SET_S =>
                    next_state <= SETTLE_S;
                    
                when SETTLE_S=>
                    next_state <= LOAD_COEFF;
                    
                when LOAD_COEFF =>
                    next_state <= SETTLE_COEFF;
                    
                when SETTLE_COEFF =>
                    if coeff_counter >=  6 then
                        next_state <= INIT_PROCESSING;
                    else
                        next_state <= LOAD_COEFF;
                    end if;
                    
                when INIT_PROCESSING =>
                    next_state <= PROCESSING;
                    
                when PROCESSING =>
                    if processing_counter > to_integer(unsigned(K)) then
                        next_state <= DONE_STATE;
                    end if;
                    
                when DONE_STATE =>
                    if i_start = '0' then
                        next_state <= IDLE;
                    end if;
                    
            end case;
        end if;
        
    end process;

    -- =============================
    --  PROCESSO: LOGICA NEXT STATE
    -- =============================
    
    next_state_logic : process(current_state, i_start)
    begin
       
    end process;

    -- ==================================
    --   PROCESSO: CONTROLLO PRINCIPALE
    -- ==================================
    
    main_control_process : process(i_clk, i_rst)
        variable shift_4, shift_6, shift_8, shift_10 : signed(31 downto 0);
        variable correction : signed(31 downto 0);
        variable final_result : signed(31 downto 0);
        variable acc : signed(31 downto 0); -- più grande per contenere il risultato
        variable to_ending : std_logic;
        
    begin
        acc := "00000000000000000000000000000000";
        final_result := "00000000000000000000000000000000";
        correction := "00000000000000000000000000000000";
        shift_4 := "00000000000000000000000000000000";
        shift_6 := "00000000000000000000000000000000";
        shift_8 := "00000000000000000000000000000000";
        shift_10 := "00000000000000000000000000000000";
        to_ending := '0';
        
        if i_rst = '1' then
            -- Reset
            K <= (others => '0');
            filter_select <= '0';
            base_address <= (others => '0');
            coefficients <= (others => (others => '0'));
            data_window <= (others => (others => '0'));
            mem_addr_int <= (others => '0');
            mem_data_out_int <= (others => '0');
            mem_we_int <= '0';
            mem_en_int <= '0';
            done_int <= '0';
            current_index <= 0;
            coeff_counter <= 0;
            processing_counter <= 0;
            processing_phase <= 0;
            buffer_index <= 3;
            temp_sum <= (others => '0');
            normalized_result <= (others => '0');
            
        elsif rising_edge(i_clk) then
        
            case current_state is
                
                when IDLE =>
                    done_int <= '0';
                    base_address <= i_add;
                    mem_en_int <= '1';
                    mem_we_int <= '0';
                    current_index <= to_integer(unsigned(i_add))+1;
                    
                when READ_K1 =>
                    mem_addr_int <= std_logic_vector(to_unsigned(current_index, 16));
                    current_index <= current_index + 1;
                    
                when READ_K2 =>
                    K(15 downto 8) <= i_mem_data;
                    mem_addr_int <= std_logic_vector(to_unsigned(current_index, 16));
                    current_index <= current_index + 1;
                    
                when READ_S =>
                    K(7 downto 0) <= i_mem_data;
                    mem_addr_int <= std_logic_vector(to_unsigned(current_index, 16));           
                   
                when SET_S =>
                    filter_select <= i_mem_data(0);
                    if i_mem_data(0) = '0' then 
                        current_index <= current_index; -- Start at C1 for order 3
                        mem_addr_int <= std_logic_vector(to_unsigned(current_index, 16));
                    else 
                        current_index <= current_index + 7; -- Start at C8 for order 5
                        mem_addr_int <= std_logic_vector(to_unsigned(current_index + 7, 16));
                    end if;
                    
                    -- SETTLE_S here just to make it settle
                    
                when LOAD_COEFF =>
                    -- Load [coeff_counter]-esimo element
                    coefficients(coeff_counter) <= signed(i_mem_data);
                    if coeff_counter <  6 then
                        coeff_counter <= coeff_counter + 1;
                        current_index <= current_index + 1;
                        mem_addr_int <= std_logic_vector(to_unsigned(current_index + 1, 16));
                    end if;
                    
                -- SETTLE_COEFF in between each phase to let em settle
                
                when INIT_PROCESSING =>
                    if filter_select = '0' then
                        coefficients(0) <= (others => '0');
                        coefficients(6) <= (others => '0');
                    end if;
                    current_index <= to_integer(unsigned(base_address)) + 17;
                    mem_addr_int <= std_logic_vector(to_unsigned(to_integer(unsigned(base_address)) + 17, 16));
                    mem_en_int <= '1';
                    --  mem_addr_int <= std_logic_vector(to_unsigned(     to_integer(unsigned(base_address)) + 17 + processing_counter, 16));
                
                when PROCESSING =>
                if processing_counter < to_integer(unsigned(K) + 1) then
                    
                    case processing_phase is
                    
                        when 0 => -- SETUP PHASE
                            processing_phase <= 1;
                            mem_en_int <= '1';
                            mem_we_int <= '0';

                        
                        when 1 => -- WAIT PHASE
                            processing_phase <= 2;
                            
                        
                        when 2 => -- LOAD PHASE
                            -- Carica il dato nel buffer
                            if buffer_index < 7 then
                                -- Caricamento sequenziale nelle prime 7 posizioni
                                data_window(buffer_index) <= signed(i_mem_data);
                                buffer_index <= buffer_index + 1;
                                
                                -- Prepara prossimo indirizzo
                                current_index <= current_index + 1;
                                mem_addr_int <= std_logic_vector(to_unsigned(current_index + 1, 16));
                                
                                -- Se abbiamo caricato tutti i 7 elementi, inizia il calcolo
                                if buffer_index = 6 then
                                    processing_phase <= 3; -- Vai a CALCULATE
                                else
                                    processing_phase <= 1; -- Continua a caricare (WAIT)
                                end if;
                                
                            else
                                -- Sliding window: shift left e inserisci nuovo
                                for i in 0 to 5 loop
                                    data_window(i) <= data_window(i + 1);
                                end loop;
                                if processing_counter > to_integer(unsigned(K)- 4) then
                                    data_window(6) <= "00000000" ;
                                else    
                                    data_window(6) <= signed(i_mem_data);
                                end if;
                                
                                -- Prepara prossimo indirizzo
                                current_index <= current_index + 1;
                                mem_addr_int <= std_logic_vector(to_unsigned(current_index + 1, 16));
                                
                                processing_phase <= 3; -- Vai a CALCULATE
                            end if;
                            
                        when 3 => -- CALCULATE PHASE
                            acc := (others => '0');
                            processing_counter <= processing_counter + 1;
        
                            -- Convolution: sum(coefficients[i] * data_window[i])
                            for i in 0 to 6 loop
                                acc := acc + (coefficients(i) * data_window(i));
                            end loop;
                            temp_sum <= acc; -- aggiorno il segnale solo alla fine

                            processing_phase <= 4;
                            
                        when 4 => -- NORMALIZE PHASE
                              -- Normalization with shift approximation
                                if filter_select = '0' then
                                    -- Order 3: 1/12 ? 1/16 + 1/64 + 1/256 + 1/1024
                                    shift_4 := temp_sum;
                                    for i in 0 to 3 loop
                                        shift_4 := shift_4(31) & shift_4(31 downto 1);
                                    end loop;
                                    
                                    shift_6 := temp_sum;
                                    for i in 0 to 5 loop
                                        shift_6 := shift_6(31) & shift_6(31 downto 1);
                                    end loop;
                                    
                                    shift_8 := temp_sum;
                                    for i in 0 to 7 loop
                                        shift_8 := shift_8(31) & shift_8(31 downto 1);
                                    end loop;
                                    
                                    shift_10 := temp_sum;
                                    for i in 0 to 9 loop
                                        shift_10 := shift_10(31) & shift_10(31 downto 1);
                                    end loop;
                                    
                                    -- Apply correction for negative values
                                    correction := (others => '0');
                                    if shift_4 < 0 then correction := correction + 1; end if;
                                    if shift_6 < 0 then correction := correction + 1; end if;
                                    if shift_8 < 0 then correction := correction + 1; end if;
                                    if shift_10 < 0 then correction := correction + 1; end if;
                                    
                                    final_result := shift_4 + shift_6 + shift_8 + shift_10 + correction;
                                    
                                else
                                    -- Order 5: 1/60 ? 1/64 + 1/1024
                                    shift_6 := temp_sum;
                                    for i in 0 to 5 loop
                                        shift_6 := shift_6(31) & shift_6(31 downto 1);
                                    end loop;
                                    
                                    shift_10 := temp_sum;
                                    for i in 0 to 9 loop
                                        shift_10 := shift_10(31) & shift_10(31 downto 1);
                                    end loop;
                                    
                                    correction := (others => '0');
                                    if shift_6 < 0 then correction := correction + 1; end if;
                                    if shift_10 < 0 then correction := correction + 1; end if;
                                    
                                    final_result := shift_6 + shift_10 + correction;
                                end if;
                                
                                -- Saturation
                                if final_result > to_signed(127, final_result'length) then
                                    normalized_result <= to_signed(127, 8);
                                elsif final_result < to_signed(-128, final_result'length) then
                                    normalized_result <= to_signed(-128, 8);
                                else
                                    normalized_result <= final_result(7 downto 0);
                                end if;

                            
                            processing_phase <= 5;
                            
                        when 5 => -- WRITE PHASE
                            mem_addr_int <= std_logic_vector(to_unsigned(
                                to_integer(unsigned(base_address)) + 16 + 
                                to_integer(unsigned(K)) + processing_counter, 16));
                            mem_data_out_int <= std_logic_vector(normalized_result);
                            
                            processing_phase <= 6;
                            
                        when 6 =>
                            mem_we_int <= '1';

                            processing_phase <= 7;
                            
                        when 7 =>
                            processing_phase <= 8;
                            
                        when 8 =>                        
                            mem_addr_int <= std_logic_vector(to_unsigned(current_index, 16));
                            if processing_counter + 1 < to_integer(unsigned(K)) then
                                processing_phase <= 0; -- Continua con WAIT
                            else
                                processing_phase <= 9; -- Finito
                            end if;
                            mem_we_int <= '0'; 
                            
                        when others =>
                            processing_phase <= 1;
                            
                    end case; -- fine case processing_phase
                    
                    else
                        -- Processing complete
                        mem_we_int <= '0';
                        mem_en_int <= '0';

                end if; -- fine if processing_counter < K
                
                when DONE_STATE =>
                    done_int <= '1';
                    mem_we_int <= '0';
                    mem_en_int <= '0';
                    K <= (others => '0');
                    filter_select <= '0';
                    base_address <= (others => '0');
                    coefficients <= (others => (others => '0'));
                    data_window <= (others => (others => '0'));
                    mem_addr_int <= (others => '0');
                    mem_data_out_int <= (others => '0');
                    mem_we_int <= '0';
                    mem_en_int <= '0';
                    current_index <= 0;
                    coeff_counter <= 0;
                    processing_counter <= 0;
                    processing_phase <= 0;
                    buffer_index <= 3;
                    temp_sum <= (others => '0');
                    normalized_result <= (others => '0');

            when others =>
                null;
                
        end case; -- fine case current_state
    end if; -- fine if i_rst
end process;

end project_reti_logiche_arch;