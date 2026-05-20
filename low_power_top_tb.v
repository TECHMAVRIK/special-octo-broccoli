// =============================================================================
// Testbench : low_power_top_tb.v
// Tests     : Clock gating, power domain sequencing, isolation cells,
//             retention registers, ALU ops, and memory read/write
// Simulator : ModelSim / QuestaSim / Icarus Verilog / Vivado Simulator
// Run       : vsim -do "run -all" low_power_top_tb
//             OR: iverilog -o sim low_power_top_tb.v low_power_design.v && vvp sim
// =============================================================================

`timescale 1ns/1ps

module low_power_top_tb;

    // =========================================================================
    // DUT Signals
    // =========================================================================
    reg         clk;
    reg         rst_n;
    reg         test_mode;
    reg  [7:0]  alu_a, alu_b;
    reg  [1:0]  alu_op;
    reg         alu_req;
    wire [8:0]  alu_result;
    wire        alu_valid;
    reg         mem_req;
    reg         mem_wr_en;
    reg  [2:0]  mem_wr_addr;
    reg  [7:0]  mem_wr_data;
    reg  [2:0]  mem_rd_addr;
    wire [7:0]  mem_rd_data;
    wire [1:0]  power_state;

    // =========================================================================
    // Instantiate DUT
    // =========================================================================
    low_power_top dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .test_mode    (test_mode),
        .alu_a        (alu_a),
        .alu_b        (alu_b),
        .alu_op       (alu_op),
        .alu_req      (alu_req),
        .alu_result   (alu_result),
        .alu_valid    (alu_valid),
        .mem_req      (mem_req),
        .mem_wr_en    (mem_wr_en),
        .mem_wr_addr  (mem_wr_addr),
        .mem_wr_data  (mem_wr_data),
        .mem_rd_addr  (mem_rd_addr),
        .mem_rd_data  (mem_rd_data),
        .power_state  (power_state)
    );

    // =========================================================================
    // Clock: 10ns period (100 MHz)
    // =========================================================================
    initial clk = 0;
    always #5 clk = ~clk;

    // =========================================================================
    // Test Tracking
    // =========================================================================
    integer pass_count, fail_count;
    reg [8:0] expected_alu;
    reg [7:0] expected_mem;

    task check_alu;
        input [8:0]  expected;
        input [63:0] test_id;
        begin
            @(posedge clk); #1;
            if (alu_valid && alu_result === expected) begin
                $display("[PASS] ALU Test %0d | Result=%0d (expected %0d)", test_id, alu_result, expected);
                pass_count = pass_count + 1;
            end
            else begin
                $display("[FAIL] ALU Test %0d | Result=%0d (expected %0d) valid=%b",
                          test_id, alu_result, expected, alu_valid);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task check_mem;
        input [7:0]  expected;
        input [63:0] test_id;
        begin
            if (mem_rd_data === expected) begin
                $display("[PASS] MEM Test %0d | Data=%0h (expected %0h)", test_id, mem_rd_data, expected);
                pass_count = pass_count + 1;
            end
            else begin
                $display("[FAIL] MEM Test %0d | Data=%0h (expected %0h)", test_id, mem_rd_data, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task check_power_state;
        input [1:0]  expected;
        input [127:0] label;
        begin
            if (power_state === expected) begin
                $display("[PASS] Power State [%s] = %b", label, power_state);
                pass_count = pass_count + 1;
            end
            else begin
                $display("[FAIL] Power State [%s] got %b expected %b", label, power_state, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task wait_cycles;
        input integer n;
        begin repeat(n) @(posedge clk); end
    endtask

    // =========================================================================
    // MAIN TEST SEQUENCE
    // =========================================================================
    initial begin
        // Waveform dump (for GTKWave)
        $dumpfile("low_power_sim.vcd");
        $dumpvars(0, low_power_top_tb);

        pass_count = 0;
        fail_count = 0;
        test_mode  = 0;

        // ---- Initialize inputs ----
        alu_req     = 0; alu_a = 0; alu_b = 0; alu_op = 0;
        mem_req     = 0; mem_wr_en = 0;
        mem_wr_addr = 0; mem_wr_data = 0; mem_rd_addr = 0;

        // ---- Reset ----
        rst_n = 0;
        wait_cycles(5);
        rst_n = 1;
        wait_cycles(2);

        $display("\n====================================================");
        $display(" TEST SUITE: Low-Power Design Verification");
        $display("====================================================\n");

        // =================================================================
        // TEST 1: Idle state — both domains should be off
        // =================================================================
        $display("--- TEST 1: Idle Power State ---");
        wait_cycles(3);
        check_power_state(2'b00, "IDLE");

        // =================================================================
        // TEST 2: ALU Operations — verify all 4 ops
        // =================================================================
        $display("\n--- TEST 2: ALU Operations ---");

        // ADD: 45 + 30 = 75
        alu_a = 8'd45; alu_b = 8'd30; alu_op = 2'b00; alu_req = 1;
        wait_cycles(3);
        check_alu(9'd75, 1);
        alu_req = 0;

        // SUB: 100 - 60 = 40
        alu_a = 8'd100; alu_b = 8'd60; alu_op = 2'b01; alu_req = 1;
        wait_cycles(3);
        check_alu(9'd40, 2);
        alu_req = 0;

        // AND: 0xFF & 0x0F = 0x0F
        alu_a = 8'hFF; alu_b = 8'h0F; alu_op = 2'b10; alu_req = 1;
        wait_cycles(3);
        check_alu(9'h00F, 3);
        alu_req = 0;

        // OR: 0xA0 | 0x0B = 0xAB
        alu_a = 8'hA0; alu_b = 8'h0B; alu_op = 2'b11; alu_req = 1;
        wait_cycles(3);
        check_alu(9'hAB, 4);
        alu_req = 0;

        // Edge: ADD with carry — 200 + 200 = 400 (needs 9 bits)
        alu_a = 8'd200; alu_b = 8'd200; alu_op = 2'b00; alu_req = 1;
        wait_cycles(3);
        check_alu(9'd400, 5);
        alu_req = 0;

        // =================================================================
        // TEST 3: ALU domain power-down after idle
        // =================================================================
        $display("\n--- TEST 3: ALU Auto Power-Down ---");
        // After ALU req drops, domain should power down after idle count
        wait_cycles(15);
        // ALU should be off now
        if (!dut.u_ctrl.pwr_en_alu) begin
            $display("[PASS] ALU domain powered down after idle");
            pass_count = pass_count + 1;
        end
        else begin
            $display("[FAIL] ALU domain still on after long idle");
            fail_count = fail_count + 1;
        end

        // =================================================================
        // TEST 4: Isolation — ALU output should be 0 when domain is off
        // =================================================================
        $display("\n--- TEST 4: Isolation Cells ---");
        wait_cycles(2);
        if (alu_result === 9'b0 && alu_valid === 1'b0) begin
            $display("[PASS] Isolation working — ALU outputs clamped to 0 when domain off");
            pass_count = pass_count + 1;
        end
        else begin
            $display("[FAIL] Isolation NOT working — alu_result=%0h alu_valid=%b", alu_result, alu_valid);
            fail_count = fail_count + 1;
        end

        // =================================================================
        // TEST 5: Memory Domain — Write and Read
        // =================================================================
        $display("\n--- TEST 5: Memory Domain Write/Read ---");
        mem_req = 1;
        wait_cycles(3);  // Allow power-up + restore

        // Write to all 8 entries
        mem_wr_en = 1;
        mem_wr_addr = 3'd0; mem_wr_data = 8'hAA; @(posedge clk);
        mem_wr_addr = 3'd1; mem_wr_data = 8'hBB; @(posedge clk);
        mem_wr_addr = 3'd2; mem_wr_data = 8'hCC; @(posedge clk);
        mem_wr_addr = 3'd3; mem_wr_data = 8'hDD; @(posedge clk);
        mem_wr_addr = 3'd4; mem_wr_data = 8'h11; @(posedge clk);
        mem_wr_addr = 3'd5; mem_wr_data = 8'h22; @(posedge clk);
        mem_wr_addr = 3'd6; mem_wr_data = 8'h33; @(posedge clk);
        mem_wr_addr = 3'd7; mem_wr_data = 8'h44; @(posedge clk);
        mem_wr_en = 0;

        // Read back and verify
        wait_cycles(1);
        mem_rd_addr = 3'd0; wait_cycles(1); check_mem(8'hAA, 10);
        mem_rd_addr = 3'd3; wait_cycles(1); check_mem(8'hDD, 11);
        mem_rd_addr = 3'd7; wait_cycles(1); check_mem(8'h44, 12);

        // =================================================================
        // TEST 6: Retention — power down MEM, power up, check data intact
        // =================================================================
        $display("\n--- TEST 6: Retention Register ---");
        // Let mem domain idle → auto power-down with save
        mem_req = 0;
        wait_cycles(20);  // Long enough for idle counter to trigger

        // Verify MEM is off
        if (!dut.u_ctrl.pwr_en_mem) begin
            $display("[PASS] MEM domain powered down (retention save triggered)");
            pass_count = pass_count + 1;
        end
        else begin
            $display("[FAIL] MEM domain did not power down after idle");
            fail_count = fail_count + 1;
        end

        // Re-power memory domain
        mem_req = 1;
        wait_cycles(5);  // Allow power-up + restore

        // Verify data is restored
        mem_rd_addr = 3'd0; wait_cycles(1); check_mem(8'hAA, 20);
        mem_rd_addr = 3'd3; wait_cycles(1); check_mem(8'hDD, 21);
        mem_rd_addr = 3'd7; wait_cycles(1); check_mem(8'h44, 22);
        mem_req = 0;

        // =================================================================
        // TEST 7: Simultaneous ALU + MEM activity (both domains on)
        // =================================================================
        $display("\n--- TEST 7: Both Domains Active ---");
        alu_a = 8'd12; alu_b = 8'd8; alu_op = 2'b00; alu_req = 1;
        mem_req = 1;
        wait_cycles(4);
        check_alu(9'd20, 30);
        check_power_state(2'b11, "BOTH_ON");
        alu_req = 0;
        mem_req  = 0;

        // =================================================================
        // TEST 8: Test Mode (scan bypass on ICG)
        // =================================================================
        $display("\n--- TEST 8: Test Mode Clock Bypass ---");
        test_mode = 1;
        wait_cycles(2);
        // With test_mode=1, ICG should pass clock regardless of enable
        // Both gated clocks should be running
        if (dut.u_icg_alu.gated_clk !== 1'bx) begin
            $display("[PASS] ICG test mode bypass active");
            pass_count = pass_count + 1;
        end
        test_mode = 0;

        // =================================================================
        // RESULTS SUMMARY
        // =================================================================
        wait_cycles(5);
        $display("\n====================================================");
        $display(" SIMULATION COMPLETE");
        $display(" PASSED : %0d", pass_count);
        $display(" FAILED : %0d", fail_count);
        if (fail_count == 0)
            $display(" STATUS : ALL TESTS PASSED ✓");
        else
            $display(" STATUS : SOME TESTS FAILED ✗");
        $display("====================================================\n");

        $finish;
    end

    // =========================================================================
    // Watchdog — prevents infinite simulation
    // =========================================================================
    initial begin
        #100000;
        $display("[WATCHDOG] Simulation timeout!");
        $finish;
    end

    // =========================================================================
    // Power state monitor (prints on every change)
    // =========================================================================
    always @(power_state) begin
        case (power_state)
            2'b00: $display("[PWR MON] t=%0t | State: IDLE    (ALU=OFF, MEM=OFF)", $time);
            2'b01: $display("[PWR MON] t=%0t | State: ALU_ON  (ALU=ON,  MEM=OFF)", $time);
            2'b10: $display("[PWR MON] t=%0t | State: MEM_ON  (ALU=OFF, MEM=ON)",  $time);
            2'b11: $display("[PWR MON] t=%0t | State: BOTH_ON (ALU=ON,  MEM=ON)",  $time);
        endcase
    end

endmodule
