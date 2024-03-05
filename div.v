function [2:0] clz(input [7:0] x);
    integer i;
    begin
        for (i = 7; i >= 0; i = i - 1) begin
            if (x[i] == 1'b1)   begin
                return 3'h7-i;
            end
        end
    end
endfunction
// -5 %  3 = -2
//  5 % -3 =  2
// -5 % -3 = -2
// the sign of `r`(a % b) is the same as `a`(divisor)
module SRT4_div(
    input   reg         clock,
    input   reg         start,
    input   reg         is_signed,
    input   reg [7:0]   a,
    input   reg [7:0]   b,
    output  reg         ready,
    output  reg         error,
    output  reg [7:0]   q,
    output  reg [7:0]   r
);
    reg [16:0] PA = 17'd0;
    reg [7:0] B = 8'd0;
    wire [7:0] abs_a = (is_signed & a[7])? ~a + 1 : a,
        abs_b = (is_signed & b[7])? ~b + 1 : b;
    reg [7:0] q_pos_acc, q_neg_acc;

    reg [1:0] cnt = 2'd3;   // 4 iterations for 8-bit division
    reg [1:0] state = DivFree;
    reg [1:0] next_state = DivFree;
    localparam DivFree = 2'd0, DivByZero = 2'd1, DivOn = 2'd2, DivEnd = 2'd3;
    wire signed [2:0] qi;
    qselect qs(
        .b(B[7:4]),
        .p(PA[16:11]),
        .q(qi)
    );
    // state transition logic
    always @(*)   begin
        next_state = DivFree;
        case (state)
            DivFree:    begin
                if (start & (cnt == 2'd3))  begin
                    next_state = (b == 7'd0)? DivByZero : DivOn;
                end
                else    begin
                    next_state = DivFree;
                end
            end
            DivByZero:  begin
                next_state = DivFree;
            end
            DivOn:      begin
                next_state = (cnt == 2'd0)? DivEnd: DivOn;
            end
            DivEnd:     begin
                next_state = DivFree;
            end
        endcase
    end
    always @(posedge clock) begin
        state <= next_state;
    end

    // divide
    wire [16:0] B_1 = {1'b0, B, 8'b0};
    wire [16:0] B_2 = {B, 9'b0};
    wire [16:0] B_neg1 = ~B_1 + 1;
    wire [16:0] B_neg2 = B_neg1 << 1;
    always @(posedge clock) begin
        ready <= 1'b0;
        error <= 1'b0;
        case (state)
            DivFree:    begin   // preparation
                q_pos_acc <= 0;
                q_neg_acc <= 0;
                if (next_state == DivOn)    begin
                    B <= (abs_b << clz(abs_b));
                    PA <= ({9'd0, abs_a}) << clz(abs_b);
                end
            end
            DivByZero:  begin
                ready <= 1'b1;
                error <= 1'b1;
            end
            DivOn:      begin
                // PA <= (PA << 2) - ((qi * B) << 8);   // bug
                case (qi)
                    -2: PA <= (PA << 2) - B_neg2;
                    -1: PA <= (PA << 2) - B_neg1;
                    0:  PA <= (PA << 2);
                    1:  PA <= (PA << 2) - B_1;
                    2:  PA <= (PA << 2) - B_2;
                    default:;
                endcase
                // accumulate: acc += abs(qi) * exp(4, cnt)
                // exp(4, cnt) = exp(2, 2cnt)
                case (qi)
                    -2: q_neg_acc <= q_neg_acc + (8'd2 << ({cnt, 1'b0}));
                    -1: q_neg_acc <= q_neg_acc + (8'd1 << ({cnt, 1'b0}));
                    1:  q_pos_acc <= q_pos_acc + (8'd1 << ({cnt, 1'b0}));
                    2:  q_pos_acc <= q_pos_acc + (8'd2 << ({cnt, 1'b0}));
                    default:;
                endcase
                cnt <= cnt - 1;
            end
            DivEnd:     begin
                ready <= 1'b1;
                cnt <= 2'd3;
                // restore
                if (PA[16])  begin
                    PA <= (PA + {B, 8'b0}) >> clz(abs_b);
                    q_neg_acc <= q_neg_acc + 1;
                end
                else    begin
                    PA <= PA >> clz(abs_b);
                end
            end
        endcase
    end
    // final adjustments on signs
    reg [7:0] q_pos_temp, q_neg_temp, r_temp;
    always @*   begin
        q_pos_temp = q_pos_acc;
        q_neg_temp = q_neg_acc;
        r_temp = PA[15:8];
        if (ready)  begin
            if (is_signed)  begin
                case ({a[7], b[7]})
                    2'b00:;         // + vs +: no adjustments
                    2'b01:  begin   // + vs -: q -> -q, r -> r
                        q_neg_temp = q_pos_acc;
                        q_pos_temp = q_neg_acc;
                    end
                    2'b10:  begin   // - vs +: q -> -q, r -> -r
                        q_neg_temp = q_pos_acc;
                        q_pos_temp = q_neg_acc;
                        r_temp = ~r_temp + 1;
                    end
                    2'b11:  begin   // - vs -: q -> q, r -> -r
                        r_temp = ~r_temp + 1;
                    end
                endcase
            end
        end
    end

    assign q = q_pos_temp - q_neg_temp;
    assign r = r_temp;
endmodule