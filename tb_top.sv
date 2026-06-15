`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 14.06.2026 20:56:04
// Design Name: 
// Module Name: tb_top
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
//The Interface between TB and DUT
/*interface i2c_if (input logic clk, input logic rst_n);
    // CPU signals to control the Master
    logic       cmd_valid;
    logic [6:0] addr;
    logic       rw;
    logic [8:0] wdata;   // [8:1] Data payload, [0] more_byte flag
    
    // Outputs from the Master
    logic [7:0] rdata;
    logic       busy;
    logic       ack_err;
    logic       timeout_err;

    // Physical I2C Bus
    tri1 scl;
    tri1 sda;
    
    // Declearing the modports
    modport Imaster(
        input cmd_valid, input addr, input rw, input wdata, input clk, input rst_n, 
        output rdata, output busy, output ack_err, output timeout_err,
        inout sda, inout scl
    );
    modport Tbstimulus(
        input rdata, input busy, input ack_err, input timeout_err, input clk, input rst_n, 
        output cmd_valid, output addr, output rw, output wdata
    );
    
endinterface

// Transaction Class
class i2c_transaction;
    // Inputs
    rand bit [6:0] addr;
    rand bit       rw;
    rand bit [8:0] wdata;
    
    bit cmd_valid;
    
    // Outputs
    bit [7:0] rdata;
    bit       ack_err;
    bit       busy;
    bit       timeout_err;

    // Constraints
    constraint ValidAddress{
        addr inside {[7'b0001000 : 7'b1111110]}; // 0 to 7 is researved
    }
    constraint ValidData{
        if(rw == 1'b0){
            wdata inside {[9'b0 : 9'b111110110]};
            wdata%2 == 0;
        }
    }

    // Display Funstion
    function void display(input string name = "Transaction");
        $display("-----------------------------------------");
        $display("[%s] Address: 0x%0h | R/W: %s", name, addr, rw ? "READ" : "WRITE");
        if (rw == 0) begin
            $display("[%s] Write Data: 0x%0h | More Byte: %b", name, wdata[8:1], wdata[0]);
        end else begin
            $display("[%s] Read Data: 0x%0h | More Byte: %b", name, rdata, wdata[0]);
        end
        if (ack_err) $display("[%s] Result: NACK ERROR!", name);
        $display("-----------------------------------------");
    endfunction

    // Transation objects
    function i2c_transaction copy();
        i2c_transaction trans = new();
        trans.addr        = this.addr;
        trans.rw          = this.rw;
        trans.wdata       = this.wdata;
        trans.rdata       = this.rdata;
        trans.ack_err     = this.ack_err;
        trans.timeout_err = this.timeout_err;
        return trans;
    endfunction

endclass

// Generator class
class generator;
    // Mailbox and loop counter
    mailbox #(i2c_transaction) mbx_drv;
    mailbox #(i2c_transaction) mbx_scb;
    i2c_transaction trans;
    int transaction_count;

    // Constructor
    function new(mailbox #(i2c_transaction) mb_drv, mailbox #(i2c_transaction) mb_scb);
        mbx_drv = mb_drv;
        mbx_scb = mb_scb;
    endfunction

    // Main Task
    task main();
        repeat(transaction_count)
        begin
            trans = new();
            if(!trans.randomize())
                $fatal(1,"Randomisation Failed ...");
            mbx_drv.put(trans);
            mbx_scb.put(trans.copy());
            trans.display("Generator");
        end
    endtask
endclass

//Driver Class
class driver;
    // Virtual Interface and Mailbox
    mailbox #(i2c_transaction) mbx;
    virtual i2c_if.Tbstimulus vif;
    
    // Constructor
    function new(virtual i2c_if.Tbstimulus vif,  mailbox #(i2c_transaction) mb);
        mbx = mb;
        this.vif = vif;
    endfunction
    
    // Reset Task
    task reset();
        vif.cmd_valid = 0;
        vif.rw = 0;
        vif.addr = 0;
        vif.wdata = 0;
    endtask
    
    // Main Task
    i2c_transaction trans;
    task main();
        forever
        begin
            mbx.get(trans);
            @(posedge vif.clk); 
                wait(!vif.busy);
            vif.addr = trans.addr;
            vif.rw = trans.rw;
            vif.wdata = trans.wdata;
            @(posedge vif.clk)
                vif.cmd_valid = 1'b1;
            wait(vif.busy)// Wait till the transmission is acknowledged
            @(posedge vif.clk)
                vif.cmd_valid = 1'b0;
            wait(!vif.busy);
            $display("[DRIVER] Transaction completely driven to hardware.");
        end
    endtask
    
endclass

// Monitor Class
class monitor;
    // Interface and mailbox
    virtual i2c_if vif;
    mailbox #(i2c_transaction) mbx;
    
    // Constructor
    function new(mailbox #(i2c_transaction) mb, virtual i2c_if vif);
        this.vif = vif;
        this.mbx = mb;
    endfunction
    
    // Main Task
    i2c_transaction trans;
    task main();
         $display("[Monitor] Started monitoring interface pins...");
         forever
         begin
            @(posedge vif.clk); // To avoid race condition as forever loop has 0 delay
            wait(vif.busy);
            wait(!vif.busy);
            trans = new();
            trans.rdata = vif.rdata;
            trans.ack_err = vif.ack_err;
            trans.timeout_err = vif.timeout_err;
            mbx.put(trans);
         end
    endtask
endclass

// Scoreboard Class
class scoreboard;
    // Mail Box
    mailbox #(i2c_transaction) mbx_exp, mbx_act;
    
    //Expected data and counter
    localparam [7:0] EXPECTED_READ_DATA = 8'hA5;
    int completed_count = 0; 
    
    // Constructor
    function new(mailbox #(i2c_transaction) mbx_exp, mailbox #(i2c_transaction) mbx_act);
        this.mbx_exp = mbx_exp;
        this.mbx_act = mbx_act;
    endfunction

    // Main Task
    i2c_transaction trans_expected, trans_actual;
    task main();
        forever
        begin
            mbx_act.get(trans_actual);
            mbx_exp.get(trans_expected);
            
            if (trans_actual.timeout_err) 
            begin
                $error("[SCOREBOARD] FAIL: Hardware Watchdog Timeout!");
            end 
            else if (trans_actual.ack_err) 
            begin
                $error("[SCOREBOARD] FAIL: NACK received for Address 0x%0h!", trans_expected.addr);
            end 
            else 
            begin
                if (trans_expected.rw == 1'b1) 
                begin
                    if (trans_actual.rdata !== EXPECTED_READ_DATA)
                    begin
                        $error("[SCOREBOARD] FAIL: READ data mismatch from Addr 0x%0h. Expected 0x%0h, Got 0x%0h",
                                trans_expected.addr, EXPECTED_READ_DATA, trans_actual.rdata);
                    end
                    else
                    begin
                        $display("[SCOREBOARD] PASS: Successful READ from Addr 0x%0h. Data: 0x%0h", 
                                  trans_expected.addr, trans_actual.rdata);
                    end
                end 
                else 
                begin
                    $display("[SCOREBOARD] PASS: Successful WRITE to Addr 0x%0h. Payload: 0x%0h", 
                              trans_expected.addr, trans_expected.wdata[8:1]);
                end
            end
            completed_count++;
            $display("---------------------------------------------------");        
        end
    endtask
endclass

// Environment Class
class environment;
    // Instances of our classes
    generator  gen;
    driver     drv;
    monitor    mon;
    scoreboard scb;
    
    // Mailboxes
    mailbox #(i2c_transaction) mbx_gen_drv;
    mailbox #(i2c_transaction) mbx_gen_scb;
    mailbox #(i2c_transaction) mbx_mon_scb;
    
    // Virtual interface
    virtual i2c_if vif;
    
    // Constructor
    function new(virtual i2c_if vif);
        this.vif = vif;
        
        // Create the mailboxes
        mbx_gen_drv = new();
        mbx_gen_scb = new();
        mbx_mon_scb = new();
        
        // Instantiate the classes and connect them
        gen = new(mbx_gen_drv, mbx_gen_scb);
        drv = new(vif, mbx_gen_drv);          
        mon = new(mbx_mon_scb, vif);          
        scb = new(mbx_gen_scb, mbx_mon_scb);  
    endfunction
    
    // Run Task
    task run();
        // Tell generator to make 10 random transactions
        gen.transaction_count = 10; 
        
        // Reset the CPU signals
        drv.reset();
        
        // Run all classes in parallel
        fork
            gen.main();
            drv.main();
            mon.main();
            scb.main();
        join_any 
        
        // Give the simulation time to finish the last transaction
        wait (scb.completed_count == gen.transaction_count);
        $display("===================================================");
        $display("   TESTBENCH COMPLETE. FINISHING SIMULATION.       ");
        $display("===================================================");
        $finish;
    endtask
endclass

// Slave module
module mock_slave #(
    parameter [7:0] TX_DATA    = 8'hA5,
    parameter [6:0] NACK_ADDR  = 7'h7F
)(
    input  wire scl,
    inout  wire sda
);

    localparam [1:0] ST_ADDR  = 2'd0;
    localparam [1:0] ST_ACK_A = 2'd1;
    localparam [1:0] ST_DATA  = 2'd2;
    localparam [1:0] ST_ACK_D = 2'd3;

    reg [1:0]  state;
    reg [3:0]  bit_cnt;
    reg [6:0]  addr_shift;
    reg        rw_bit;
    reg [7:0]  tx_shift;
    reg        sda_drive;

    assign sda = sda_drive ? 1'b0 : 1'bz;

    reg scl_was_high_sda_low;

    always @(posedge scl) begin
        scl_was_high_sda_low <= ~sda;
    end

    always @(negedge scl) begin
        scl_was_high_sda_low <= 1'b0;
    end

    wire stop_condition = scl & sda & scl_was_high_sda_low;

    always @(negedge scl or posedge stop_condition) begin
        if (stop_condition) begin
            state     <= ST_ADDR;
            bit_cnt   <= 4'd0;
            sda_drive <= 1'b0;
        end else begin
            case (state)
                ST_ADDR: begin
                    sda_drive <= 1'b0;
                    if (bit_cnt < 4'd7) begin
                        addr_shift <= {addr_shift[5:0], sda};
                        bit_cnt    <= bit_cnt + 1;
                    end else begin
                        rw_bit  <= sda;
                        bit_cnt <= 4'd0;
                        state   <= ST_ACK_A;
                    end
                end

                ST_ACK_A: begin
                    if (addr_shift == NACK_ADDR) begin
                        sda_drive <= 1'b0;
                        state     <= ST_ADDR;
                        bit_cnt   <= 4'd0;
                    end else begin
                        sda_drive <= 1'b1;
                        tx_shift  <= TX_DATA;
                        state     <= ST_DATA;
                        bit_cnt   <= 4'd0;
                    end
                end

                ST_DATA: begin
                    if (bit_cnt < 4'd7) begin
                        if (rw_bit) begin
                            sda_drive <= ~tx_shift[7];
                            tx_shift  <= {tx_shift[6:0], 1'b0};
                        end else begin
                            sda_drive <= 1'b0;
                        end
                        bit_cnt <= bit_cnt + 1;
                    end else begin
                        if (rw_bit) begin
                            sda_drive <= ~tx_shift[7];
                            tx_shift  <= {tx_shift[6:0], 1'b0};
                        end else begin
                            sda_drive <= 1'b0;
                        end
                        bit_cnt <= 4'd0;
                        state   <= ST_ACK_D;
                    end
                end

                ST_ACK_D: begin
                    if (rw_bit) begin
                        sda_drive <= 1'b0;
                    end else begin
                        sda_drive <= 1'b1;
                    end
                    tx_shift <= TX_DATA;
                    bit_cnt  <= 4'd0;
                    state    <= ST_DATA;
                end

                default: begin
                    sda_drive <= 1'b0;
                    state     <= ST_ADDR;
                    bit_cnt   <= 4'd0;
                end
            endcase
        end
    end
endmodule

// Top Level Simulation Module
module tb_top();
    logic clk;
    logic rst_n;

    // Clock Generation (50 MHz)
    initial begin
        clk = 0;
        forever #10 clk = ~clk; 
    end

    // Instantiate 
    i2c_if vif(clk, rst_n);
    
    i2c_master dut (
        .clk         (vif.clk),
        .rst_n       (vif.rst_n),
        .cmd_valid   (vif.cmd_valid),
        .addr        (vif.addr),
        .rw          (vif.rw),
        .wdata       (vif.wdata),
        .rdata       (vif.rdata),
        .busy        (vif.busy),
        .ack_err     (vif.ack_err),
        .timeout_err (vif.timeout_err),
        .scl         (vif.scl),
        .sda         (vif.sda)  
    );
    
    mock_slave #(.TX_DATA(8'hA5), .NACK_ADDR(7'h7F)) slave_bfm (
    .scl(vif.scl),
    .sda(vif.sda)
    );
    
    environment env;

    initial begin
        // Reset
        rst_n = 0;
        #100;
        rst_n = 1;
        #100;
        
        // Tests
        env = new(vif);
        env.run();
    end
    
endmodule*/
`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 14.06.2026 20:56:04
// Design Name: 
// Module Name: tb_top
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

