`timescale 1ns/1ps

// INTEGRATED CLOCK GATE (ICG) CELL
// The latch eliminates glitches on gated_clk

module icg_cell (
    input  wire clk,        // Free-running clock
    input  wire enable,     // Clock enable (from controller)
    input  wire test_mode,  // Scan/test bypass
    output wire gated_clk   // Gated clock to domain
);
    reg  latch_en;

    // Latch samples enable on LOW phase of clock (negative-level latch)
    // This prevents glitches by only passing stable enable values
    always @(*) begin
        if (!clk)
            latch_en = enable | test_mode;
    end

    assign gated_clk = clk & latch_en;

endmodule


// =============================================================================
// ISOLATION CELL
// Holds output at known safe value (0) when domain is powered off
// Prevents X-propagation into always-on domains
// =============================================================================
module iso_cell (
    input  wire data_in,    // Signal from powered-off domain
    input  wire iso_en,     // Isolation enable (1 = domain OFF)
    output wire data_out    // Safe output to always-on domain
);
    // When iso_en=1 (domain off): output clamped to 0
    // When iso_en=0 (domain on):  output passes through
    assign data_out = data_in & ~iso_en;

endmodule


// =============================================================================
// RETENTION REGISTER
// Retains state during power-down using a shadow latch
// On power-up, saved state is restored before normal operation
// =============================================================================
module retention_reg #(parameter WIDTH = 8) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             save,       // Capture to shadow latch (before power-down)
    input  wire             restore,    // Restore from shadow (after power-up)
    input  wire [WIDTH-1:0] d,
    output reg  [WIDTH-1:0] q
);
    reg [WIDTH-1:0] shadow;  // Non-volatile shadow (balloon register)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q      <= {WIDTH{1'b0}};
            shadow <= {WIDTH{1'b0}};
        end
        else if (save) begin
            shadow <= q;       // Save current state before power-down
        end
        else if (restore) begin
            q <= shadow;       // Restore saved state after power-up
        end
        else begin
            q <= d;            // Normal register operation
        end
    end

endmodule

// ALU DOMAIN (PD_ALU)
// Simple 8-bit ALU: add, subtract, AND, OR
// Powered down when idle via clock gating + power enable

module alu_domain (
    input  wire        gated_clk,   // Gated clock from ICG
    input  wire        rst_n,
    input  wire [7:0]  operand_a,
    input  wire [7:0]  operand_b,
    input  wire [1:0]  op_sel,      // 00=ADD, 01=SUB, 10=AND, 11=OR
    input  wire        valid_in,
    output reg  [8:0]  result,      // 9-bit to capture carry/borrow
    output reg         valid_out
);
    always @(posedge gated_clk or negedge rst_n) begin
        if (!rst_n) begin
            result    <= 9'b0;
            valid_out <= 1'b0;
        end
        else begin
            valid_out <= valid_in;
            if (valid_in) begin
                case (op_sel)
                    2'b00: result <= {1'b0, operand_a} + {1'b0, operand_b}; // ADD
                    2'b01: result <= {1'b0, operand_a} - {1'b0, operand_b}; // SUB
                    2'b10: result <= {1'b0, operand_a  & operand_b};         // AND
                    2'b11: result <= {1'b0, operand_a  | operand_b};         // OR
                endcase
            end
        end
    end

endmodule



// MEMORY DOMAIN (PD_MEM)
// 8-entry x 8-bit register file with retention support
// Powered down between bursts; state retained in shadow latches

module mem_domain (
    input  wire        gated_clk,
    input  wire        rst_n,
    input  wire        wr_en,
    input  wire [2:0]  wr_addr,
    input  wire [7:0]  wr_data,
    input  wire [2:0]  rd_addr,
    output reg  [7:0]  rd_data,
    // Retention control
    input  wire        save,
    input  wire        restore
);
    reg [7:0] regfile [0:7];
    reg [7:0] shadow  [0:7];   // Shadow copies for retention
    integer i;

    always @(posedge gated_clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 8; i = i+1) begin
                regfile[i] <= 8'b0;
                shadow[i]  <= 8'b0;
            end
            rd_data <= 8'b0;
        end
        else if (save) begin
            // Capture all registers to shadow before power-down
            for (i = 0; i < 8; i = i+1)
                shadow[i] <= regfile[i];
        end
        else if (restore) begin
            // Restore from shadow after power-up
            for (i = 0; i < 8; i = i+1)
                regfile[i] <= shadow[i];
        end
        else begin
            if (wr_en)
                regfile[wr_addr] <= wr_data;
            rd_data <= regfile[rd_addr];
        end
    end

endmodule


// CONTROL DOMAIN (PD_CTRL) — ALWAYS ON
// Manages power sequencing, clock enables, isolation, and retention signals
// This domain never powers down

module ctrl_domain (
    input  wire        clk,         // Always-on clock
    input  wire        rst_n,
    // Activity hints from top-level
    input  wire        alu_req,     // ALU operation requested
    input  wire        mem_req,     // Memory access requested
    // Power/clock control outputs
    output reg         alu_clk_en,  // ICG enable for ALU domain
    output reg         mem_clk_en,  // ICG enable for MEM domain
    output reg         pwr_en_alu,  // Power enable for ALU domain
    output reg         pwr_en_mem,  // Power enable for MEM domain
    output reg         iso_en_alu,  // Isolation for ALU outputs
    output reg         iso_en_mem,  // Isolation for MEM outputs
    output reg         save_mem,    // Trigger retention save
    output reg         restore_mem, // Trigger retention restore
    // Power state indicators
    output reg [1:0]   power_state  // 00=idle, 01=alu_on, 10=mem_on, 11=both_on
);

    // Power-up sequencing: ISO must be released AFTER domain is powered and clocked
    // Power-down sequencing: ISO must be asserted BEFORE power is removed

    localparam IDLE     = 2'b00;
    localparam ALU_ON   = 2'b01;
    localparam MEM_ON   = 2'b10;
    localparam BOTH_ON  = 2'b11;

    reg [3:0] idle_cnt_alu, idle_cnt_mem;  // Idle counters for auto power-down

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alu_clk_en  <= 1'b0;
            mem_clk_en  <= 1'b0;
            pwr_en_alu  <= 1'b0;
            pwr_en_mem  <= 1'b0;
            iso_en_alu  <= 1'b1;   // Isolation ON at reset (domain off)
            iso_en_mem  <= 1'b1;
            save_mem    <= 1'b0;
            restore_mem <= 1'b0;
            power_state <= IDLE;
            idle_cnt_alu <= 4'b0;
            idle_cnt_mem <= 4'b0;
        end
        else begin
            save_mem    <= 1'b0;   // Pulse signals — clear each cycle
            restore_mem <= 1'b0;

            // ---- ALU Power Management ----
            if (alu_req) begin
                // Power-up sequence: Power → Clock → Release Isolation
                pwr_en_alu  <= 1'b1;
                alu_clk_en  <= 1'b1;
                iso_en_alu  <= 1'b0;   // Release isolation
                idle_cnt_alu <= 4'b0;
            end
            else if (pwr_en_alu) begin
                // Auto power-down after idle
                idle_cnt_alu <= idle_cnt_alu + 1;
                if (idle_cnt_alu == 4'd8) begin
                    // Power-down sequence: Assert Isolation → Stop Clock → Power Off
                    iso_en_alu  <= 1'b1;
                    alu_clk_en  <= 1'b0;
                    pwr_en_alu  <= 1'b0;
                end
            end

            // ---- MEM Power Management ----
            if (mem_req) begin
                if (!pwr_en_mem) begin
                    // Coming from power-off: restore retained state
                    pwr_en_mem  <= 1'b1;
                    mem_clk_en  <= 1'b1;
                    restore_mem <= 1'b1;
                    iso_en_mem  <= 1'b0;
                end
                idle_cnt_mem <= 4'b0;
            end
            else if (pwr_en_mem) begin
                idle_cnt_mem <= idle_cnt_mem + 1;
                if (idle_cnt_mem == 4'd12) begin
                    // Save state before powering down
                    save_mem    <= 1'b1;
                    iso_en_mem  <= 1'b1;
                    mem_clk_en  <= 1'b0;
                    pwr_en_mem  <= 1'b0;
                end
            end

            // Update power state indicator
            power_state <= {pwr_en_mem, pwr_en_alu};
        end
    end

endmodule

// TOP MODULE
// Integrates all domains, ICG cells, and isolation cells

module low_power_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        test_mode,

    // ALU interface
    input  wire [7:0]  alu_a,
    input  wire [7:0]  alu_b,
    input  wire [1:0]  alu_op,
    input  wire        alu_req,
    output wire [8:0]  alu_result,
    output wire        alu_valid,

    // Memory interface
    input  wire        mem_req,
    input  wire        mem_wr_en,
    input  wire [2:0]  mem_wr_addr,
    input  wire [7:0]  mem_wr_data,
    input  wire [2:0]  mem_rd_addr,
    output wire [7:0]  mem_rd_data,

    // Status
    output wire [1:0]  power_state
);

    // Internal wires
    wire        alu_clk_en, mem_clk_en;
    wire        pwr_en_alu, pwr_en_mem;
    wire        iso_en_alu, iso_en_mem;
    wire        save_mem,   restore_mem;
    wire        gated_clk_alu, gated_clk_mem;

    // Raw (pre-isolation) outputs from domains
    wire [8:0]  alu_result_raw;
    wire        alu_valid_raw;
    wire [7:0]  mem_rd_data_raw;

    // ---- Clock Gate Cells ----
    icg_cell u_icg_alu (
        .clk        (clk),
        .enable     (alu_clk_en),
        .test_mode  (test_mode),
        .gated_clk  (gated_clk_alu)
    );

    icg_cell u_icg_mem (
        .clk        (clk),
        .enable     (mem_clk_en),
        .test_mode  (test_mode),
        .gated_clk  (gated_clk_mem)
    );


    ctrl_domain u_ctrl (
        .clk         (clk),
        .rst_n       (rst_n),
        .alu_req     (alu_req),
        .mem_req     (mem_req),
        .alu_clk_en  (alu_clk_en),
        .mem_clk_en  (mem_clk_en),
        .pwr_en_alu  (pwr_en_alu),
        .pwr_en_mem  (pwr_en_mem),
        .iso_en_alu  (iso_en_alu),
        .iso_en_mem  (iso_en_mem),
        .save_mem    (save_mem),
        .restore_mem (restore_mem),
        .power_state (power_state)
    );
    alu_domain u_alu (
        .gated_clk  (gated_clk_alu),
        .rst_n      (rst_n),
        .operand_a  (alu_a),
        .operand_b  (alu_b),
        .op_sel     (alu_op),
        .valid_in   (alu_req),
        .result     (alu_result_raw),
        .valid_out  (alu_valid_raw)
    );
    mem_domain u_mem (
        .gated_clk  (gated_clk_mem),
        .rst_n      (rst_n),
        .wr_en      (mem_wr_en),
        .wr_addr    (mem_wr_addr),
        .wr_data    (mem_wr_data),
        .rd_addr    (mem_rd_addr),
        .rd_data    (mem_rd_data_raw),
        .save       (save_mem),
        .restore    (restore_mem)
    );
    genvar i;
    generate
        for (i = 0; i < 9; i = i+1) begin : iso_alu_result
            iso_cell u_iso (
                .data_in  (alu_result_raw[i]),
                .iso_en   (iso_en_alu),
                .data_out (alu_result[i])
            );
        end
    endgenerate

    iso_cell u_iso_alu_valid (
        .data_in  (alu_valid_raw),
        .iso_en   (iso_en_alu),
        .data_out (alu_valid)
    );
    generate
        for (i = 0; i < 8; i = i+1) begin : iso_mem_rd
            iso_cell u_iso (
                .data_in  (mem_rd_data_raw[i]),
                .iso_en   (iso_en_mem),
                .data_out (mem_rd_data[i])
            );
        end
    endgenerate

endmodule
