`timescale 1ns / 1ps

module tb_i2c;

    // Inputs
    logic clk;
    logic reset;
    logic [7:0] din;
    logic wren;
    logic rden;
    logic [1:0] addr;
    logic sdin;

    // Outputs
    logic [7:0] dout;
    logic sclk;
    logic sdout;
    logic dir;

    parameter SCLK_PERIOD=2500;  //sclk period in ns (2.5 us = 2500 ns, 400 KHz)
    parameter CHARACTER_PERIOD = (SCLK_PERIOD*9);

`define START_CONTROL_BIT 0
`define STOP_CONTROL_BIT 1
`define WRITE_EN_CONTROL_BIT 2
`define WRITE_ACK_STATUS_BIT 3
`define READ_EN_CONTROL_BIT 4
`define READ_ACK_BIT 5
`define RESET_CONTROL_BIT 6

    // Instantiate the Unit Under Test (UUT)
    i2c uut (
        .clk(clk),
        .reset(reset),
        .din(din),
        .dout(dout),
        .wren(wren),
        .rden(rden),
        .addr(addr),
        .sclk(sclk),
        .sdout(sdout),
        .sdin(sdin),
        .dir(dir)
    );

    integer vectors_done_flag;

    //timeout process
    initial begin

        #(CHARACTER_PERIOD*20);   //wait 20 characters

        if (vectors_done_flag == 0) begin
            $display("%t: TIMEOUT, not all vectors processed.",$time);
            $display("The timeout is probably due to waiting for a status bit that never is cleared");
       end

    end

    initial begin
        clk = 0;
        #100   //reset delay
        forever #10 clk = ~clk;
    end
    integer errors;

    task checkSclk;
        input sclk_value;
        begin
        if (sclk_value == sclk) begin
        $display("%t: PASS, found expected sclk= %h",$time,sclk_value);
        end else begin
            $display("%t: FAIL, expected sclk= %h, actual= %h",$time,sclk_value,sclk);
            errors = errors + 1;
        end

        end
    endtask

    task checkSdout;
        input sdout_value;
        begin
            if (sdout_value == sdout) begin
                $display("%t: PASS, found expected sclk= %h",$time,sdout_value);
            end else begin
                $display("%t: FAIL, expected sdout= %h, actual= %h",$time,sdout_value,sdout);
                errors = errors + 1;
            end
        end
    endtask

    task checkDir;
        input dir_value;
        begin
            if (dir_value == dir) begin
            $display("%t: PASS, found expected dir= %h",$time,dir_value);
            end else begin
                $display("%t: FAIL, expected dir= %h, actual= %h",$time,dir_value,dir);
                errors = errors + 1;
            end
        end
    endtask

    task checkOutputs;
        input sclk_value;
        input sdout_value;
        input dir_value;
        begin
            checkSclk(sclk_value);
            checkSdout(sdout_value);
            checkDir(dir_value);
        end
    endtask

    task writeReg;
        input [7:0] regval;
        input [1:0] addrval;

        begin
            din = regval;
            addr = addrval;
            wren = 1;
            @(negedge clk);
            wren = 0;
            @(negedge clk);
        end
    endtask

    task checkReg;
        input [7:0] regval;
        input [1:0] addrval;

        begin
            addr = addrval;
            rden = 1;
            @(negedge clk);
            if (dout == regval) begin
                $display("%t: PASS, for register: %h, read expected value: %h",$time,addr,regval);
            end else begin
                $display("%t: FAIL, for register: %h, expected: %h, actual: %h",$time,addr,regval,dout);
                errors = errors + 1;
            end
            rden = 0;
            @(negedge clk);
        end
    endtask

    task readreg;
        input [1:0] addrval;

        begin
            addr = addrval;
            rden = 1;
            @(negedge clk);
        end
    endtask


    task simFail;
        begin
            while(1)begin
                @(negedge clk);
            end
        end
    endtask


    task checkStartCondition;
        begin
            $display("%t: Checking start operation",$time);

            // read the status register
            readreg(3'b11);
            if (dout[`START_CONTROL_BIT] != 1) begin
                $display("%t: FAIL, Start bit in status register not set, discontinuing vectors.",$time);
                simFail;
            end

            // start hold time is 600 ns, delay for 300 ns
            #300;
            @(negedge clk);
            // start bit should still be set
            if (dout[`START_CONTROL_BIT] != 1) begin
                $display("%t: FAIL, Start bit in status register not set, discontinuing vectors.",$time);
                simFail;
            end
            checkOutputs(1,0,0); //sclk, sdout, dir
            // now wait for start control bit to clear
            @(negedge clk);
            while (dout[`START_CONTROL_BIT] == 1) begin
                @(negedge clk);
            end
            @(negedge clk);
            @(negedge clk);
            @(negedge clk);
            // by this time, should have transitioned to write
            @(negedge clk);
        end
    endtask

    integer i;
    logic [7:0]shiftdata;

    task checkWrite;
        input [7:0] expectedval;
        input ackbit;
        begin
        $display("%t: Checking write operation",$time);
        readreg(3'b11); //read the status register
        if (dout[`WRITE_EN_CONTROL_BIT] != 1) begin
            $display("%t: FAIL, Write enable control bit in status register not set, discontinuing vectors.",$time);
            simFail;
        end
        checkSclk(0);  //sclk should be 0
        i = 0;
        while (i != 8) begin
            //wait for sclk = 1
            while (sclk != 1)begin
                @(negedge clk);
            end
            //wait for sclk = 0
            while (sclk != 0)begin
                @(negedge clk);
            end
            shiftdata[0] = sdout;
            i = i + 1;
            if (i != 8) shiftdata = {shiftdata[6:0],1'b0};//shift left
        end
        if (shiftdata == expectedval) begin
            $display("%t: PASS, got expected write value: %h",$time,expectedval);
        end else begin
            $display("%t: FAIL, for expected write value: %h, got: %h",$time,expectedval,shiftdata);
            errors = errors + 1;
        end
        sdin = ackbit;  //set the ack bit that we need to send back
        //wait for sclk = 1
        while (sclk != 1)begin
                @(negedge clk);
        end
        //direction should be 1 (read)
        checkDir(1);
        //wait for sclk = 0
        while (sclk != 0)begin
                @(negedge clk);
        end
        @(negedge clk);
        @(negedge clk);
        @(negedge clk);
        //read status register, ackbit should equal to this ackbit.
        readreg(3'b11); //read the status register
        if (dout[`WRITE_ACK_STATUS_BIT] == ackbit) begin
            $display("%t: PASS, got expected ack status value: %h",$time,ackbit);
        end else begin
            $display("%t: FAIL, for expected ack status value: %h, got %h",$time,ackbit,dout[`WRITE_ACK_STATUS_BIT]);
            errors = errors + 1;
        end
        //delay for bus release hold time, it is 600 ns, delay for 800 ns
        #800;
        @(negedge clk);
        //now ensure that the write enable status bit is cleared.
        if (dout[`WRITE_EN_CONTROL_BIT] != 0) begin
            $display("%t: FAIL, Write enable control bit in status register is not cleared, discontinuing vectors.",$time);
            simFail;
        end

        //finally, on exit, check SCLK=0, SDOUT=0, DIR=0 (write)
        //SDOUT must be driven low so that we can do a stop condition properly
        checkOutputs(0,0,0); //sclk, sdout, dir

        end
    endtask

    task doWrite;
        input[7:0] writevalue;
        input ackbit;

        begin
            writeReg(writevalue,1); //write to TX register
            checkReg(writevalue,1); //check it
            writeReg(8'b00000100,3); //set write control en bit
            checkWrite(writevalue,ackbit); //check the write
        end
    endtask

    task checkWriteAbort;
        input [7:0] expectedval;
        input ackbit;
        begin
            $display("%t: Checking write abort operation",$time);
            readreg(3'b11); //read the status register
            if (dout[`WRITE_EN_CONTROL_BIT] != 1) begin
                $display("%t: FAIL, Write enable control bit in status register not set, discontinuing vectors.",$time);
                simFail;
            end
            checkSclk(0);  //sclk should be 0
            i = 0;
            while (i != 4) begin	 //only write 4 bits
                //wait for sclk = 1
                while (sclk != 1)begin
                    @(negedge clk);
                end
                //wait for sclk = 0
                while (sclk != 0)begin
                    @(negedge clk);
                end
                shiftdata[0] = sdout;
                i = i + 1;
                if (i != 8) shiftdata = {shiftdata[6:0],1'b0};//shift left
            end
            @(negedge clk);

            //abort write
            writeReg(8'b01000000,3); //write to Status register
            @(negedge clk);
            @(negedge clk);
            @(negedge clk);
            //wait a few clocks
            checkOutputs(1,1,1); //sclk, sdout, dir
        end
    endtask

    task doWriteAbort;
        input[7:0] writevalue;
        input ackbit;

        begin
            writeReg(writevalue,1); //write to TX register
            checkReg(writevalue,1); //check it
            writeReg(8'b00000100,3); //set write control en bit
            checkWriteAbort(writevalue,ackbit); //check the write
        end
    endtask

    task doStopCondition;
        begin
        $display("%t: Checking stop condition operation",$time);

        writeReg(8'b00000010,3); //set stop bit
        if (dout[`STOP_CONTROL_BIT] != 1) begin
            $display("%t: FAIL, Stop bit (check 1) in status register is not set, discontinuing vectors.",$time);
            simFail;
        end

        //low clock time is 1300 ns, delay for half of this
        #600;
        @(negedge clk);
        //stop bit should still be set
        if (dout[`STOP_CONTROL_BIT] != 1) begin
            $display("%t: FAIL, Stop bit (check 2) in status register not set, discontinuing vectors.",$time);
            simFail;
        end
        //all of these should still be 0
        checkOutputs(0,0,0); //sclk, sdout, dir
        //now wait for SCLK to go high
        while (sclk == 0) begin
            @(negedge clk);
        end
        //only sclk should be high
        checkOutputs(1,0,0); //sclk, sdout, dir
        //hold time is 600 ns, delay for hal of this
        #300;
        @(negedge clk);
        //stop bit should still be set
        if (dout[`STOP_CONTROL_BIT] != 1) begin
            $display("%t: FAIL, Stop bit (check 3) in status register not set, discontinuing vectors.",$time);
            simFail;
        end
        //now wait for SDOUT to go high
        while (sdout == 0) begin
            @(negedge clk);
        end
        //sclk,sda should be high
        checkOutputs(1,1,0); //sclk, sdout, dir
        //min time between start and stop is 1300 ns, delay for half of this time
        #600;
        //stop bit should still be set
        if (dout[`STOP_CONTROL_BIT] != 1) begin
            $display("%t: FAIL, Stop bit (check 4) in status register not set, discontinuing vectors.",$time);
            simFail;
        end
        //now wait for stop bit to clear.
        while (dout[`STOP_CONTROL_BIT] == 1) begin
            @(negedge clk);
        end
        //these should all be high, direction is read (bus released).
        checkOutputs(1,1,1); //sclk, sdout, dir


        end
    endtask

    logic readAckBit;

    task doRead;
        input[7:0] readvalue;
        input ackbit;

        begin
            $display("%t: Beginning read operation check.",$time);
            shiftdata = readvalue;

            writeReg({2'b00,ackbit,5'b10000},3); //set read control en bit, and read ack bit
            readreg(3'b11); //read the status register
            if (dout[`READ_EN_CONTROL_BIT] != 1) begin
                $display("%t: FAIL, Read enable bit (check 1) in status register not set, discontinuing vectors.",$time);
                simFail;
            end
            #500;  //delay 1 us
            checkSclk(0); //should be zero
            checkDir(1); //should be read mode

            i = 0;
            while (i != 8) begin
            sdin = shiftdata[7]; //set the sdin value
            while (sclk == 0) begin
                @(negedge clk);
            end
            while (sclk == 1) begin
                @(negedge clk);
            end
            @(negedge clk);
            @(negedge clk); //a bit of hold time
            i = i + 1;
            if (i != 8) begin
                shiftdata[7:0] = {shiftdata[6:0],1'b0}; //shift right
            end
            end
            readreg(3'b11); //read the status register
            @(negedge clk);
            if (dout[`READ_EN_CONTROL_BIT] != 1) begin
                $display("%t: FAIL, Read enable bit (check 2) in status register not set, discontinuing vectors.",$time);
                simFail;
            end
            //next, need to read the ack bit
            while (sclk == 0) begin
                @(negedge clk);
            end
            while (sclk == 1) begin
                @(negedge clk);
            end

            readAckBit = sdout;
            //now check validity
            readreg(3'b10); //read the RX register
            if (dout == readvalue) begin
                $display("%t: PASS, got expected RX register value: %h",$time,readvalue);
            end else begin
                $display("%t: FAIL, expected RX register value: %h, actual: %h",$time,readvalue,dout);
            end

            if (readAckBit == ackbit) begin
                $display("%t: PASS, got expected read ack output value: %h",$time,ackbit);
            end else begin
                $display("%t: FAIL, for expected read ack value: %h, got %h",$time,ackbit,readAckBit);
                errors = errors + 1;
            end

            #600; //delay 600 ns for 300ns ack hold time
            checkOutputs(0,0,0); //all of these should be low
            //readen bit should be cleared
            readreg(3'b11); //read the status register
            @(negedge clk);
            @(negedge clk);
            if (dout[`READ_EN_CONTROL_BIT] != 0) begin
                $display("%t: FAIL, Read enable bit (check 3) in status register not cleared, discontinuing vectors.",$time);
                simFail;
            end
        end
    endtask


    task doReadAbort;
        input[7:0] readvalue;
        input ackbit;

        begin
            $display("%t: Beginning read operation check.",$time);
            shiftdata = readvalue;

            writeReg({2'b00,ackbit,5'b10000},3); //set read control en bit, and read ack bit
            readreg(3'b11); //read the status register
            if (dout[`READ_EN_CONTROL_BIT] != 1) begin
                $display("%t: FAIL, Read enable bit (check 1) in status register not set, discontinuing vectors.",$time);
                simFail;
            end
            #500;  //delay 1 us
            checkSclk(0); //should be zero
            checkDir(1); //should be read mode

            i = 0;
            while (i != 4) begin
                sdin = shiftdata[7]; //set the sdin value
                while (sclk == 0) begin
                    @(negedge clk);
                end
                while (sclk == 1) begin
                    @(negedge clk);
                end
                @(negedge clk);
                @(negedge clk); //a bit of hold time
                i = i + 1;
                if (i != 8) begin
                    shiftdata[7:0] = {shiftdata[6:0],1'b0}; //shift right
                end
            end

            //abort read
            writeReg(8'b01000000,3); //write to Status register
            @(negedge clk);
            @(negedge clk);
            @(negedge clk);
            //wait a few clocks
            checkOutputs(1,1,1); //sclk, sdout, dir
        end
    endtask

    integer sclk_count;
    integer timeMeasured;

    initial begin
        // Initialize Inputs
        #1
        vectors_done_flag = 0;
        clk = 0;
        reset = 1;
        din = 0;
        wren = 0;
        rden = 0;
        addr = 0;
        sdin = 0;
        errors = 0;
        sclk_count = 0;
        timeMeasured = 0;

        // Wait 100 ns for global reset to finish
        #100;

        // Add stimulus here
        @(negedge clk);
        reset = 0;
        @(negedge clk);
        @(negedge clk);
        @(negedge clk);
        checkOutputs(1,1,1); //sclk, sdout, dir
        writeReg(62,0); //write value of 62 to period register.
        checkReg(62,0); //check it
        writeReg(8'hA5,1); //write to TX register
        checkReg(8'hA5,1); //check it
        checkReg(0,2); //receive register
        checkReg(0,2); //status register
        //ready to go. lets set both the start and write enable bits in the control register
        //this will kick off both the start and write conditions
        writeReg(8'b00000101,3);
        checkStartCondition;
        checkWrite(8'hA5,0); //value to check, ack bit to send back

        doWrite(8'h5A,1); //nak value this time.
        doWrite(8'hC3,0); //ack value this time.
        doWriteAbort(8'h5A,0); //do a write abort

        //lets do another
        writeReg(8'h27,1); //write to TX register
        checkReg(8'h27,1); //check it
        writeReg(8'b00000101,3);
        checkStartCondition;
        checkWrite(8'h27,0); //value to check, ack bit to send back

        if (errors == 0) begin
            $display("%t: Deliverable #1, Simulation PASSED, no errors.",$time);
        end else begin
            $display("%t: Deliverable #1, Simulation FAILED with %d errors.",$time,errors);
        end

        doStopCondition();

        //lets do another
        writeReg(8'h27,1); //write to TX register
        checkReg(8'h27,1); //check it
        writeReg(8'b00000101,3);
        checkStartCondition;
        checkWrite(8'h27,0); //value to check, ack bit to send back
        doWriteAbort(8'h5A,0); //do a write abort

        //should now be able to do a start condition
        //lets do another
        writeReg(8'h3C,1); //write to TX register
        checkReg(8'h3C,1); //check it
        writeReg(8'b00000101,3);
        checkStartCondition;
        checkWrite(8'h3C,0); //value to check, ack bit to send back
        doWrite(8'hAF,0); //ack value this time.

        doStopCondition();

        writeReg(8'h72,1); //write to TX register
        checkReg(8'h72,1); //check it
        //this will kick off both the start and write conditions
        writeReg(8'b00000101,3);
        checkStartCondition;
        checkWrite(8'h72,0); //value to check, ack bit to send back
        //do a read now.
        doRead(8'h38,0);
        doRead(8'hDE,0);
        doRead(8'hA5,1);
        doStopCondition();

        writeReg(8'hE3,1); //write to TX register
        checkReg(8'hE3,1); //check it
        //this will kick off both the start and write conditions
        writeReg(8'b00000101,3);
        checkStartCondition;
        checkWrite(8'hE3,0); //value to check, ack bit to send back
        //do a read now.
        doRead(8'h38,0);
        doReadAbort(8'h38,0);

        //after abort, should be able to start again

        writeReg(8'h1D,1); //write to TX register
        checkReg(8'h1D,1); //check it
        //this will kick off both the start and write conditions
        writeReg(8'b00000101,3);
        checkStartCondition;
        checkWrite(8'h1D,0); //value to check, ack bit to send back
        //do a read now.
        doRead(8'h68,0);
        doRead(8'hBA,0);
        doStopCondition();

        vectors_done_flag = 1;
        if (errors == 0) begin
            $display("%t: Deliverable #2, Simulation PASSED, no errors.",$time);
       end else begin
            $display("%t: Deliverable #2, Simulation FAILED with %d errors.",$time,errors);
        end
    end

    time t1;
    integer delta;

    always @(sclk) begin
        if (sclk) sclk_count = sclk_count + 1;
        if (sclk_count >= 4 ) begin
            if (sclk) t1 = $time;
            if (sclk == 0 && ($time > t1)) begin
                delta = $time - t1;
                //for 400 Khz clock, time whould be
                if (timeMeasured == 0) begin
                    timeMeasured = 1;
                    if ((delta < 1280) && (delta > 1220)) begin
                        $display("%t: PASS, SCLK is expected pulse width (~1250 ns)",$time);
                    end else begin
                            $display("%t: FAIL, SCLK is not expected pulse width (~1250 ns), got: %d",$time,delta);
                            errors = errors + 1;
                    end
                end
            end
        end
    end
endmodule