//The Interface between TB and DUT
interface i2c_if (input logic clk, input logic rst_n);
    // CPU signals to control the Master
    logic       cmd_valid;
    logic [6:0] addr;
    logic       rw;
    logic [8:0] wdata;   // [8:1] Data payload, [0] more_byte flag
    
    // Outputs from the Master
    logic [7:0] rdata;
    logic       busy;
    logic       ack_err;
    logic       timeout_err;

    // Physical I2C Bus
    tri1 scl;
    tri1 sda;
    
    // Declearing the modports
    modport Imaster(
        input cmd_valid, input addr, input rw, input wdata, input clk, input rst_n, 
        output rdata, output busy, output ack_err, output timeout_err,
        inout sda, inout scl
    );
    modport Tbstimulus(
        input rdata, input busy, input ack_err, input timeout_err, input clk, input rst_n, 
        output cmd_valid, output addr, output rw, output wdata
    );
    
endinterface

// Transaction Class
class i2c_transaction;
    // Inputs
    rand bit [6:0] addr;
    rand bit       rw;
    rand bit [8:0] wdata;
    
    bit cmd_valid;
    
    // Outputs
    bit [7:0] rdata;
    bit       ack_err;
    bit       busy;
    bit       timeout_err;

    // Constraints
    constraint ValidAddress{
        addr inside {[7'b0001000 : 7'b1111110]}; // 0 to 7 is researved
    }
    constraint ValidData{
        if(rw == 1'b0){
            wdata inside {[9'b0 : 9'b111110110]};
            wdata%2 == 0;
        }
    }

    // Display Funstion
    function void display(input string name = "Transaction");
        $display("-----------------------------------------");
        $display("[%s] Address: 0x%0h | R/W: %s", name, addr, rw ? "READ" : "WRITE");
        if (rw == 0) begin
            $display("[%s] Write Data: 0x%0h | More Byte: %b", name, wdata[8:1], wdata[0]);
        end else begin
            $display("[%s] Read Data: 0x%0h | More Byte: %b", name, rdata, wdata[0]);
        end
        if (ack_err) $display("[%s] Result: NACK ERROR!", name);
        $display("-----------------------------------------");
    endfunction

    // Transation objects
    function i2c_transaction copy();
        i2c_transaction trans = new();
        trans.addr        = this.addr;
        trans.rw          = this.rw;
        trans.wdata       = this.wdata;
        trans.rdata       = this.rdata;
        trans.ack_err     = this.ack_err;
        trans.timeout_err = this.timeout_err;
        return trans;
    endfunction

