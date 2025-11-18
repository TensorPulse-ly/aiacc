// ---------------------------------------------------------------------
//
// ------------------------------------------------------------------------------
// 
// Copyright 2005 - 2022 Synopsys, INC.
// 
// This Synopsys IP and all associated documentation are proprietary to
// Synopsys, Inc. and may only be used pursuant to the terms and conditions of a
// written license agreement with Synopsys, Inc. All other use, reproduction,
// modification, or distribution of the Synopsys IP or the associated
// documentation is strictly prohibited.
// Inclusivity & Diversity - Visit SolvNetPlus to read the "Synopsys Statement on
//            Inclusivity and Diversity" (Refer to article 000036315 at
//                        https://solvnetplus.synopsys.com)
// 
// Component Name   : DW_axi_gs
// Component Version: 2.05a
// Release Type     : GA
// Build ID         : 19.15.20.7
// ------------------------------------------------------------------------------

// 
// Release version :  2.05a
// File Version     :        $Revision: #15 $ 
// Revision: $Id: //dwh/DW_ocb/DW_axi_gs/axi_dev_br/src/DW_axi_gs_exclusive.v#15 $ 
//
// -------------------------------------------------------------------------
//
// AUTHOR:    James Feagans      2/10/2005
//
// VERSION:   DW_axi_gs_exclusive Verilog Synthesis Model
//
//
//-----------------------------------------------------------------------------
//-----------------------------------------------------------------------------
//
// ABSTRACT:  Exclusive Access Monitor
//
// Maintains exclusive access table of addresses and IDs.
// Asserts output port exokay upon successful exclusive read or write access.
//
// Upon an exclusive read access:
//
//   - if the {id} matches the {id} field of an existing table entry, replace
//     that table entry with the new {id, addr} pair and report exokay = 1.
//
//   - else if the table is full, do not alter the table and report exokay = 0.
//
//   - else, add the entry to the table and report exokay = 1.
//
// Upon an exclusive write access:
//
//   - if the address matches an existing table entry, delete
//     that table entry and report exokay = 1.
//
//   - else, do not alter the table and report exokay = 0.
//
// Upon a normal read access:
//
//   - do not alter the table and report exokay = 0.
//
// Upon a normal write access:
//
//   - if the address matches an existing table entry, delete
//     that table entry and report exokay = 0.
//
//   - else, do not alter the table and report exokay = 0.
//
//-----------------------------------------------------------------------------

`include "DW_axi_gs_all_includes.vh"

module DW_axi_gs_exclusive(

  // Inputs
  clk,       // Clock, positive edge
  clk_en,    // Clock enable for quasi-synchronous clocking mode
  reset_n,   // Reset, active low
  read,      // Initiate read transaction
  write,     // Initiate write transaction
  exclusive, // Identify transaction as exclusive access
  payload,   // Group of address channel signals

  // Outputs
  exokay,    // Indicates exclusive access succeeded
  exfail     // Indicates exclusive access failed
);


// ----------------------------------------------------------------------------
// PARAMETERS
// ----------------------------------------------------------------------------

// these parameters are defined by the user upon instantiation
parameter NUM_ENTRIES    = `NUM_ENTRIES_INT; //`GS_AXI_EX_ACCESS; //4;  // RANGE 1 to 32
parameter ID_WIDTH       = `GS_ID; //8;  // RANGE 1 to 16
// The exclusive access monitor ignores the low-order bits of the address
// per the AXI Protocol v1.0 Specification. Monitoring 128 bytes for any given
// access corresponds to dropping the 7 low-order bits. This would make the
// address input of the exclusive access monitor 25 bits if the AXI address bus
// is 32 bits wide.
//parameter PYLD_W          = 0; // Width of payload bus
parameter PYLD_W =
 (`GS_AW+`GS_ID+2+`GS_BW+3+2+2) - 2;


// Exclusive access address granularity of 128 bytes (2^7).
parameter EX_ADDR_PRECISION = 7;
parameter ADDR_COMP_WIDTH = `GS_AW - EX_ADDR_PRECISION;

// these parameters are automatically derived from the parameters above
//parameter ex_encode_width   = ((NUM_ENTRIES>16)?((NUM_ENTRIES>64)?
//  ((NUM_ENTRIES>128)?8:7):((NUM_ENTRIES>32)?6:5)):((NUM_ENTRIES>4)?
//  ((NUM_ENTRIES>8)?4:3):((NUM_ENTRIES>2)?2:1)));
parameter EX_ID_TBL_WIDTH   = NUM_ENTRIES*ID_WIDTH;
parameter EX_ADDR_TBL_WIDTH = NUM_ENTRIES*ADDR_COMP_WIDTH;

parameter ADDR_COMP_LSB = EX_ADDR_PRECISION; //`GS_AW-ADDR_COMP_WIDTH;

