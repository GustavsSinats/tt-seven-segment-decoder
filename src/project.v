`default_nettype none

// Tiny Tapeout digital-development wrapper.
//
// ui_in[0] = external/test sigma-delta bitstream
// uo_out   = seven-segment signals
// uio[2:0] = digit enables
// uio[3]   = raw bitstream
//
// This wrapper is for testing and hardening the DIGITAL block.
// The final analog project needs a mixed-signal top-level layout.

module tt_um_gustavssinats_seven_segment_decoder (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,

    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,

    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    wire [7:0] segments;
    wire [2:0] digit_en;

    sigma_delta_display_core #(
        // 0: active-high segments, e.g. common-cathode logic
        // 1: active-low segments, e.g. common-anode logic
        .SEG_ACTIVE_LOW(1'b0),

        // Set according to your external digit-driver circuit.
        .DIGIT_ACTIVE_LOW(1'b0),

        // At clk = 1 MHz:
        // digit changes every 1024 clocks;
        // complete display refresh is about 325 Hz.
        .SCAN_DIV(1024)
    ) core (
        .clk       (clk),
        .rst_n     (rst_n),
        .enable    (ena),
        .bitstream (ui_in[0]),
        .segments  (segments),
        .digit_en  (digit_en)
    );

    assign uo_out = segments;

    assign uio_out = {
        4'b0000,
        (ena & ui_in[0]),
        digit_en
    };

    // uio[3:0] outputs, uio[7:4] inputs.
    assign uio_oe = 8'b00001111;

    wire _unused = &{ui_in[7:1], uio_in, 1'b0};

endmodule


module sigma_delta_display_core #(
    parameter SEG_ACTIVE_LOW   = 1'b0,
    parameter DIGIT_ACTIVE_LOW = 1'b0,
    parameter integer SCAN_DIV = 1024
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       enable,
    input  wire       bitstream,

    output wire [7:0] segments,
    output wire [2:0] digit_en
);

    // SCAN_DIV must be between 1 and 65536.
    localparam [15:0] SCAN_LAST = 16'(SCAN_DIV - 1);

    // 4096 samples per output result.
    reg [11:0] sample_count;

    // 13 bits are needed to represent 4096 ones.
    reg [12:0] ones_count;
    wire [12:0] ones_next;

    // Latched output: 0 through 4095.
    reg [11:0] result;

    assign ones_next =
        ones_count + {{12{1'b0}}, bitstream};

    // Accumulate the bitstream and update the result
    // once per 4096 enabled clock cycles.
    always @(posedge clk) begin
        if (!rst_n) begin
            sample_count <= 12'd0;
            ones_count   <= 13'd0;
            result       <= 12'd0;
        end else if (enable) begin
            if (sample_count == 12'd4095) begin
                sample_count <= 12'd0;
                ones_count   <= 13'd0;

                // Include the current/final input sample.
                // Saturate 4096 to the largest 12-bit code.
                if (ones_next >= 13'd4096)
                    result <= 12'hFFF;
                else
                    result <= ones_next[11:0];
            end else begin
                sample_count <= sample_count + 12'd1;
                ones_count   <= ones_next;
            end
        end
    end

    // Display scanning.
    reg [15:0] scan_count;
    reg [1:0]  digit_index;

    always @(posedge clk) begin
        if (!rst_n) begin
            scan_count  <= 16'd0;
            digit_index <= 2'd0;
        end else if (enable) begin
            if (scan_count == SCAN_LAST) begin
                scan_count <= 16'd0;

                if (digit_index == 2'd2)
                    digit_index <= 2'd0;
                else
                    digit_index <= digit_index + 2'd1;
            end else begin
                scan_count <= scan_count + 16'd1;
            end
        end
    end

    reg [3:0] hex_digit;
    reg [2:0] digit_on;

    // Digit 0 = rightmost / least-significant digit.
    always @(*) begin
        hex_digit = 4'd0;
        digit_on  = 3'b000;

        case (digit_index)
            2'd0: begin
                hex_digit = result[3:0];
                digit_on  = 3'b001;
            end

            2'd1: begin
                hex_digit = result[7:4];
                digit_on  = 3'b010;
            end

            2'd2: begin
                hex_digit = result[11:8];
                digit_on  = 3'b100;
            end

            default: begin
                hex_digit = 4'd0;
                digit_on  = 3'b000;
            end
        endcase
    end

    // Internal segment order:
    // seg_on[0] = a
    // seg_on[1] = b
    // seg_on[2] = c
    // seg_on[3] = d
    // seg_on[4] = e
    // seg_on[5] = f
    // seg_on[6] = g
    // seg_on[7] = decimal point
    //
    // Patterns display 0...9, A, b, C, d, E, F.
    reg [7:0] seg_on;

    always @(*) begin
        case (hex_digit)
            4'h0: seg_on = 8'h3F;
            4'h1: seg_on = 8'h06;
            4'h2: seg_on = 8'h5B;
            4'h3: seg_on = 8'h4F;
            4'h4: seg_on = 8'h66;
            4'h5: seg_on = 8'h6D;
            4'h6: seg_on = 8'h7D;
            4'h7: seg_on = 8'h07;
            4'h8: seg_on = 8'h7F;
            4'h9: seg_on = 8'h6F;
            4'hA: seg_on = 8'h77;
            4'hB: seg_on = 8'h7C;
            4'hC: seg_on = 8'h39;
            4'hD: seg_on = 8'h5E;
            4'hE: seg_on = 8'h79;
            4'hF: seg_on = 8'h71;
            default: seg_on = 8'h00;
        endcase
    end

    wire display_on;
    wire [7:0] enabled_segments;
    wire [2:0] enabled_digits;

    assign display_on = enable & rst_n;

    assign enabled_segments =
        display_on ? seg_on : 8'h00;

    assign enabled_digits =
        display_on ? digit_on : 3'b000;

    assign segments =
        SEG_ACTIVE_LOW ? ~enabled_segments : enabled_segments;

    assign digit_en =
        DIGIT_ACTIVE_LOW ? ~enabled_digits : enabled_digits;

endmodule

`default_nettype wire
