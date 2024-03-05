module srt_tb(input clock);
    reg [7:0] a = 149, b = 5, q, r;
    reg ready, start = 0;
    SRT4_div d(
        .a(a),
        .b(b),
        .q(q),
        .r(r),
        .clock(clock),
        .start(start),
        .is_signed(1'b0),
        .ready(ready)
    );
    always @(*) begin
        if (ready)
            $display("q = %d\nr = %d", q, r);
    end
endmodule