// Maximum transaction size in bytes
parameter MAX_TX_SZ_BYTES = (`GS_DW/8 * `GS_MAX_LEN);


// ----------------------------------------------------------------------------
// PORTS
// ----------------------------------------------------------------------------

input  clk;
input  clk_en;
input  reset_n;
input  read;
input  write;
input  exclusive;
//the arvalid and awvalid (1 bit each) portions of the payload are unused.
input  [PYLD_W-1:0] payload; // Group of address channel signals

output exokay;
output exfail;


// ----------------------------------------------------------------------------
// INTERNAL SIGNALS
// ----------------------------------------------------------------------------

// Exclusive Access Table
// There are (NUM_ENTRIES) entries in the table.
// Each entry includes three fields: {id, address, valid}
reg  [EX_ID_TBL_WIDTH-1:0]   ex_id, next_ex_id;
reg  [EX_ADDR_TBL_WIDTH-1:0] ex_addr, next_ex_addr;
reg  [NUM_ENTRIES-1:0]       ex_valid, next_ex_valid,
                             ex_id_eq, ex_addr_eq, empty_selected;

wire                         ex_id_found, ex_addr_found, ex_tbl_full;
reg  [NUM_ENTRIES-1:0]       ex_tbl_wr;
wire [NUM_ENTRIES-1:0]       ex_tbl_r;

// Payload signals
wire  [`GS_AW-1:0] addr;
//wire  arvalid_dummy;
//wire  awvalid_dummy;
wire  [ID_WIDTH-1:0] id;
wire  [`GS_BW-1:0] len;
wire  [`GS_SIZE_BW-1:0] size;
wire  [`GS_BURST_W-1:0] burst;

wire  [EX_ID_TBL_WIDTH-1:0]   ex_id_c;
wire  [EX_ADDR_TBL_WIDTH-1:0] ex_addr_c;
wire  [NUM_ENTRIES-1:0]       ex_valid_c;
// ----------------------------------------------------------------------------
// DESIGN
// ----------------------------------------------------------------------------
 
// Extract signal from payload
//assign {addr, id, arvalid_dummy, awvalid_dummy, len, size, burst} = payload[`GS_BURST_W + `GS_SIZE_W + `GS_BW + 1 + 1 + ID_WIDTH + `GS_AW - 1:0];
//assign {addr, id, len, size, burst} = {payload[`GS_BURST_W + `GS_SIZE_W + `GS_BW + 1 + 1 + ID_WIDTH + `GS_AW - 1:`GS_BURST_W + `GS_SIZE_W + `GS_BW + 2], payload[`GS_BURST_W + `GS_SIZE_W + `GS_BW -1:0]};

assign burst = payload[`GS_BURST_W-1:0];
assign size  = payload[`GS_BURST_W+`GS_SIZE_BW-1:`GS_BURST_W];
assign len   = payload[`GS_BURST_W+`GS_SIZE_W+`GS_BW-1:`GS_BURST_W+`GS_SIZE_W];
assign id    = payload[`GS_BURST_W+`GS_SIZE_W+`GS_BW+2+ID_WIDTH-1:`GS_BURST_W+`GS_SIZE_W+`GS_BW+2];
assign addr  = payload[`GS_BURST_W+`GS_SIZE_W+`GS_BW+2+ID_WIDTH+`GS_AW-1:`GS_BURST_W+`GS_SIZE_W+`GS_BW+2+ID_WIDTH];


// determine whether ID matches an ID in the table
assign ex_id_found = ex_id_eq;

// determine whether address matches an address in the table
assign ex_addr_found = (ex_addr_eq & ex_id_eq);

// determine whether the table is full
assign ex_tbl_full = ex_valid;

// determine whether the exclusive access failed
assign exfail = (NUM_ENTRIES == 0) ? exclusive:
  exclusive & ((read & (!ex_id_found & ex_tbl_full)) | (write & (!ex_id_found | (ex_id_found & (!ex_addr_found)))));

// determine whether the exclusive access passed
assign exokay = (NUM_ENTRIES == 0) ? 0: exclusive & (!exfail);

assign ex_id_c    = ex_id;
assign ex_addr_c  = ex_addr;
assign ex_valid_c = ex_valid;

