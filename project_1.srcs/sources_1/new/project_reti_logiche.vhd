library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity project_reti_logiche is
    port (
        i_clk : in std_logic;
        i_rst : in std_logic;
        i_start : in std_logic;
        i_add : in std_logic_vector(15 downto 0);            -- Indirizzo base da cui leggere
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
        IDLE,           -- Stato di attesa
        SETUP,          -- Setup iniziale e lettura parametri
        READ_K1,
        READ_K2,
        READ_S,
        INIT_COEFF,
        LOAD_FILTER,
        PROCESSING,     -- Elaborazione dati (stati futuri)
        DONE_STATE      -- Stato fine parte iniziale
    );
    
    type coeff_array is array (0 to 6) of std_logic_vector(7 downto 0); -- per i coefficienti del filtro
    type data_buffer is array (0 to 6) of std_logic_vector(7 downto 0); -- per finestra scorrevole di dati
    
    -- ============================
    -- SEGNALI INTERNI
    -- ============================
    
    -- Controllo FSM
    signal current_state : state_type;
    signal next_state : state_type;
    
    -- Parametri del progetto
    signal K : std_logic_vector(15 downto 0);          -- Lunghezza sequenza
    signal K1 : std_logic_vector(7 downto 0);          -- Byte alto di K
    signal K2 : std_logic_vector(7 downto 0);          -- Byte basso di K
    signal filter_select : std_logic;                  -- Tipo filtro (0=ord3, 1=ord5)  da togliere
    signal base_address : std_logic_vector(15 downto 0);  -- Indirizzo base (i_add)
    signal current_index : integer :=0;                  -- Indice corrente
    
    -- Coefficienti e buffer dati
    signal coefficients : coeff_array;                 -- Coefficienti filtro
    signal data_window : data_buffer := (
    0 => (others => '0'),
    1 => (others => '0'),
    2 => (others => '0'),
    3 => (others => '0'),
    4 => (others => '0'),
    5 => (others => '0'),
    6 => (others => '0')
);                 -- Finestra dati per filtro
    signal coeff_counter : integer := 0;
    
    -- segnali per scrittura
    signal R1 : std_logic_vector(7 downto 0);
    signal current_R : std_logic_vector(7 downto 0);
    signal start_load : integer := 0;
    signal start_compute : integer :=0 ;
    
    -- Segnali di controllo memoria
    signal mem_addr_int : std_logic_vector(15 downto 0);
    signal mem_data_out_int : std_logic_vector(7 downto 0);
    signal mem_we_int : std_logic;
    signal mem_en_int : std_logic;
    
    -- Segnali di output
    signal done_int : std_logic;
    
        -- ============================
    -- SEGNALI AGGIUNTIVI DA AGGIUNGERE NELLA SEZIONE SIGNALS
    -- ============================
    
    -- Buffer per finestra scorrevole (7 elementi per ordine 5, ma usiamo sempre 7)
    type buffer_array is array (0 to 6) of signed(7 downto 0);
    
    -- Indice per caricamento buffer
    signal index_load_buffer : integer := 3; -- Inizializzato a 3 (primi 3 sono 0)
    
    -- Variabile per risultato prima della normalizzazione
    signal to_normalize : signed(31 downto 0) := (others => '0');
    
    -- Variabile per risultato normalizzato finale
    signal normalized_result : signed(7 downto 0) := (others => '0');
    
    -- Contatore per elaborazione dati
    signal processing_counter : integer := 0;
    
    -- Segnali di controllo per le funzioni
    signal load_buffer_enable : std_logic := '0';
    signal calculate_r_enable : std_logic := '0';
    signal normalize_enable : std_logic := '0';
    signal write_result_enable : std_logic := '0';