endclass

// Generator class
class generator;
    // Mailbox and loop counter
    mailbox #(i2c_transaction) mbx_drv;
    mailbox #(i2c_transaction) mbx_scb;
    i2c_transaction trans;
    int transaction_count;

    // Constructor
    function new(mailbox #(i2c_transaction) mb_drv, mailbox #(i2c_transaction) mb_scb);
        mbx_drv = mb_drv;
        mbx_scb = mb_scb;
    endfunction

    // Main Task
    task main();
        repeat(transaction_count)
        begin
            trans = new();
            if(!trans.randomize())
                $fatal(1,"Randomisation Failed ...");
            mbx_drv.put(trans);
            mbx_scb.put(trans.copy());
            trans.display("Generator");
        end
    endtask
endclass

//Driver Class
class driver;
    // Virtual Interface and Mailbox
    mailbox #(i2c_transaction) mbx;
    virtual i2c_if vif; // Fixed XSim Bug: Removed .Tbstimulus
    
    // Constructor
    function new(virtual i2c_if vif,  mailbox #(i2c_transaction) mb); // Fixed XSim Bug: Removed .Tbstimulus
        mbx = mb;
        this.vif = vif;
    endfunction
    
    // Reset Task
    task reset();
        vif.cmd_valid = 0;
        vif.rw = 0;
        vif.addr = 0;
        vif.wdata = 0;
    endtask
    
    // Main Task
    i2c_transaction trans;
    task main();
    forever
    begin
        mbx.get(trans);
        $display("[DRIVER DEBUG 1] Got transaction, addr=0x%0h, busy=%b, rst_n=%b", trans.addr, vif.busy, vif.rst_n);
        @(posedge vif.clk); 
        $display("[DRIVER DEBUG 2] Passed posedge clk");
        wait(!vif.busy);
        $display("[DRIVER DEBUG 3] busy is now low, proceeding");
        vif.addr = trans.addr;
        vif.rw = trans.rw;
        vif.wdata = trans.wdata;
        @(posedge vif.clk)
            vif.cmd_valid = 1'b1;
        $display("[DRIVER DEBUG 4] cmd_valid asserted");
        wait(vif.busy);
        $display("[DRIVER DEBUG 5] busy went high");
        @(posedge vif.clk)
            vif.cmd_valid = 1'b0;
        wait(!vif.busy);
        $display("[DRIVER] Transaction completely driven to hardware.");
    end
endtask
    
endclass

// Monitor Class
class monitor;
    // Interface and mailbox
    virtual i2c_if vif;
    mailbox #(i2c_transaction) mbx;
    
    // Constructor
    function new(mailbox #(i2c_transaction) mb, virtual i2c_if vif);
        this.vif = vif;
        this.mbx = mb;
    endfunction
    
    // Main Task
    i2c_transaction trans;
    task main();
         $display("[Monitor] Started monitoring interface pins...");
         forever
         begin
            @(posedge vif.clk); // To avoid race condition as forever loop has 0 delay
            wait(vif.busy);
            wait(!vif.busy);
            trans = new();
            trans.rdata = vif.rdata;
            trans.ack_err = vif.ack_err;
            trans.timeout_err = vif.timeout_err;
            mbx.put(trans);
         end
    endtask
endclass

// Scoreboard Class
class scoreboard;
    // Mail Box
    mailbox #(i2c_transaction) mbx_exp, mbx_act;
    
    //Expected data and counter
    bit [7:0] EXPECTED_READ_DATA = 8'hA5; // Fixed XSim Bug: Changed from localparam
    int completed_count = 0; 
    
    // Constructor
    function new(mailbox #(i2c_transaction) mbx_exp, mailbox #(i2c_transaction) mbx_act);
        this.mbx_exp = mbx_exp;
        this.mbx_act = mbx_act;
    endfunction

    // Main Task
    i2c_transaction trans_expected, trans_actual;
    task main();
        forever
        begin
            mbx_act.get(trans_actual);
            mbx_exp.get(trans_expected);
            
            if (trans_actual.timeout_err) 
            begin
                $error("[SCOREBOARD] FAIL: Hardware Watchdog Timeout!");
            end 
            else if (trans_actual.ack_err) 
            begin
                $error("[SCOREBOARD] FAIL: NACK received for Address 0x%0h!", trans_expected.addr);
            end 
            else 
            begin
                if (trans_expected.rw == 1'b1) 
                begin
                    if (trans_actual.rdata !== EXPECTED_READ_DATA)
                    begin
                        $error("[SCOREBOARD] FAIL: READ data mismatch from Addr 0x%0h. Expected 0x%0h, Got 0x%0h",
                                trans_expected.addr, EXPECTED_READ_DATA, trans_actual.rdata);
                    end
                    else
                    begin
                        // Added the more_byte (wdata[0]) to the READ printout
                        $display("[SCOREBOARD] PASS: Successful READ from Addr 0x%0h. Data: 0x%0h | More Byte: %b", 
                                  trans_expected.addr, trans_actual.rdata, trans_expected.wdata[0]);
                    end
                end 
                else 
                begin
                    // Added the more_byte (wdata[0]) to the WRITE printout
                    $display("[SCOREBOARD] PASS: Successful WRITE to Addr 0x%0h. Payload: 0x%0h | More Byte: %b", 
                              trans_expected.addr, trans_expected.wdata[8:1], trans_expected.wdata[0]);
                end
            end
            completed_count++;
            $display("---------------------------------------------------");        
        end
    endtask
endclass

// Environment Class
class environment;
    // Instances of our classes
    generator  gen;
    driver     drv;
    monitor    mon;
    scoreboard scb;
    
    // Mailboxes
    mailbox #(i2c_transaction) mbx_gen_drv;
    mailbox #(i2c_transaction) mbx_gen_scb;
    mailbox #(i2c_transaction) mbx_mon_scb;
    
    // Virtual interface
    virtual i2c_if vif;
    
    // Constructor
    function new(virtual i2c_if vif);
        this.vif = vif;
        
        // Create the mailboxes
        mbx_gen_drv = new();
        mbx_gen_scb = new();
        mbx_mon_scb = new();
        
        // Instantiate the classes and connect them
        gen = new(mbx_gen_drv, mbx_gen_scb);
        drv = new(vif, mbx_gen_drv);          
        mon = new(mbx_mon_scb, vif);          
        scb = new(mbx_gen_scb, mbx_mon_scb);  
    endfunction
    
    // Run Task
    task run();
        // Tell generator to make 10 random transactions
        gen.transaction_count = 10; 
        
        // Reset the CPU signals
        drv.reset();
        
        // Run all classes in parallel
        fork
            gen.main();
            drv.main();
            mon.main();
            scb.main();
        join_any 
        
        // Give the simulation time to finish the last transaction
        wait (scb.completed_count == gen.transaction_count);
        $display("===================================================");
        $display("   TESTBENCH COMPLETE. FINISHING SIMULATION.       ");
        $display("===================================================");
        $finish;
    endtask
endclass
// Slave module

module mock_slave #(
    parameter [7:0] TX_DATA    = 8'hA5,
    parameter [6:0] NACK_ADDR  = 7'h7F
)(
    input  wire clk,
    input  wire rst_n,
    input  wire scl,
    inout  wire sda
);

    // 1. Oversample the I2C bus using the 50MHz clock
    reg [2:0] scl_sync, sda_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_sync <= 3'b111;
            sda_sync <= 3'b111;
        end else begin
            scl_sync <= {scl_sync[1:0], scl};
            sda_sync <= {sda_sync[1:0], sda};
        end
    end

    // 2. Edge Detectors
    wire scl_rise = (scl_sync[2:1] == 2'b01);
    wire scl_fall = (scl_sync[2:1] == 2'b10);
    wire sda_fall = (sda_sync[2:1] == 2'b10);
    wire sda_rise = (sda_sync[2:1] == 2'b01);

    // 3. I2C Condition Detectors
    wire start_cond = (scl_sync[1] == 1'b1) && sda_fall;
    wire stop_cond  = (scl_sync[1] == 1'b1) && sda_rise;

    localparam IDLE = 0, ADDR = 1, ACK_A = 2, DATA = 3, ACK_D = 4;
    reg [2:0] state;
    reg [3:0] bit_cnt;
    reg [7:0] shift_reg;
    reg       rw_bit;
    reg       sda_drive;

    assign sda = sda_drive ? 1'b0 : 1'bz;

    // 4. Synchronous State Machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            bit_cnt   <= 0;
            sda_drive <= 0;
        end else if (start_cond) begin
            state     <= ADDR;
            bit_cnt   <= 0;
            sda_drive <= 0;
        end else if (stop_cond) begin
            state     <= IDLE;
            sda_drive <= 0;
        end else begin
            case (state)
                IDLE: sda_drive <= 0;
                
                ADDR: begin
                    if (scl_rise) begin // Safely SAMPLE data when SCL goes HIGH
                        shift_reg <= {shift_reg[6:0], sda_sync[1]};
                        bit_cnt   <= bit_cnt + 1;
                    end else if (scl_fall && bit_cnt == 8) begin // DRIVE data when SCL goes LOW
                        rw_bit <= shift_reg[0];
                        state  <= ACK_A;
                        bit_cnt <= 0;
                        sda_drive <= (shift_reg[7:1] == NACK_ADDR) ? 1'b0 : 1'b1; 
                    end
                end
                
                ACK_A: begin
                    if (scl_fall) begin
                        if (shift_reg[7:1] == NACK_ADDR) begin
                            state <= IDLE;
                            sda_drive <= 0;
                        end else begin
                            state <= DATA;
                            shift_reg <= TX_DATA; 
                            if (rw_bit == 1'b1) sda_drive <= ~TX_DATA[7]; 
                            else sda_drive <= 0;
                        end
                    end
                end
                
                DATA: begin
                    if (scl_rise) begin
                        if (rw_bit == 1'b0) shift_reg <= {shift_reg[6:0], sda_sync[1]}; 
                        bit_cnt <= bit_cnt + 1;
                    end else if (scl_fall) begin
                        if (bit_cnt == 8) begin
                            state <= ACK_D;
                            bit_cnt <= 0;
                            sda_drive <= (rw_bit == 1'b0) ? 1'b1 : 1'b0; 
                        end else begin
                            if (rw_bit == 1'b1) begin
                                shift_reg <= {shift_reg[6:0], 1'b0};
                                sda_drive <= ~shift_reg[6]; 
                            end
                        end
                    end
                end
                
                ACK_D: begin
                    if (scl_rise && rw_bit == 1'b1) begin
                        if (sda_sync[1] == 1'b1) state <= IDLE; // Master sent NACK, abort
                    end else if (scl_fall && state == ACK_D) begin
                        state <= DATA;
                        shift_reg <= TX_DATA; 
                        if (rw_bit == 1'b1) sda_drive <= ~TX_DATA[7];
                        else sda_drive <= 0;
                    end
                end
            endcase
        end
    end
endmodule

// Top Level Simulation Module
module tb_top();
    logic clk;
    logic rst_n;

    // Clock Generation (50 MHz)
    initial begin
        clk = 0;
        forever #10 clk = ~clk; 
    end

    // Instantiate 
    i2c_if vif(clk, rst_n);
    
    i2c_master dut (
        .clk         (vif.clk),
        .rst_n       (vif.rst_n),
        .cmd_valid   (vif.cmd_valid),
        .addr        (vif.addr),
        .rw          (vif.rw),
        .wdata       (vif.wdata),
        .rdata       (vif.rdata),
        .busy        (vif.busy),
        .ack_err     (vif.ack_err),
        .timeout_err (vif.timeout_err),
        .scl         (vif.scl),
        .sda         (vif.sda)  
    );
    
    mock_slave #(.TX_DATA(8'hA5), .NACK_ADDR(7'h7F)) slave_bfm (
        .clk(vif.clk),     // <-- ADD THIS!
        .rst_n(vif.rst_n), // <-- ADD THIS!
        .scl(vif.scl),
        .sda(vif.sda)
    );
    
    environment env;

    initial begin
    rst_n = 0;
    #100;
    rst_n = 1;
    #100;
    
    $display("[DEBUG] Initial scl=%b sda=%b", vif.scl, vif.sda);
    
    env = new(vif);
    env.run();
end
endmodule