// Select an empty location in table
integer empty_i;
always @(ex_tbl_full or ex_valid)
begin : find_empty_entries_PROC
  empty_selected = {NUM_ENTRIES{1'b0}};
  if (!ex_tbl_full)
    for (empty_i=0; empty_i<NUM_ENTRIES; empty_i=empty_i+1)
      if (ex_valid[empty_i] == 1'b0)
        begin
//spyglass disable_block W415a
//SMD: Signal may be multiply assigned (beside initialization) in the same scope
//SJ : This is happening inside for loop as per the logic. This won't cause any functionality issue. 
          //cg empty_selected = (1'b1 << empty_i);
          empty_selected = {NUM_ENTRIES{1'b0}};
          empty_selected[empty_i] = 1'b1;
//spyglass enable_block W415a
        end
end // find_empty_entries


// assert ff reset upon any write that matches a table address
// jstokes, 5.4.2011, STAR 9000463283
// - Entries in the exclusive monitoring table should only be cleared
//   by an exclusive write if the exclusive write succeeds, as only then
//   will the memory be updated. If the write is exclusive, then there
//   must be an address and id match with an entry in the table for the write
//   to succeed, and invalidate any entries with a matching address. 
//   If it is a normal write, then a write with
//   a matching address alone will invalidate all address matching entries.
//assign ex_tbl_r = (write & ex_addr_found) ? ex_addr_eq: 0;
assign ex_tbl_r = write 
                  ? (exclusive 

                       // For an exclusive write, if there is an address
                       // and ID match with any entry in the exclusive
                       // monitor table, then invalidate (reset) all
                       // entries with matching addresses.
                     ? (((ex_addr_eq & ex_id_eq)) ? ex_addr_eq : {NUM_ENTRIES{1'b0}})

                       // For a normal write, invalidate any entries
                       // with matching addresses.
                     : ex_addr_eq
                    )
                  : {NUM_ENTRIES{1'b0}};

// assert ff write enable upon successful exclusive read
always @(exclusive or read or ex_id_found or ex_id_eq or ex_tbl_full or
  empty_selected)
begin : write_control_PROC
  if (exclusive & read) begin
    if      (ex_id_found)  ex_tbl_wr = ex_id_eq;
    else if (ex_tbl_full)  ex_tbl_wr = {NUM_ENTRIES{1'b0}};
    else                   ex_tbl_wr = empty_selected;
  end
  else                     ex_tbl_wr = {NUM_ENTRIES{1'b0}};
end // write_control

// Instantiate comparators for each ID in the Exclusive Access Table
// ex_id_eq(i) is asserted if (ex_id(i) == id(i)) *and* entry(i) is valid.
integer id_i, id_j;
reg  [ID_WIDTH-1:0] temp_ex_id;
always @(ex_id or ex_valid or id)
begin : id_comparator_PROC
  for (id_i=0; id_i<NUM_ENTRIES; id_i=id_i+1) begin

    // select id(id_i)
    for (id_j=0; id_j<ID_WIDTH; id_j=id_j+1)
// spyglass disable_block SelfDeterminedExpr-ML
// SMD: Self determined expression found
// SJ: The expression indexing the vector/array will never exceed the bound of the vector/array.        
      temp_ex_id[id_j] = ex_id[ID_WIDTH*id_i+id_j];
// spyglass enable_block SelfDeterminedExpr-ML

    // infer ID comparator
    ex_id_eq[id_i] = ex_valid[id_i] & (id == temp_ex_id);

  end // for (id_i
end // id_comparator

// jstokes, 20.5.11, STAR 9000466641
// Address checking is being changed to take account of the fact that non
// exclusive accesses may start in a particular 128 byte aligned region,
// but finish in another one. The current GS address comparison will only
// detect an address as overlapping with an address that is being
// exclusively monitored, if it is in the same aligned 128 byte space. It 
// does this by ignoring the bottom 7 bits in the address comparison. 
// This method is ok for exclusive accesses, which cannot be greater than
// 128 bytes in total size, and must be aligned to the total size of the 
// transfer. But it is not OK for non exclusive accesses, as these do not
// have to obey such limitations.

// jstokes, 20.5.11, STAR 9000466641
// Calculate the start/end addresses of each transfer type. For WRAP
// tranfers we calculate the upper and lower boundaries
parameter FOUR_K_BND_MSB=12;
parameter EIGHT_K_BND_MSB=13;
parameter SIXTEEN_K_BND_MSB=14;
parameter MAX_SZ_BND_MSB=((MAX_TX_SZ_BYTES <= 4096) ? FOUR_K_BND_MSB : ((MAX_TX_SZ_BYTES<=8192) ? EIGHT_K_BND_MSB : SIXTEEN_K_BND_MSB));
// Need to create this dummy macro to pacify MTI when it compiles some
// later code in configurations where the code is removed with a generate
parameter MAX_SZ_BND_MSB_DUMMY=((MAX_SZ_BND_MSB > FOUR_K_BND_MSB) ? MAX_SZ_BND_MSB : (FOUR_K_BND_MSB+1));


// Create a version of size, which is limited in width and value to only
// what is required/possible for this configuration
    wire [`GS_MAX_SIZE_W-1:0] size_limited;
    reg [`GS_MAX_SIZE_W-1:0] size_limited_reg;
parameter [`GS_MAX_SIZE_W-1:0] GS_MAX_SIZE_WIRE = `GS_MAX_SIZE;
    always @(*) begin : size_limited_reg_32_PROC
      // Strip off unrequired bits
      size_limited_reg = size[`GS_MAX_SIZE_W-1:0];
      // Limit to max size
      if(size_limited_reg > `GS_MAX_SIZE) size_limited_reg = GS_MAX_SIZE_WIRE;
    end // size_limited_reg_32_PROC
    assign size_limited = size_limited_reg;
//assign size_limited = (`GS_DW==8) ? size_limited_wire : size_limited_reg;

// Extract only the bits of the address required to address within 4k
// A burst is not allowed to cross a 4k boundary
wire [FOUR_K_BND_MSB-1:0] addr_4kbnd;
assign addr_4kbnd = addr[FOUR_K_BND_MSB-1:0];

// Extract only the bits of the address required to address the maximum transaction size
//wire [MAX_SZ_BND_MSB-1:0] addr_max_sz_bnd;
//assign addr_max_sz_bnd = addr[MAX_SZ_BND_MSB-1:0];

// Length + 1, 1 bit wider to accomodate value of max length
wire [`GS_BW:0] len_p1;
//Overflow will never happen because bit width of len signal is one less than len_p1.
assign len_p1 = {1'b0, len} + 1;

// Create a mask of the lower address bits that address
// within the t/x size

// Wires for each size value
parameter [`GS_SIZE_W-1:0] SIZE_8 = `GS_SIZE_8;
parameter [`GS_SIZE_W-1:0] SIZE_16 = `GS_SIZE_16;
parameter [`GS_SIZE_W-1:0] SIZE_32 = `GS_SIZE_32;
parameter [`GS_SIZE_W-1:0] SIZE_64 = `GS_SIZE_64;
parameter [`GS_SIZE_W-1:0] SIZE_128 = `GS_SIZE_128;

reg [FOUR_K_BND_MSB-1:0] addr_size_mask_reg;




always @(*) begin : addr_size_mask_128_PROC
  addr_size_mask_reg = {FOUR_K_BND_MSB{1'b0}};
  case(size_limited)
    SIZE_8[`GS_MAX_SIZE_W-1:0]  : addr_size_mask_reg = {FOUR_K_BND_MSB{1'b1}};
    SIZE_16[`GS_MAX_SIZE_W-1:0] : addr_size_mask_reg = {FOUR_K_BND_MSB{1'b1}} << `GS_SIZE_16;
    SIZE_32[`GS_MAX_SIZE_W-1:0] : addr_size_mask_reg = {FOUR_K_BND_MSB{1'b1}} << `GS_SIZE_32;
    SIZE_64[`GS_MAX_SIZE_W-1:0] : addr_size_mask_reg = {FOUR_K_BND_MSB{1'b1}} << `GS_SIZE_64;
    SIZE_128[`GS_MAX_SIZE_W-1:0] : addr_size_mask_reg = {FOUR_K_BND_MSB{1'b1}} << `GS_SIZE_128;
    default : addr_size_mask_reg = {FOUR_K_BND_MSB{1'b1}} << `GS_SIZE_128;
  endcase
end



wire [FOUR_K_BND_MSB-1:0] addr_size_mask;
assign addr_size_mask = addr_size_mask_reg;

// Create version of incoming address aligned to size boundary
wire [FOUR_K_BND_MSB-1:0] addr_size_align;
assign addr_size_align = addr_4kbnd & addr_size_mask;

// For INCR's, need a version of addr_size_align which will hold the extra
// address bits required to address the maximum possible t/x size
wire [MAX_SZ_BND_MSB-1:0] addr_size_align_maxbnd;
generate
  if(MAX_SZ_BND_MSB>FOUR_K_BND_MSB) begin : addr_size_align_maxbnd_genb1
    // *DUMMY macro required because MTI still compiles this line when
    // MAX_SZ_BND_MSB <= FOUR_K_BND_MSB. Gives error that part select index
    // to addr are reversed.
    assign addr_size_align_maxbnd = {addr[MAX_SZ_BND_MSB_DUMMY-1:FOUR_K_BND_MSB],addr_size_align};
  end else begin : addr_size_align_maxbnd_genb2
    assign addr_size_align_maxbnd = addr_size_align;
  end
endgenerate

// Calculate the size in bytes of the transfer
wire [`GS_TX_SIZE_BYTES_W-1:0] tx_size_bytes;
generate if (`GS_TX_SIZE_BYTES_W > (`GS_BW+1))
begin : GS_TX_SIZE_BYTES_W_gt_GS_BW_PROC
  assign tx_size_bytes = {{(`GS_TX_SIZE_BYTES_W-(`GS_BW+1)){1'b0}}, len_p1} << size_limited;
end
else if (`GS_TX_SIZE_BYTES_W < (`GS_BW+1))
begin : GS_TX_SIZE_BYTES_W_lt_GS_BW_PROC
  assign tx_size_bytes = {{((`GS_BW+1)-`GS_TX_SIZE_BYTES_W){1'b0}}, len_p1} << size_limited;
end
else
begin : GS_TX_SIZE_BYTES_W_eq_GS_BW_PROC
  assign tx_size_bytes = len_p1 << size_limited;
end
endgenerate

//When (MAX_SZ_BND_MSB < `GS_TX_SIZE_BYTES_W), the extra MSBs are unused.
wire [`GS_TX_SIZE_BYTES_W-1:0] tx_size_bytes_sub1;

//spyglass disable_block TA_09
//SMD: Reports cause of uncontrollability or unobservability and estimates the number of nets whose controllability/ observability is impacted
//SJ : This is not an issue as few bits of tx_size_bytes_sub1 may be fixed
//underflow will never happen since functionally tx_size_bytes will never be < 1.
assign tx_size_bytes_sub1 = tx_size_bytes - 1;
//spyglass enable_block TA_09

// Version of tx_size_bytes, which will never need to store a value > 1K
// bytes. Used for wrap transfers, where length >16 is not permitted.
wire [`GS_TX_SIZE_BYTES_1KMAX_W-1:0] tx_size_bytes_1kmax;
parameter [`GS_TX_SIZE_BYTES_1KMAX_W-1:0] TEMP_VAL = 16;
assign tx_size_bytes_1kmax = tx_size_bytes[`GS_TX_SIZE_BYTES_1KMAX_W-1:0];

// End address of an INCR transfer
// NOTE the -1 on tx_size_bytes, the end address is the address of
// the last byte addressed by the t/x
wire [MAX_SZ_BND_MSB-1:0] addr_incr_end_maxbnd;
generate if (MAX_SZ_BND_MSB > `GS_TX_SIZE_BYTES_W) begin : MAX_SZ_BND_MSB_gt_GS_TX_SIZE_BYTES_PROC
//spyglass disable_block STARC-2.10.6.1
//SMD:Possible loss of carry or borrow in addition or subtraction (Verilog)
//SJ: Bursts must not cross 4KB boundaries to prevent them from crossing boundaries
//    between slaves and to limit the size of the address incrementer required within slaves.
//    Here addr_incr_end_maxbnd should be within 4kB boundary. So there will be
//    no possible loss of carry or borrow in addition or subtraction.
//spyglass disable_block W484
//SMD:Possible loss of carry or borrow due to addition or subtraction
//SJ :Please look into previous SJ.
//spyglass disable_block W164a
//SMD: Possible loss of carry or borrow due to addition or subtraction.
//SJ: Bursts must not cross 4KB boundaries to prevent them from crossing boundaries
//    between slaves and to limit the size of the address incrementer required within slaves.
//    Here addr_incr_end_maxbnd should be within 4kB boundary. So there will be
//    no possible loss of carry or borrow in addition or subtraction.
assign addr_incr_end_maxbnd = addr_size_align_maxbnd + {{(MAX_SZ_BND_MSB-`GS_TX_SIZE_BYTES_W){1'b0}}, tx_size_bytes_sub1};
end
else if (MAX_SZ_BND_MSB < `GS_TX_SIZE_BYTES_W) begin : MAX_SZ_BND_MSB_lt_GS_TX_SIZE_BYTES_PROC
assign addr_incr_end_maxbnd = addr_size_align_maxbnd + tx_size_bytes_sub1[MAX_SZ_BND_MSB-1:0];
end
else begin : MAX_SZ_BND_MSB_eq_GS_TX_SIZE_BYTES_PROC
assign addr_incr_end_maxbnd = addr_size_align_maxbnd + tx_size_bytes_sub1;
end
endgenerate
//spyglass enable_block W164a
//spyglass enable_block W484
//spyglass enable_block STARC-2.10.6.1

// Version of tx_size_bytes_sub1, which will never need to store a value > 1K
// bytes. Used for wrap transfers, where length >16 is not permitted.
//wire [`GS_TX_SIZE_BYTES_1KMAX_W-1:0] tx_size_bytes_sub1_1kmax;
//assign tx_size_bytes_sub1_1kmax = tx_size_bytes_sub1[`GS_TX_SIZE_BYTES_1KMAX_W-1:0];

// Combine with the incoming address to create a full width address signal
// Range:0-6. The exclusive access monitor ignores the low-order bits of the address
// per the AXI Protocol v1.0 Specification. Monitoring 128 bytes for any given
// access corresponds to dropping the 7 low-order bits.
wire [`GS_AW-1:0] addr_incr_end;
assign addr_incr_end = {addr[`GS_AW-1:MAX_SZ_BND_MSB],addr_incr_end_maxbnd};

// End address of a FIXED transfer
// NOTE the -1 on (1<<size), the end address is the address of
// the last byte addressed by the t/x
wire [FOUR_K_BND_MSB-1:0] addr_fixed_end_4kbnd;
parameter [FOUR_K_BND_MSB-1:0] TEMP_VAL_1 = 1;
//spyglass disable_block TA_09
//SMD: Reports cause of uncontrollability or unobservability and estimates the number of nets whose controllability/ observability is impacted
//SJ : Here violation is occuring only due to bits which are not used or floating bits. We are not reading all bits of addr_fixed_end_4kbnd hence observability is not required for floating bits. 
assign addr_fixed_end_4kbnd = addr_size_align + ((TEMP_VAL_1<<size_limited)-1);
//spyglass enable_block TA_09
// Combine with the incoming address to create a full width address signal
// Range:0-6. The exclusive access monitor ignores the low-order bits of the address
// per the AXI Protocol v1.0 Specification. Monitoring 128 bytes for any given
// access corresponds to dropping the 7 low-order bits.
wire [`GS_AW-1:0] addr_fixed_end;
assign addr_fixed_end = {addr[`GS_AW-1:FOUR_K_BND_MSB],addr_fixed_end_4kbnd};

// ----------------------------------------------------------------------------
// Decode upper and lower boundary of WRAP transfers
//
// * If the maximum t/x size is > 128 bytes, then a wrap could start
//   outside of an aligned 128 byte space, but still address it.
//
// * In the logic below, we do not take account of transfer sizes less
//   than 64-bits. 
//
//   16 * (64/8) = 128 
//
//   A WRAP transfer always wraps at the total t/x size boundary, and 128 is 
//   a boundary for any total t/x size <= 128. A wrap t/x of size <=
//   64-bits that starts in a particular 128 byte aligned address space,
//   will not address bytes outside of that 128 byte aligned address space.
//   Therefore, for a t/x size of <= 64-bits, only the start address of the 
//   WRAP needs to be checked against outstanding exclusive t/x's.
//
//   This means that the logic that decodes the upper and lower boundary
//   of a wrap transfer can be optimised away if GS_DW <= 64, and otherwise
//   only sizes of > 64 need to be considered.
// ----------------------------------------------------------------------------
parameter TX_SZ_SEL_W=3;
reg [TX_SZ_SEL_W-1:0] tx_size_select;
always @(*) begin : tx_size_select_PROC
  tx_size_select = {TX_SZ_SEL_W{1'b0}};
  if(  (tx_size_bytes_1kmax >  (TEMP_VAL << `GS_SIZE_64)) 
     & (tx_size_bytes_1kmax <= (TEMP_VAL << `GS_SIZE_128))
     & (`GS_DW >= 128)
    ) 
  begin
    tx_size_select[0] = 1'b1;
  end

  if(  (tx_size_bytes_1kmax >  (TEMP_VAL << `GS_SIZE_128)) 
     & (tx_size_bytes_1kmax <= (TEMP_VAL << `GS_SIZE_256))
     & (`GS_DW >= 256)
    ) 
  begin
    tx_size_select[1] = 1'b1;
  end

  if(  (tx_size_bytes_1kmax >  (TEMP_VAL << `GS_SIZE_256)) 
     & (tx_size_bytes_1kmax <= (TEMP_VAL << `GS_SIZE_512))
     & (`GS_DW >= 512)
    ) 
  begin
    tx_size_select[2] = 1'b1;
  end
end // tx_size_select_PROC

// LSbit is tied to zero since Monitoring 128 bytes for any given
// access corresponds to dropping the 7 low-order bits and tying the 
// respective LSbits to zero while monitoring > 128 bytes.

// lower address boundaries for particular total transaction sizes
// tx_size_select is used to select which one of these we use
//spyglass disable_block W415a
//SMD: Signal may be multiply assigned (beside initialization) in the same scope.
//SJ : Here initially we assigned same bits of the variable to 0 in order to  avoid latches. So functionally it is correct. Hence we can waive this warning.
reg [FOUR_K_BND_MSB-1:ADDR_COMP_LSB] addr_lwr_bnd_tsz_256;
always @(*) begin : addr_lwr_bnd_tsz_256_PROC
  addr_lwr_bnd_tsz_256 = {(FOUR_K_BND_MSB-ADDR_COMP_LSB){1'b0}};
  addr_lwr_bnd_tsz_256[FOUR_K_BND_MSB-1:8] = addr[FOUR_K_BND_MSB-1:8];
end

reg [FOUR_K_BND_MSB-1:ADDR_COMP_LSB] addr_lwr_bnd_tsz_512;
always @(*) begin : addr_lwr_bnd_tsz_512_PROC
  addr_lwr_bnd_tsz_512 = {(FOUR_K_BND_MSB-ADDR_COMP_LSB){1'b0}};
  addr_lwr_bnd_tsz_512[FOUR_K_BND_MSB-1:9] = addr[FOUR_K_BND_MSB-1:9];
end

reg [FOUR_K_BND_MSB-1:ADDR_COMP_LSB] addr_lwr_bnd_tsz_1024;
always @(*) begin : addr_lwr_bnd_tsz_1024_PROC
  addr_lwr_bnd_tsz_1024 = {(FOUR_K_BND_MSB-ADDR_COMP_LSB){1'b0}};
  addr_lwr_bnd_tsz_1024[FOUR_K_BND_MSB-1:10] = addr[FOUR_K_BND_MSB-1:10];
end
//spyglass enable_block W415a

// Select the lower wrap boundary
// If a particular branch of the mux is not required, tx_size_select is
// limited to not select that branch so it will be optimised away at
// synthesis
reg [FOUR_K_BND_MSB-1:ADDR_COMP_LSB] addr_lwr_bnd_4kbnd;
always @(*) begin : addr_lwr_bnd_4kbnd_PROC
  addr_lwr_bnd_4kbnd = {(FOUR_K_BND_MSB-ADDR_COMP_LSB){1'b0}};
  case(tx_size_select)
    3'b001  : addr_lwr_bnd_4kbnd = addr_lwr_bnd_tsz_256;
    3'b010  : addr_lwr_bnd_4kbnd = addr_lwr_bnd_tsz_512;
    3'b100  : addr_lwr_bnd_4kbnd = addr_lwr_bnd_tsz_1024;
    default : addr_lwr_bnd_4kbnd = {(FOUR_K_BND_MSB-ADDR_COMP_LSB){1'b0}};
  endcase
end

// Combine with the incoming address to create a full width address signal
wire [`GS_AW-1:ADDR_COMP_LSB] addr_lwr_bnd;
assign addr_lwr_bnd = {addr[`GS_AW-1:FOUR_K_BND_MSB],addr_lwr_bnd_4kbnd};

// Select the lower wrap boundary
// 1 is subtracted from tx_size_bytes so we end up with the address
// of the last byte addressed
// If a particular branch of the mux is not required, tx_size_select is
// limited to not select that branch so it will be optimised away at
// synthesis
reg [FOUR_K_BND_MSB-1:ADDR_COMP_LSB] addr_upr_bnd_4kbnd;
always @(*) begin : addr_upr_bnd_4kbnd_PROC
 // The upper bound address, or rather the last byte addressed before the
 // upper boundary, is the same as the lower boundary except with all 1's
 // in the bit positions that address inside the transaction size
 case(tx_size_select)
   3'b001  : addr_upr_bnd_4kbnd = {addr[FOUR_K_BND_MSB-1:8], {1{1'b1}}};
   3'b010  : addr_upr_bnd_4kbnd = {addr[FOUR_K_BND_MSB-1:9], {2{1'b1}}};
   3'b100  : addr_upr_bnd_4kbnd = {addr[FOUR_K_BND_MSB-1:10], {3{1'b1}}};
   default : addr_upr_bnd_4kbnd = {addr[FOUR_K_BND_MSB-1:8], {1{1'b1}}};
 endcase
end

// Combine with the incoming address to create a full width address signal
//wire [`GS_AW-1:0] addr_upr_bnd;
wire [`GS_AW-1:ADDR_COMP_LSB] addr_upr_bnd;
assign addr_upr_bnd = {addr[`GS_AW-1:FOUR_K_BND_MSB],addr_upr_bnd_4kbnd};

// Check the incoming transaction against the exclusive addresses
// currently being monitored
integer addr_i, addr_j;
reg  [ADDR_COMP_WIDTH-1:0] temp_ex_addr;
always @(*)
begin : addr_comparator_PROC
  for (addr_i=0; addr_i<NUM_ENTRIES; addr_i=addr_i+1) begin
    ex_addr_eq[addr_i] = 1'b0;

    // select addr(addr_i)
    for (addr_j=0; addr_j<ADDR_COMP_WIDTH; addr_j=addr_j+1)
// spyglass disable_block SelfDeterminedExpr-ML
// SMD: Self determined expression found
// SJ: The expression indexing the vector/array will never exceed the bound of the vector/array.        
      temp_ex_addr[addr_j] = ex_addr[ADDR_COMP_WIDTH*addr_i+addr_j];
// spyglass enable_block SelfDeterminedExpr-ML

    if(ex_valid[addr_i]) begin
      // There is a valid address in this slot
      
      case(burst) 
        `GS_AXI_FIXED : begin
          if(  (addr[`GS_AW-1:ADDR_COMP_LSB] == temp_ex_addr)
             | (addr_fixed_end[`GS_AW-1:ADDR_COMP_LSB] == temp_ex_addr)
            )
          begin
            ex_addr_eq[addr_i] = 1'b1;
          end
        end // GS_AXI_FIXED
  
        `GS_AXI_INCR : begin
          if(  (addr[`GS_AW-1:ADDR_COMP_LSB] <= temp_ex_addr)
             & (addr_incr_end[`GS_AW-1:ADDR_COMP_LSB] >= temp_ex_addr)
            )
          begin
            ex_addr_eq[addr_i] = 1'b1;
          end
        end // GS_AXI_INCR
  
        `GS_AXI_WRAP : begin
          // For a WRAP, either the t/x starts in the exclusive addresses
          // 128 byte region, or the WRAP encompasses the exclusive
          // addresses' aligned 128-byte region. These are the match
          // requirements
          if(addr[`GS_AW-1:ADDR_COMP_LSB] == temp_ex_addr) ex_addr_eq[addr_i] = 1'b1;
          if(  (addr_lwr_bnd[`GS_AW-1:ADDR_COMP_LSB] <= temp_ex_addr)
             & (addr_upr_bnd[`GS_AW-1:ADDR_COMP_LSB] >= temp_ex_addr)
               // Wrap larger than 128 bytes in size is only possible 
               // if DW is greater than or equal to 128 
             & (`GS_DW >= 128)
               // t/x size > 128 bytes
             & (|tx_size_select)
            )
          begin
            ex_addr_eq[addr_i] = 1'b1;
          end
        end // GS_AXI_WRAP
        
        default : begin
          ex_addr_eq[addr_i] = 1'b0;
        end
      endcase // burst

    end // ex_valid[addr_i]

    // infer addr comparator
    //ex_addr_eq[addr_i] = ex_valid[addr_i] & (addr == temp_ex_addr);

  end // for (addr_i
end // addr_comparator


// ----------------------------------------------------------------------------
// Flip Flops
//
// For each entry (i) in the exclusive access table,
// instantiate the following three sets of flip flops:
//                --------
// -----id--------|D    Q|---ex_id(i)---
// --ex_tbl_wr(i)-|en    |
// ---------------|r     |
// ----clk--------|>     |
//                --------
//                --------
// ----addr-------|D    Q|--ex_addr(i)--
// --ex_tbl_wr(i)-|en    |
// ---------------|r     |
// ----clk--------|>     |
//                --------
//                --------
// -----1---------|D    Q|-ex_valid(i)--
// --ex_tbl_wr(i)-|en    |
// --ex_tbl_r(i)--|r     |
// ----clk--------|>     |
//                --------
// ----------------------------------------------------------------------------

// counters for wire assignments
integer entry, id_bit, addr_bit;

always @(*)
begin : next_dff_PROC
  for (entry=0; entry<NUM_ENTRIES; entry=entry+1) begin
  
    // assign ID flip flops
    for (id_bit=0; id_bit<ID_WIDTH; id_bit=id_bit+1)
// spyglass disable_block SelfDeterminedExpr-ML
// SMD: Self determined expression found
// SJ: The expression indexing the vector/array will never exceed the bound of the vector/array.        
      next_ex_id[(entry*ID_WIDTH)+id_bit] = (ex_tbl_wr[entry]) ?
        id[id_bit] : ex_id[(entry*ID_WIDTH)+id_bit];
    
    // assign address flip flops
    for (addr_bit=0; addr_bit<ADDR_COMP_WIDTH; addr_bit=addr_bit+1)
      next_ex_addr[(entry*ADDR_COMP_WIDTH)+addr_bit] = (ex_tbl_wr[entry]) ?
        addr[addr_bit+ADDR_COMP_LSB] : ex_addr[(entry*ADDR_COMP_WIDTH)+addr_bit];
// spyglass enable_block SelfDeterminedExpr-ML
        //addr[addr_bit] : ex_addr[(entry*ADDR_COMP_WIDTH)+addr_bit];
        // jstokes, 20.5.11, STAR 9000466641
        // Incoming address is now full width
    
    // assign valid flip flops
    if      (ex_tbl_r[entry])   next_ex_valid[entry] = 1'b0;
    else if (ex_tbl_wr[entry])  next_ex_valid[entry] = 1'b1;
    else                        next_ex_valid[entry] = ex_valid[entry];

  end // for (entry
  
end // next_dff


// standard DFFs
always @(posedge clk or negedge reset_n)
begin : dff_PROC
  if (!reset_n) begin
    ex_id    <= {EX_ID_TBL_WIDTH{1'b0}};
    ex_addr  <= {EX_ADDR_TBL_WIDTH{1'b0}};
    ex_valid <= {NUM_ENTRIES{1'b0}};
  end
  else begin
    if (clk_en) begin
      ex_id    <= next_ex_id;
      ex_addr  <= next_ex_addr;
      ex_valid <= next_ex_valid;
    end
    else begin
      ex_id    <= ex_id_c;
      ex_addr  <= ex_addr_c;
      ex_valid <= ex_valid_c;
    end
  end
end // dff

endmodule