begin

    -- ============================
    -- ASSEGNAZIONI OUTPUT
    -- ============================
    
    o_mem_addr <= mem_addr_int;
    o_mem_data <= mem_data_out_int;
    o_mem_we <= mem_we_int;
    o_mem_en <= mem_en_int;
    o_done <= done_int;

    -- ============================
    -- PROCESSO: AGGIORNAMENTO STATO
    -- ============================
    
    state_update_process : process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            current_state <= IDLE;
        elsif rising_edge(i_clk) then
            current_state <= next_state;
        end if;
    end process;

    -- ============================
    -- PROCESSO: LOGICA NEXT STATE
    -- ============================
    
    next_state_logic : process(current_state)
    begin
        next_state <= current_state;  -- Default: rimani nello stato corrente
        
        case current_state is
            when IDLE =>
                if i_start = '1' then
                    next_state <= READ_K1;
                end if;
                
            when READ_K1 =>
                next_state <= READ_K2;
                
            when READ_K2 =>
                next_state <= READ_S;
                
            when READ_S =>
                next_state <= INIT_COEFF;
                
            when INIT_COEFF =>
                next_state <= PROCESSING;
                
            when LOAD_FILTER =>
                if ((current_index < 17 and filter_select = '1') or (current_index < 8 and filter_select = '0')) then    
                    next_state <= LOAD_FILTER;
                else
                    next_state <= PROCESSING;
                end if;    
            when PROCESSING =>
                if ( mem_addr_int = R1) then 
                    next_state <= DONE_STATE;  -- Placeholder
                end if;
                
                
            when DONE_STATE =>
                if i_start = '0' then
                    next_state <= IDLE;
                end if;
                
        end case;
    end process;

    -- ============================
    -- PROCESSO: CONTROLLO MEMORIA E SETUP
    -- ============================
    
    -- Ciclo 1: PROCESSING : Load dato 0 nel buffer
    -- Ciclo 2: PROCESSING : Calcola filtro per posizione 0  
    -- Ciclo 3: PROCESSING : Normalizza risultato 0
    -- Ciclo 4: PROCESSING : Scrivi R0 a indirizzo (ADD+17+K+0)

    -- Ciclo 5: PROCESSING : Load dato 1 (shift buffer)
    -- ..
    -- Ciclo 8: PROCESSING : Scrivi R1 a indirizzo (ADD+17+K+1)
       
    -- ( itero k volte )
    
    -- Ultimo ciclo: results_written = K & next_state = DONE_STATE
    
    memory_control_process : process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            -- Reset di tutti i segnali
            K <= (others => '0');
            filter_select <= '0';
            base_address <= (others => '0');
            coefficients <= (others => (others => '0'));
            mem_addr_int <= (others => '0');
            mem_data_out_int <= (others => '0');
            mem_we_int <= '0';
            mem_en_int <= '0';
            
        elsif rising_edge(i_clk) then
            
            case current_state is
                
                when IDLE =>
                    -- Preparazione per l'inizio
                    base_address <= i_add;  -- metto inizio sequenza in base_address
                    mem_we_int <= '0';      -- Sempre in lettura durante il setup
                    
                when READ_K1 =>
                    -- Richiedi lettura di K1 (byte alto)
                    mem_addr_int <= base_address;
                    current_index <= to_integer(unsigned(base_address));
                    mem_en_int <= '1';
                    
                when READ_K2 =>
                    -- Salva K1 e richiedi K2 (byte basso)
                    K(15 downto 8) <= i_mem_data;  -- Salva K1 nel byte alto
                    current_index <= current_index + 1;
                    mem_addr_int <= std_logic_vector(to_unsigned(current_index, 16));
                    mem_en_int <= '1';
                    
                when READ_S =>
                    -- Salva K2 e richiedi S (tipo filtro)
                    K(7 downto 0) <= i_mem_data;   -- Salva K2 nel byte basso
                    current_index <= current_index + 1;
                    mem_addr_int <= std_logic_vector(to_unsigned(current_index, 16));
                    mem_en_int <= '1';
                    
                when INIT_COEFF =>
                    -- Salva tipo filtro e inizializza coefficienti
                    filter_select <= i_mem_data(0);
                    mem_en_int <= '0';  -- Disabilita memoria ( da ricontrollare ) 
                    
                    -- Inizializza coefficienti in base al filtro
                    if filter_select = '0' then 
                        current_index <= current_index + 1;
                    mem_addr_int <= std_logic_vector(to_unsigned(current_index, 16));
                    else 
                        current_index <= current_index + 8;
                    mem_addr_int <= std_logic_vector(to_unsigned(current_index, 16));
                        
                    end if;
                    
                when LOAD_FILTER =>
                    coefficients(coeff_counter) <= i_mem_data;
                    coeff_counter <= coeff_counter +1;
                    current_index <= current_index +1;
                    mem_addr_int <= std_logic_vector(to_unsigned(current_index, 16));
                    mem_en_int <= '1';
                    if (next_state = PROCESSING ) then
                        coeff_counter <= 0;
                    end if;
                    
                when PROCESSING =>
                    if ( coeff_counter < to_Integer(unsigned(K))) then 
                        -- qua va uno start_load = 1 no?
                        coeff_counter <= coeff_counter + 1;
                    end if;
                    -- e poi else (next_state = done_state);
                                            
                when DONE_STATE =>
                    -- Mantieni tutto disabilitato
                    mem_en_int <= '0';
                    
            end case;
            
        end if;
    end process;

    -- ============================
    -- PROCESSO: CONTROLLI OUTPUT
    -- ============================
    
output_control : process(current_state)
    begin
        -- Valori di default
        done_int <= '0';
        
        case current_state is
            when IDLE | READ_K1 | READ_K2 | READ_S | INIT_COEFF | PROCESSING =>
                done_int <= '0';
                
            when DONE_STATE =>
                done_int <= '1';
                
        end case;
    end process;

    -- ==============
    -- LOAD BUFFER
    -- ==============
    
    load_buffer : process( start_load )
    begin
            
            if start_load = 1 then
                
                if index_load_buffer < 7 then
                    -- Prima fase: caricamento iniziale (4 valori)
                    -- Posizioni 0,1,2 rimangono a 0 (padding iniziale)
                    data_window(index_load_buffer) <= (i_mem_data);
                    index_load_buffer <= index_load_buffer + 1;
                    
                else
                    -- Fase scorrevole: shift a sinistra e nuovo valore in ultima posizione
                    -- Sposta tutti gli elementi di una posizione a sinistra
                    for i in 0 to 5 loop
                        data_window(i) <= data_window(i + 1);
                    end loop;
                    
                    -- Inserisce nuovo valore nell'ultima posizione
                    data_window(6) <= (i_mem_data);
                    -- index_load_buffer rimane a 7;

                end if;
                    if (index_load_buffer = 7) then
                        start_compute <= 1;
                    end if;
                start_load <= 0;

            end if;
             
    end process;
    
    
    -- ======================
    -- CALCOLO RISULTATO
    -- ======================
