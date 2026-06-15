`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09.06.2026 20:17:52
// Design Name: 
// Module Name: i2c_master
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module i2c_master #(
    parameter CLK_FREQ = 50_000_000, 
    parameter SCL_FREQ = 100_000,    
    parameter DIVIDER = (CLK_FREQ / (4 * SCL_FREQ)) - 1 
)(
    input  wire       clk,        // System clock
    input  wire       rst_n,      // Active-low async reset
    input  wire       cmd_valid,  // Pulse: start transaction
    input  wire [6:0] addr,       // 7-bit slave address
    input  wire       rw,         // 0=write, 1=read
    input  wire [8:0] wdata,      // Byte to write and if more byte is to be transfered
    
    output reg  [7:0] rdata,      // Byte read from slave
    output reg        busy,       // 1 while transaction active
    output reg        ack_err,    // 1 if NACK received
    output reg        timeout_err,// Timeout error flag to be used by watchdog timer
    
    inout  wire       scl,        // I2C clock (open-drain)
    inout  wire       sda         // I2C data (open-drain)
);

    // States
    localparam [3:0] IDLE=4'd0, START=4'd1, ADDR_SEND=4'd2, ADDR_ACK=4'd3, DATA_WRITE=4'd4, WRITE_ACK=4'd5, DATA_READ=4'd6;
    localparam [3:0] READ_ACK=4'd7, STOP=4'd8;
    localparam [1:0] LOW=2'd0, RISE=2'd1, HIGH=2'd2, FALL=2'd3;
    localparam [7:0] T_BUF_CYCLES = 8'd235; 

    // Registers to be used
    reg [3:0] state, next_state;
    reg [7:0] count_s;
    reg [2:0] add_count;
    reg [3:0] data_count;
    reg [1:0] scl_phase;
    reg arb_lost;
    reg [15:0] watchdog;  // For Watchdog timer
    reg [6:0] address;  // For handeling the address
    reg [8:0] data_io;  // For handeling the data
    reg mode; 
    reg [7:0] bus_free_timer; 
    reg bus_is_free;
    reg more_byte; // More bytes are to be transfered or not
    // For open drain logic and wires
    wire scl_in;
    reg  scl_oe, sda_oe;
    wire sda_in;
    wire scl_ip, sda_ip;
    // Synchronizer Registers
    reg [3:0] scl_sync;
    reg [3:0] sda_sync;
    assign scl = scl_oe ? 1'b0 : 1'bz;
    assign scl_ip = scl;
    assign scl_in = ((scl_sync[1] & scl_sync[2]) | (scl_sync[2] & scl_sync[3]) | (scl_sync[1] & scl_sync[3]));
    assign sda = sda_oe ? 1'b0 : 1'bz;
    assign sda_ip = sda;
    assign sda_in = (sda_sync[1] & sda_sync[2]) | (sda_sync[2] & sda_sync[3]) | (sda_sync[1] & sda_sync[3]);
    
    // Timers and Counters and Master reset
    always@(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
        begin
            state <= 4'b0;
            count_s <= 8'b0;
            scl_phase <= 2'b0;
            add_count <= 3'b0;
            data_count <= 4'b0;
            watchdog <= 16'b0;
            bus_free_timer <= 8'b0;
            address <= 7'b0;
            data_io <= 9'b0;
            mode <= 1'b0;
            rdata <= 8'b0;
            ack_err <= 1'b0;
            timeout_err <= 1'b0;
            arb_lost <= 1'b0;
            bus_is_free <= 1'b0;
            more_byte <= 1'b0;
            sda_sync <= 4'b1111;
            scl_sync <= 4'b1111;
        end
        else
        begin
            // 1. Bus Free Monitor
            if (scl_in && sda_in)
            begin
                if (bus_free_timer == T_BUF_CYCLES)
                begin
                    bus_is_free <= 1'b1;
                end
                else
                begin
                    bus_free_timer <= bus_free_timer + 1;
                end
            end 
            else 
            begin
                bus_free_timer <= 8'd0; 
                bus_is_free <= 1'b0;
            end

            // 2. Watchdog and Phase Counting
            if ((scl_phase == HIGH && scl_in == 1'b0) && (state != IDLE))
            begin
                // Stretched
                if (watchdog == 16'd50000)
                     timeout_err <= 1'b1;
                else
                     watchdog <= watchdog + 1;
            end 
            else 
            begin
                // Normal progression
                watchdog <= 16'b0;
                if (count_s == DIVIDER)
                begin
                    count_s <= 8'b0;
                    scl_phase <= scl_phase + 1;
                end 
                else 
                begin
                    count_s <= count_s + 1;
                end
            end
            
            // 3. Tracking scl and sda lines
            scl_sync <= {scl_sync[2:0],scl_ip};
            sda_sync <= {sda_sync[2:0],sda_ip};
            
            
            // 4. State updation
            if(count_s == DIVIDER && scl_phase == FALL)
                state <= next_state;
                
            // 5. DataPath Logic
            
            // IDLE state reset
            if(state == IDLE)
            begin
               address <= 7'b0;
               mode <= 1'b0;
               data_io <= 9'b0;
               more_byte <= 1'b0;
               rdata <= 8'b0;
               add_count <= 3'b0;
               data_count <= 4'b0;
               arb_lost <= 1'b0;
               ack_err <= 1'b0;
               timeout_err <= 1'b0;
            end
                
            // Address and data Sampling
            if(state == START && scl_phase == LOW && count_s == DIVIDER)
            begin
                address <= addr;
                mode <= rw;
                data_io <= (rw) ? 9'b0 : wdata;
                more_byte <= (rw) ? 1'b0 : wdata[0];
                bus_is_free <= 1'b0;
            end
            
            // Arbitration checking
            if(state == ADDR_SEND || state == DATA_WRITE)
            begin
                if(count_s == DIVIDER && scl_phase == HIGH)
                begin   
                    if(sda_oe == 0 && sda_in == 0)
                    arb_lost <= 1'b1;
                end
            end
            
            // Address updation
            if(state == ADDR_SEND && scl_phase == FALL && count_s == DIVIDER)
            begin
                address <= {address[5:0],mode};
                add_count <= add_count + 1;
            end
            
            // Address Acknowledgement
            if(state == ADDR_ACK && scl_phase == HIGH && count_s == DIVIDER)
            begin
                if(sda_in == 1'b0)
                    ack_err <= 1'b0;
                else
                    ack_err <= 1'b1;
            end
            
            // Data Writing
            if(state == DATA_WRITE && scl_phase == FALL && count_s == DIVIDER)
            begin
                data_count <= data_count + 1;
                data_io <= {data_io[7:0],1'b0};
            end
            
            // Data Write ACK
            if(state == WRITE_ACK && scl_phase == FALL && count_s == DIVIDER)
            begin
                if(data_count == 4'd8 && more_byte)
                begin
                    data_count <= 4'b0;
                    data_io <= wdata;
                    more_byte <= wdata[0];
                end
            end
            if(state == WRITE_ACK && scl_phase == HIGH && count_s == DIVIDER)
            begin    
                if(sda_in == 1'b0)
                    ack_err <= 1'b0;
                else
                    ack_err <= 1'b1;
                    
            end
            
            // Reading the Data
            if(state == DATA_READ && scl_phase == HIGH && count_s == DIVIDER)
            begin
                data_count <= data_count + 1;
                data_io <= {data_io[7:0], sda_in};
            end
            
            // Read Data ACK
            if(state == READ_ACK && scl_phase == LOW && count_s == DIVIDER)
            begin
                if(data_count == 4'd8)
                begin
                    rdata <= data_io[7:0];
                    if(more_byte)
                    begin
                        data_count <= 4'b0;
                        data_io <= 9'b0;
                    end
                end
            end
        end
    end
    
    // FSM logic
    always@(*)
    begin
        next_state = state;
        scl_oe = 1'b0;
        sda_oe = 1'b0;
        busy = (state != IDLE);
        if (state == ADDR_SEND || state == ADDR_ACK || state == DATA_WRITE || state == WRITE_ACK || state == DATA_READ || state == READ_ACK)
        begin        
            if (scl_phase == LOW || scl_phase == FALL)
            begin
                scl_oe = 1'b1; 
            end 
            else 
            begin
                scl_oe = 1'b0;
            end
        end
        else if (state == START)
        begin
            if (scl_phase == FALL) scl_oe = 1'b1; // FIX: Drop SCL before jumping to ADDR_SEND!
        end
        
        
        // Tracking for error
        if(arb_lost || ack_err || timeout_err)
            next_state = IDLE;
            
        case(state)
            IDLE: // It is idle but constantly checking
            begin
                if(cmd_valid && bus_is_free)
                begin
                    next_state = START;
                end
            end    
            
            START: // The Transmission starts
            begin
                sda_oe = 1'b1;
                if(scl_phase == FALL && count_s == DIVIDER)
                begin
                    next_state = ADDR_SEND;  
                end
            end
            
            ADDR_SEND: // The Address is ready to be sent
            begin
                    sda_oe = !address[6];
                    if(add_count == 3'd7 && scl_phase == FALL && count_s == DIVIDER)
                        next_state = ADDR_ACK;
            end
            
            ADDR_ACK: // Acknowledgment signal
            begin
                if(scl_phase == FALL && count_s == DIVIDER)
                begin
                    next_state = (mode) ? DATA_READ : DATA_WRITE;
                end
            end
            
            DATA_WRITE: // Data to be written by the master
            begin
                sda_oe = !data_io[8];
                if(scl_phase == FALL && count_s == DIVIDER)
                begin
                    if(data_count == 4'd7)
                    next_state = WRITE_ACK;
                end
            end
            
            WRITE_ACK: // Acknowledgement to the write data
            begin
                if(scl_phase == FALL && count_s == DIVIDER)
                begin
                    if(more_byte)
                        next_state = DATA_WRITE;
                    else
                        next_state = STOP;
                end
            end
            
            DATA_READ: // Reading the data from the slave
            begin
                sda_oe = 1'b0;
                if(scl_phase == FALL && count_s == DIVIDER)
                begin
                    if(data_count == 4'd8)
                        next_state = READ_ACK;
                end
            end
            
            READ_ACK: // Acknowledgement to the read data
            begin
                sda_oe = more_byte ? 1'b1 : 1'b0;
                if(scl_phase == FALL && count_s == DIVIDER)
                begin                        
                    if(more_byte)
                        next_state = DATA_READ;
                    else
                        next_state = STOP;
                end
            end
            
            STOP: // Transaction complete
            begin
                if(scl_phase == LOW)
                begin
                    scl_oe = 1'b1;
                    sda_oe = 1'b1;  
                end
                else 
                if(scl_phase == RISE || scl_phase == HIGH) 
                begin
                    scl_oe = 1'b0;
                    sda_oe = 1'b1;
                end 
                else 
                begin
                    scl_oe = 1'b0;
                    sda_oe = 1'b0; 
                end 
                
                if (count_s == DIVIDER && scl_phase == FALL)
                    next_state = IDLE; 
            end
            default:
            begin
                 next_state = state; 
            end
        endcase
    end    
endmodule