calculate_R : process( start_compute )
    variable temp_sum : signed(31 downto 0);
    variable filter_length : integer;

    begin
        if start_compute = 1 then      
            if calculate_r_enable = '1' then
                
                temp_sum := (others => '0');
               
                -- sommatoria (coefficients[i] * data_buffer[i])
                for i in 0 to 6 loop
                    temp_sum := temp_sum + (signed(coefficients(i)) * signed(data_window(i)));
                end loop;
                
                -- risultato in to_normalize
                to_normalize <= temp_sum;
                
            end if;            
            
            start_compute <= 0;
        end if;
    end process;

   
   
    -- ===================
    -- NORMALIZZAZIONE
    -- ===================
normalize : process ( to_normalize )

    variable temp_result : signed(31 downto 0);   
    variable shift_4, -- Shift fino a 16
             shift_6, -- Shift fino a 64
             shift_8, -- Shift fino a 256
             shift_10 : signed(31 downto 0);    -- Shift fino a 1024
    variable final_result : signed(31 downto 0);
    begin            
        temp_result := to_normalize;
        
        if filter_select = '0' then
        -- Filtro ordine 3: normalizzazione 1/12
            -- 1/12 = 1/16 + 1/64 + 1/256 + 1/1024 = >>4 + >>6 + >>8 + >>10
            
            -- Calcolo shift
            shift_4 := temp_result(31) & temp_result(31 downto 1);   -- >>1 equivale a /2, >>4 equivale a /16
            shift_4 := shift_4(31) & shift_4(31 downto 1);
            shift_4 := shift_4(31) & shift_4(31 downto 1);
            shift_4 := shift_4(31) & shift_4(31 downto 1);
            
            shift_6 := shift_4(31) & shift_4(31 downto 1);
            shift_6 := shift_6(31) & shift_6(31 downto 1);
            
            shift_8 := shift_6(31) & shift_6(31 downto 1);
            shift_8 := shift_8(31) & shift_8(31 downto 1);
            
            shift_10 := shift_8(31) & shift_8(31 downto 1);
            shift_10 := shift_10(31) & shift_10(31 downto 1);
            
            -- Correzione per numeri negativi
            final_result := shift_4 + shift_6 + shift_8 + shift_10;
            if shift_4 < 0 then
                final_result := final_result + 4;
            end if;
                        
        else
           shift_6 := temp_result(31) & temp_result(31 downto 1);
           shift_6 := shift_6(31) & shift_6(31 downto 1);
           shift_6 := shift_6(31) & shift_6(31 downto 1);
           shift_6 := shift_6(31) & shift_6(31 downto 1);
           shift_6 := shift_6(31) & shift_6(31 downto 1);
           shift_6 := shift_6(31) & shift_6(31 downto 1);

           shift_10 := shift_6(31) & shift_6(31 downto 1);
           shift_10 := shift_10(31) & shift_10(31 downto 1);
           shift_10 := shift_10(31) & shift_10(31 downto 1);
           shift_10 := shift_10(31) & shift_10(31 downto 1);
           
           -- Correzione per numeri negativi
            final_result := shift_6 + shift_10;
            if shift_6 < 0 then
                final_result := final_result + 2;
            end if;
        end if;
        
        if final_result > 127 then
            final_result := "01111111";
        end if;
        if final_result < -128 then
            final_result := "10000000";
        end if;
      
        write_result_enable <= '1';
    end process;
    
    
    -- ==========================
    -- PROCESSI FUTURI
    -- ==========================
    
    -- TODO: Aggiungere processo per scrittura risultati
    -- write_results_process : process(i_clk, i_rst)
write_results_process : process(write_result_enable)
    begin
        if write_result_enable = '1' then
                
                -- Indirizzo scrittura (che dovrebbe essere ADD + K + R[n-1] ?credo)
                mem_addr_int <= std_logic_vector(to_unsigned(
                    to_integer(unsigned(base_address)) + 17 + to_integer(unsigned(K)) + coeff_counter, 16)
                );
                    
                -- Wirte in memoria
                mem_data_out_int <= std_logic_vector(normalized_result);
                mem_we_int <= '1';
                mem_en_int <= '1';
                
                -- Disabilito? o non serve?
                write_result_enable <= '0';
        else
             mem_we_int <= '0';
        end if;
    end process;
        
    --TODO: fare process per inserire i primi quattro numeri in data_window
    --      e un altro per il calcolo e un altro ancora per la normalizzazzione
   

end project_reti_logiche_arch;