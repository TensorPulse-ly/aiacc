// ---------------------------------------------------------------------
// 版权与版本声明：Synopsys 知识产权，仅可通过书面授权使用，禁止未授权传播
// ------------------------------------------------------------------------------
// Copyright 2005 - 2022 Synopsys, INC.  // Synopsys 版权所有（2005-2022）
// This Synopsys IP and all associated documentation are proprietary to
// Synopsys, Inc. and may only be used pursuant to the terms and conditions of a
// written license agreement with Synopsys, Inc. All other use, reproduction,
// modification, or distribution of the Synopsys IP or the associated
// documentation is strictly prohibited.  // 明确IP使用权限：仅书面授权可用，禁止未授权使用/修改/传播
// Inclusivity & Diversity - Visit SolvNetPlus to read the "Synopsys Statement on
//            Inclusivity and Diversity" (Refer to article 000036315 at
//                        https://solvnetplus.synopsys.com)  // 包容性声明及参考链接
// 
// Component Name   : DW_axi_gm  // 组件名称：AXI通用主控制器（GM）
// Component Version: 2.05a      // 组件版本：2.05a
// Release Type     : GA         // 发布类型：正式版（GA=General Availability）
// Build ID         : 16.17.20.6 // 构建ID：用于版本追溯
// ------------------------------------------------------------------------------

// Release version :  2.05a  // 发布版本
// File Version     :        $Revision: #11 $  // 文件版本：版本控制标记（第11次修订）
// Revision: $Id: //dwh/DW_ocb/DW_axi_gm/axi_dev_br/src/DW_axi_gm_core.v#11 $  // 修订ID：文件路径+版本，用于版本管理
// 
// ----------------------------------------------------------------------------
// Author: Christian Graber  // 作者：Christian Graber
// ----------------------------------------------------------------------------

`include "DW_axi_gm_all_includes.vh"  // 引用头文件：包含GM_ID、GM_AW等宏定义，避免重复定义

// 模块定义：AXI通用主控制器核心模块，/*AUTOARG*/是工具自动生成端口列表的标记（简化代码编写）
module DW_axi_gm_core (/*AUTOARG*/
  // Outputs：模块输出端口（GIF响应、AXI请求信号）
  saccept, sid, svalid, slast, sdata, sresp, awvalid, awid, awaddr, 
  awlen, awsize, awburst, awlock, awcache,
  awprot, wvalid, wlast, 
  wid, wdata, wstrb, bready, arvalid, arid, araddr, arlen, arsize, 
  arburst, arlock, arcache, arprot, rready,
  // Inputs：模块输入端口（全局信号、GIF请求、AXI响应信号）
  aclk, aresetn, gclken,
  mid, maddr, mread, mwrite, 
 mlen,
  msize, mburst, mcache, mprot, mdata, mwstrb, mready, awready, 
  wready, bvalid, bid, bresp, arready, rvalid, rid, rlast, rdata, 
  rresp
  );

  // --------------------------------------------------------------------------
  // Parameters：参数声明（本模块未显式定义参数，依赖头文件宏定义，此处预留参数块）
  // --------------------------------------------------------------------------

  // Low Power FSM：低功耗状态机（本模块未实现，预留注释）
  // --------------------------------------------------------------------------
  // Ports：端口类型声明（明确每个端口的位宽/类型，与外部信号匹配）
  // --------------------------------------------------------------------------

  // Global signals：全局信号（AXI时钟、复位、全局使能）
  input                             aclk;                  // AXI总线时钟（上升沿触发，所有时序逻辑同步于此）
  input                             aresetn;               // 异步复位（低电平有效，复位时清空内部状态）
  input                             gclken;                // 全局时钟使能（高电平时，内部逻辑才执行）

  // GIF request：GIF（通用接口）请求信号（从外部接收的读/写请求）
  input [`GM_ID-1:0]                mid;                   // GIF请求ID（用于请求-响应对应，位宽由GM_ID宏定义）
  input [`GM_AW-1:0]                maddr;                 // GIF请求地址（AXI地址总线宽度，由GM_AW宏定义）
  input                             mread;                 // GIF读请求使能（高有效：当前请求为读操作）
  input                             mwrite;                // GIF写请求使能（高有效：当前请求为写操作）
  input [`GM_BW-1:0]                mlen;                  // GIF突发长度（突发传输的总拍数-1，位宽由GM_BW宏定义）
  input [2:0]                       msize;                 // GIF传输宽度（0=1字节，1=2字节，2=4字节等，AXI标准3位编码）
  input [1:0]                       mburst;                // GIF突发类型（0=固定，1=递增，2=回环，AXI标准2位编码）
  input [3:0]                       mcache;                // GIF缓存属性（AXI标准4位编码，指示缓存策略）
  input [2:0]                       mprot;                 // GIF保护属性（AXI标准3位编码，指示安全/权限等级）
  input [`GM_DW-1:0]                mdata;                 // GIF写数据（AXI数据总线宽度，由GM_DW宏定义）
  input [`GM_WW-1:0]                mwstrb;                // GIF写数据字节掩码（高有效，指示mdata中哪些字节有效，位宽=GM_DW/8）
  output                            saccept;               // GIF请求接受信号（高有效：模块已准备好接收当前GIF请求）

  // GIF response：GIF响应信号（向外部反馈的读/写结果）
  output [`GM_ID-1:0]               sid;                   // GIF响应ID（与请求mid对应，标识当前响应属于哪个请求）
  output                            svalid;                // GIF响应有效（高有效：当前sid/sdata/sresp为有效数据）
  output                            slast;                 // GIF突发响应最后一拍（高有效：当前响应是突发传输的最后一拍）
  output [`GM_DW-1:0]               sdata;                 // GIF读响应数据（仅读操作有效，回传从AXI从设备读取的数据）
  output [2:0]                      sresp;                 // GIF响应状态（扩展AXI响应：0=OK，1=错误等，3位编码）
  input                             mready;                // GIF接受响应使能（外部输入：高有效时，外部可接收当前响应）

  // AXI write request：AXI写地址通道信号（向AXI从设备发送的写地址请求）
  output                            awvalid;               // AXI写地址有效（高有效：当前awid/awaddr等信号有效）
  output [`GM_ID-1:0]               awid;                  // AXI写地址ID（与GIF的mid对应，用于写地址-写响应匹配）
  output [`GM_AW-1:0]               awaddr;                // AXI写地址（从GIF的maddr转换而来）
  output [`GM_BW-1:0]               awlen;                 // AXI写突发长度（从GIF的mlen转换而来，AXI标准：总拍数-1）
  output [2:0]                      awsize;                // AXI写传输宽度（从GIF的msize转换而来，AXI标准3位编码）
  output [1:0]                      awburst;               // AXI写突发类型（从GIF的mburst转换而来，AXI标准2位编码）
  output [`GM_W_LTW-1:0]            awlock;                // AXI写锁定属性（本设计固定为1'b0，不使用锁定功能，位宽由GM_W_LTW宏定义）
  output [3:0]                      awcache;               // AXI写缓存属性（从GIF的mcache转换而来，AXI标准4位编码）
  output [2:0]                      awprot;                // AXI写保护属性（从GIF的mprot转换而来，AXI标准3位编码）
  input                             awready;               // AXI从设备接受写地址（从设备输入：高有效时，从设备已接收写地址）

  // AXI write data：AXI写数据通道信号（向AXI从设备发送的写数据）
  output                            wvalid;                // AXI写数据有效（高有效：当前wid/wdata/wstrb等信号有效）
  output                            wlast;                 // AXI写数据最后一拍（高有效：当前写数据是突发传输的最后一拍）
  output [`GM_ID-1:0]               wid;                   // AXI写数据ID（与awid对应，确保写地址-写数据顺序）
  output [`GM_DW-1:0]               wdata;                 // AXI写数据（从GIF的mdata转换而来）
  output [`GM_WW-1:0]               wstrb;                 // AXI写数据字节掩码（从GIF的mwstrb转换而来）
  input                             wready;                // AXI从设备接受写数据（从设备输入：高有效时，从设备已接收写数据）

  // AXI write response：AXI写响应通道信号（从AXI从设备接收的写结果）
  input                             bvalid;                // AXI写响应有效（从设备输入：高有效时，当前bid/bresp有效）
  input [`GM_ID-1:0]                bid;                   // AXI写响应ID（与awid对应，标识当前响应属于哪个写请求）
  input [1:0]                       bresp;                 // AXI写响应状态（AXI标准2位编码：0=OKAY，1=EXOKAY，2=SLVERR，3=DECERR）
  output                            bready;                // AXI主控制器接受写响应（高有效：模块已准备好接收写响应）

  // AXI read request：AXI读地址通道信号（向AXI从设备发送的读地址请求）
  output                            arvalid;               // AXI读地址有效（高有效：当前arid/araddr等信号有效）
  output [`GM_ID-1:0]               arid;                  // AXI读地址ID（与GIF的mid对应，用于读地址-读响应匹配）
  output [`GM_AW-1:0]               araddr;                // AXI读地址（从GIF的maddr转换而来）
  output [`GM_BW-1:0]               arlen;                 // AXI读突发长度（从GIF的mlen转换而来）
  output [2:0]                      arsize;                // AXI读传输宽度（从GIF的msize转换而来）
  output [1:0]                      arburst;               // AXI读突发类型（从GIF的mburst转换而来）
  output [`GM_W_LTW-1:0]            arlock;                // AXI读锁定属性（本设计固定为1'b0，不使用锁定功能）
  output [3:0]                      arcache;               // AXI读缓存属性（从GIF的mcache转换而来）
  output [2:0]                      arprot;                // AXI读保护属性（从GIF的mprot转换而来）
  input                             arready;               // AXI从设备接受读地址（从设备输入：高有效时，从设备已接收读地址）

  // AXI read response & read data：AXI读响应/数据通道信号（从AXI从设备接收的读结果）
  input                             rvalid;                // AXI读响应有效（从设备输入：高有效时，当前rid/rdata/rresp有效）
  input [`GM_ID-1:0]                rid;                   // AXI读响应ID（与arid对应，标识当前响应属于哪个读请求）
  input                             rlast;                 // AXI读响应最后一拍（高有效：当前读响应是突发传输的最后一拍）
  input [`GM_DW-1:0]                rdata;                 // AXI读响应数据（从从设备读取的数据，需回传给GIF）
  input [2:0]                       rresp;                 // AXI读响应状态（AXI标准2位编码，扩展为3位与GIF的sresp匹配）
  output                            rready;                // AXI主控制器接受读响应（高有效：模块已准备好接收读响应）

  // --------------------------------------------------------------------------
  // Internal Signals：内部信号声明（仅模块内部使用，不对外暴露）
  // --------------------------------------------------------------------------

  reg                                    saccept_r;          // saccept的寄存器版本（时序逻辑输出，避免组合逻辑毛刺）
  reg [`GM_BW-1:0]                       wburst_gif_count;   // GIF侧写突发计数器（记录当前写突发已传输的拍数）
  wire[`GM_BW-1:0]                       wburst_gif_count_int;// wburst_gif_count的线网别名（避免时序逻辑中直接读取寄存器）
  reg                                    saccept_reqb_block; // 请求缓冲区接受控制信号（控制是否允许新请求写入请求缓冲区）
  reg                                    rready_gc;          // 读响应接受使能（全局时钟使能域的信号，高有效时接收读响应）
  reg                                    bready_gc;          // 写响应接受使能（全局时钟使能域的信号，高有效时接收写响应）
  reg [`GM_DW+`GM_ID+3:0]                respb_data_in;      // 响应缓冲区输入数据（拼接ID、响应状态、数据等，总位宽=GM_DW+GM_ID+4）
  reg                                    gvalid;             // 响应有效标记（标识当前选择的读/写响应是否有效）
  reg                                    bselect;            // 响应选择标记（0=优先处理读响应，1=优先处理写响应）
  reg [`GM_BW-1:0]                       wburst_axi_count;   // AXI侧写突发计数器（记录当前写突发已传输的拍数）
  wire[`GM_BW-1:0]                       wburst_axi_count_int;// wburst_axi_count的线网别名（避免时序逻辑中直接读取寄存器）

  // 请求缓冲区相关信号（缓存GIF请求的地址、控制信息）
  wire                                   saccept_reqb;       // 请求缓冲区接受能力标记（高有效：请求缓冲区可接受新请求）
  wire                                   saccept_wb;         // 写数据缓冲区接受能力标记（高有效：写数据缓冲区可接受新数据）
  wire                                   svalid;             // GIF响应有效（与输出端口svalid直接关联）
  wire [2:0]                             sresp;              // GIF响应状态（与输出端口sresp直接关联）
  wire                                   slast;              // GIF突发响应最后一拍（与输出端口slast直接关联）
  wire                                   gready;             // 响应缓冲区接受能力标记（高有效：响应缓冲区可接受新响应）
  wire                                   respb_push_n;       // 响应缓冲区写入使能（低有效：向响应缓冲区写入数据）
  wire                                   respb_pop_n;        // 响应缓冲区读出使能（低有效：从响应缓冲区读出数据）
  wire                                   respb_push_gc_n;    // 全局时钟使能域的响应缓冲区写入使能（低有效）
  wire                                   respb_pop_gc_n;     // 全局时钟使能域的响应缓冲区读出使能（低有效）
  wire                                   respb_empty;        // 响应缓冲区空状态（高有效：缓冲区无数据）
  wire                                   respb_full;         // 响应缓冲区满状态（高有效：缓冲区无空闲空间）
  wire [`GM_DW+`GM_ID+3:0]               respb_data_out;     // 响应缓冲区输出数据（从缓冲区读出的响应数据）
  // 请求缓冲区数据（拼接GIF请求的ID、地址、控制信息，总位宽=GM_AW+GM_ID+GM_BW+14）
  wire [`GM_AW+`GM_ID+`GM_BW+13:0]       reqb_data_in;       // 请求缓冲区输入数据
  wire [`GM_AW+`GM_ID+`GM_BW+13:0]       reqb_data_out;      // 请求缓冲区输出数据
  wire                                   reqb_push_gc_n;     // 全局时钟使能域的请求缓冲区写入使能（低有效）
  wire                                   reqb_pop_n;         // 请求缓冲区读出使能（低有效）
  wire                                   reqb_push_n;        // 请求缓冲区写入使能（低有效）
  wire                                   reqb_empty;         // 请求缓冲区空状态（高有效）
  wire                                   reqb_full;          // 请求缓冲区满状态（高有效）
  // 写数据缓冲区相关信号（缓存GIF写请求的数据、掩码）
  wire [`GM_ID+`GM_DW+`GM_WW+`GM_BW-1:0] wb_data_in;         // 写数据缓冲区输入数据（拼接ID、数据、掩码、突发长度）
  wire [`GM_ID+`GM_DW+`GM_WW+`GM_BW-1:0] wb_data_out;        // 写数据缓冲区输出数据
  wire                                   wb_push_gc_n;       // 全局时钟使能域的写数据缓冲区写入使能（低有效）
  wire                                   wb_pop_n;           // 写数据缓冲区读出使能（低有效）
  wire                                   wb_push_n;          // 写数据缓冲区写入使能（低有效）
  wire                                   wb_empty;           // 写数据缓冲区空状态（高有效）
  wire                                   wb_full;            // 写数据缓冲区满状态（高有效）
  wire [`GM_BW-1:0]                      wlen;               // AXI写突发长度（从写数据缓冲区读出，与awlen对应）
  wire                                   wburst_gif_active;  // GIF侧写突发活跃标记（高有效：当前处于GIF写突发传输中）

  // Unconnected wires：未连接信号（缓冲区的辅助状态信号，本设计未使用，仅声明避免工具告警）
  wire                                   unconnected_req_almost_empty;  // 请求缓冲区“几乎空”（未使用）
  wire                                   unconnected_req_half_full;     // 请求缓冲区“半满”（未使用）
  wire                                   unconnected_req_almost_full;   // 请求缓冲区“几乎满”（未使用）
  wire                                   unconnected_req_error;         // 请求缓冲区“错误”（未使用）
  wire                                   unconnected_wdata_almost_empty;// 写数据缓冲区“几乎空”（未使用）
  wire                                   unconnected_wdata_half_full;   // 写数据缓冲区“半满”（未使用）
  wire                                   unconnected_wdata_almost_full; // 写数据缓冲区“几乎满”（未使用）
  wire                                   unconnected_wdata_error;       // 写数据缓冲区“错误”（未使用）
  wire                                   unconnected_resp_almost_empty; // 响应缓冲区“几乎空”（未使用）
  wire                                   unconnected_resp_half_full;    // 响应缓冲区“半满”（未使用）
  wire                                   unconnected_resp_almost_full;  // 响应缓冲区“几乎满”（未使用）
  wire                                   unconnected_resp_error;        // 响应缓冲区“错误”（未使用）

  // --------------------------------------------------------------------------
  // REQUEST PHASE：请求阶段逻辑（核心：接收GIF请求→缓存→转换为AXI请求）
  // 设计思路：通过请求缓冲区、写数据缓冲区解耦GIF与AXI的时序差异；
  //          写突发传输需单独计数，确保首拍与后续拍的接受逻辑一致。
  // --------------------------------------------------------------------------

  // 请求缓冲区读出使能：当AXI读地址或写地址被从设备接受时（arvalid&arready 或 awvalid&awready），
  // 从请求缓冲区弹出一个请求（低有效，故用~取反）
  assign reqb_pop_n = ~((arvalid & arready) | (awvalid & awready));

  // 全局时钟使能域的请求缓冲区写入使能：当GIF有读/写请求（mread^mwrite，确保读/写互斥）、
  // GIF侧写突发未活跃（~wburst_gif_active，首拍才需写请求缓冲区）、且接受请求（saccept）时，
  // 允许写入请求缓冲区（低有效，故用~取反）
  assign reqb_push_gc_n = ~((mread ^ mwrite) & (~wburst_gif_active) & saccept);

  // 请求缓冲区写入使能：仅当全局时钟使能（gclken=1）时，才允许写入（否则保持高电平，禁止写入）
  assign reqb_push_n = (gclken==1'b1) ? reqb_push_gc_n : 1'b1;

  // 请求缓冲区输入数据拼接：将GIF请求的ID、保护属性、缓存属性、读/写使能、突发类型、
  // 传输宽度、突发长度、地址按顺序拼接，总位宽=GM_ID+3+4+1+1+2+3+GM_BW+GM_AW=GM_AW+GM_ID+GM_BW+14
  assign reqb_data_in = {
          mid,        // 高位：GIF请求ID（位宽GM_ID）
          mprot,      // 保护属性（3位）
          mcache,     // 缓存属性（4位）
          mread,      // 读使能（1位）
          mwrite,     // 写使能（1位）
          mburst,     // 突发类型（2位）
          msize,      // 传输宽度（3位）
          mlen,       // 突发长度（位宽GM_BW）
          maddr       // 低位：请求地址（位宽GM_AW）
          };

  // spyglass disable_block W528：工具告警抑制（原因：缓冲区部分辅助端口未使用，无需驱动）
  // SMD: A signal or variable is set but never read. 
  // SJ : BCM组件可配置，本设计未使用“几乎空/半满/错误”端口，故抑制未读信号告警
  // REQUEST BUFFER：实例化请求缓冲区（Synopsys标准FIFO模块DW_axi_gm_bcm65）
  DW_axi_gm_bcm65
   #(
     .DATA_WIDTH(`GM_AW+`GM_ID+`GM_BW+14),  // 缓冲区数据宽度：与reqb_data_in位宽一致
     .DEPTH(`GM_REQ_BUFFER),                 // 缓冲区深度：由GM_REQ_BUFFER宏定义（配置缓存容量）
     .FULL_FLAG(1),                          // 满状态标记使能（1=使能full信号）
     .EMPTY_FLAG(1),                         // 空状态标记使能（1=使能empty信号）
     .ALMOST_FULL_THRESH(`GM_REQ_BUFFER-1),  // “几乎满”阈值：深度-1（未使用）
     .ALMOST_EMPTY_THRESH(0),                // “几乎空”阈值：0（未使用）
     .ADDR_WIDTH(`GM_REQ_BUFFER_AW)          // 缓冲区地址位宽：由GM_REQ_BUFFER_AW宏定义（与深度匹配）
   )
  req_buffer(
             .clk(aclk),                      // 时钟：与AXI时钟同步
             .rst_n(aresetn),                 // 复位：与模块复位同步
             .init_n(1'b1),                   // 初始化：1=不初始化（依赖rst_n复位）
             .push_req_n(reqb_push_n),        // 写入使能：低有效（reqb_push_n）
             .pop_req_n(reqb_pop_n),          // 读出使能：低有效（reqb_pop_n）
             .diag_n(1'b1),                   // 诊断模式：1=禁用诊断
             .data_in(reqb_data_in),          // 输入数据：请求缓冲区输入（reqb_data_in）
             .empty(reqb_empty),              // 输出：缓冲区空状态（reqb_empty）
             .almost_empty(unconnected_req_almost_empty), // 未使用：几乎空
             .half_full(unconnected_req_half_full),        // 未使用：半满
             .almost_full(unconnected_req_almost_full),    // 未使用：几乎满
             .full(reqb_full),                // 输出：缓冲区满状态（reqb_full）
             .error(unconnected_req_error),   // 未使用：错误状态
             .data_out(reqb_data_out)         // 输出数据：请求缓冲区输出（reqb_data_out）
             );
  // spyglass enable_block W528：恢复工具告警检查

  // AXI读地址通道信号：从请求缓冲区输出数据（reqb_data_out）中拆分读地址相关信号
  assign araddr = reqb_data_out[`GM_AW-1:0];  // 读地址：取reqb_data_out最低GM_AW位（对应reqb_data_in的maddr）
  assign arlen = reqb_data_out[`GM_AW+`GM_BW-1:`GM_AW];  // 读突发长度：取GM_AW~GM_AW+GM_BW-1位（对应reqb_data_in的mlen）
  assign arsize = reqb_data_out[`GM_AW+`GM_BW+2:`GM_AW+`GM_BW];  // 读传输宽度：取GM_AW+GM_BW~GM_AW+GM_BW+2位（对应reqb_data_in的msize）
  assign arburst = reqb_data_out[`GM_AW+`GM_BW+4:`GM_AW+`GM_BW+3];  // 读突发类型：取GM_AW+GM_BW+3~GM_AW+GM_BW+4位（对应reqb_data_in的mburst）
  assign arlock = {1'b0};  // 读锁定属性：固定为0（不使用锁定功能）
  assign arcache = reqb_data_out[`GM_AW+`GM_BW+10:`GM_AW+`GM_BW+7];  // 读缓存属性：取GM_AW+GM_BW+7~GM_AW+GM_BW+10位（对应reqb_data_in的mcache）
  assign arprot = reqb_data_out[`GM_AW+`GM_BW+13:`GM_AW+`GM_BW+11];  // 读保护属性：取GM_AW+GM_BW+11~GM_AW+GM_BW+13位（对应reqb_data_in的mprot）
  assign arid = reqb_data_out[`GM_AW+`GM_ID+`GM_BW+13:`GM_AW+`GM_BW+14];  // 读地址ID：取最高GM_ID位（对应reqb_data_in的mid）
  // 读地址有效：请求缓冲区非空（~reqb_empty）且当前请求为读操作（reqb_data_out的mread位为1，对应位：GM_AW+GM_BW+6）
  assign arvalid = ~reqb_empty & reqb_data_out[`GM_AW+`GM_BW+6];

  // AXI写地址通道信号：从请求缓冲区输出数据（reqb_data_out）中拆分写地址相关信号
  assign awaddr = reqb_data_out[`GM_AW-1:0];  // 写地址：与araddr相同（对应reqb_data_in的maddr）
  assign awlen = reqb_data_out[`GM_AW+`GM_BW-1:`GM_AW];  // 写突发长度：与arlen相同（对应reqb_data_in的mlen）
  assign awsize = reqb_data_out[`GM_AW+`GM_BW+2:`GM_AW+`GM_BW];  // 写传输宽度：与arsize相同（对应reqb_data_in的msize）
  assign awburst = reqb_data_out[`GM_AW+`GM_BW+4:`GM_AW+`GM_BW+3];  // 写突发类型：与arburst相同（对应reqb_data_in的mburst）
  assign awlock = {1'b0};  // 写锁定属性：固定为0（不使用锁定功能）
  assign awcache = reqb_data_out[`GM_AW+`GM_BW+10:`GM_AW+`GM_BW+7];  // 写缓存属性：与arcache相同（对应reqb_data_in的mcache）
  assign awprot = reqb_data_out[`GM_AW+`GM_BW+13:`GM_AW+`GM_BW+11];  // 写保护属性：与arprot相同（对应reqb_data_in的mprot）
  assign awid = reqb_data_out[`GM_AW+`GM_ID+`GM_BW+13:`GM_AW+`GM_BW+14];  // 写地址ID：与arid相同（对应reqb_data_in的mid）
  // 写地址有效：请求缓冲区非空（~reqb_empty）且当前请求为写操作（reqb_data_out的mwrite位为1，对应位：GM_AW+GM_BW+5）
  assign awvalid = ~reqb_empty & reqb_data_out[`GM_AW+`GM_BW+5];

  // 请求缓冲区接受能力：请求缓冲区未满（~reqb_full），或虽满但AXI刚接受一个请求（reqb_full&arready&awready，有空闲空间）
  assign saccept_reqb = (~reqb_full | (reqb_full & arready & awready)) ;

  // 全局时钟使能域的写数据缓冲区写入使能：当GIF有写请求（mwrite）且接受请求（saccept）时，
  // 允许写入写数据缓冲区（低有效，故用~取反）
  assign wb_push_gc_n = ~(mwrite & saccept);

  // 写数据缓冲区写入使能：仅当全局时钟使能（gclken=1）时，才允许写入（否则保持高电平，禁止写入）
  assign wb_push_n = (gclken==1'b1) ? wb_push_gc_n : 1'b1;

  // 写数据缓冲区读出使能：当AXI写数据被从设备接受时（wvalid&wready），从写数据缓冲区弹出一个数据（低有效，故用~取反）
  assign wb_pop_n = ~(wvalid & wready);

  // 写数据缓冲区输入数据拼接：将GIF写请求的ID、突发长度、掩码、数据按顺序拼接，
  // 总位宽=GM_ID+GM_BW+GM_WW+GM_DW
  assign wb_data_in = {
          mid,        // 高位：GIF请求ID（位宽GM_ID）
          mlen,       // 突发长度（位宽GM_BW）
          mwstrb,     // 写数据掩码（位宽GM_WW）
          mdata       // 低位：写数据（位宽GM_DW）
          };

  // spyglass disable_block W528：工具告警抑制（原因同请求缓冲区，未使用辅助端口）
  // WRITE DATA BUFFER：实例化写数据缓冲区（Synopsys标准FIFO模块DW_axi_gm_bcm65）
  DW_axi_gm_bcm65
   #(
     .DATA_WIDTH(`GM_ID+`GM_DW+`GM_WW+`GM_BW),  // 缓冲区数据宽度：与wb_data_in位宽一致
     .DEPTH(`GM_WDATA_BUFFER),                  // 缓冲区深度：由GM_WDATA_BUFFER宏定义
     .FULL_FLAG(1),                             // 满状态标记使能
     .EMPTY_FLAG(1),                            // 空状态标记使能
     .ALMOST_FULL_THRESH(`GM_WDATA_BUFFER-1),   // “几乎满”阈值（未使用）
     .ALMOST_EMPTY_THRESH(0),                   // “几乎空”阈值（未使用）
     .ADDR_WIDTH(`GM_WDATA_BUFFER_AW)           // 缓冲区地址位宽：由GM_WDATA_BUFFER_AW宏定义
   )
    wdata_buffer(
              .clk(aclk),                      // 时钟：与AXI时钟同步
              .rst_n(aresetn),                 // 复位：与模块复位同步
              .init_n(1'b1),                   // 初始化：1=不初始化
              .push_req_n(wb_push_n),          // 写入使能：低有效（wb_push_n）
              .pop_req_n(wb_pop_n),            // 读出使能：低有效（wb_pop_n）
              .diag_n(1'b1),                   // 诊断模式：1=禁用
              .data_in(wb_data_in),            // 输入数据：写数据缓冲区输入（wb_data_in）
              .empty(wb_empty),                // 输出：缓冲区空状态（wb_empty）
              .almost_empty(unconnected_wdata_almost_empty), // 未使用：几乎空
              .half_full(unconnected_wdata_half_full),        // 未使用：半满
              .almost_full(unconnected_wdata_almost_full),    // 未使用：几乎满
              .full(wb_full),                  // 输出：缓冲区满状态（wb_full）
              .error(unconnected_wdata_error), // 未使用：错误状态
              .data_out(wb_data_out)           // 输出数据：写数据缓冲区输出（wb_data_out）
              );
  // spyglass enable_block W528：恢复工具告警检查

  // AXI写数据通道信号：从写数据缓冲区输出数据（wb_data_out）中拆分写数据相关信号
  assign wdata = wb_data_out[`GM_DW-1:0];  // 写数据：取wb_data_out最低GM_DW位（对应wb_data_in的mdata）
  assign wstrb = wb_data_out[`GM_DW+`GM_WW-1:`GM_DW];  // 写数据掩码：取GM_DW~GM_DW+GM_WW-1位（对应wb_data_in的mwstrb）
  assign wlen = wb_data_out[`GM_DW+`GM_WW+`GM_BW-1:`GM_DW+`GM_WW];  // 写突发长度：取GM_DW+GM_WW~GM_DW+GM_WW+GM_BW-1位（对应wb_data_in的mlen）
  assign wid = wb_data_out[`GM_ID+`GM_DW+`GM_WW+`GM_BW-1:`GM_DW+`GM_WW+`GM_BW];  // 写数据ID：取最高GM_ID位（对应wb_data_in的mid）
  assign wvalid = ~wb_empty;  // 写数据有效：写数据缓冲区非空（~wb_empty）

  // 写数据缓冲区接受能力：写数据缓冲区未满（~wb_full），或虽满但AXI刚接受一个写数据（wb_full&wready，有空闲空间）
  assign saccept_wb = (~wb_full | (wb_full & wready)) ;

  // --------------------------------------------------------------------------
  // saccept信号生成：组合逻辑，决定是否接受当前GIF请求
  // 设计思路：写突发首拍需同时满足“请求缓冲区+写数据缓冲区就绪”，后续拍仅需“写数据缓冲区就绪”
  // --------------------------------------------------------------------------
  // AUTO_CONSTANT：工具自动生成宏定义（GM_BLOCK_READ/GM_BLOCK_WRITE，本设计未使用，预留）
  always @ (*)
    begin : saccept_reqb_block_PROC  // 块名：saccept_reqb_block的组合逻辑
      // 允许读/写请求阻塞（本设计直接赋值saccept_reqb，无额外阻塞逻辑）
          saccept_reqb_block = saccept_reqb;
    end // always@ (*)

  // lede W456 on：工具告警标记（预留，无实际功能）
  // 组合逻辑：根据GIF侧写突发是否活跃，决定saccept_r的值
  always@(/*AUTOSENSE*/saccept_reqb_block or saccept_wb or wburst_gif_active)
    begin : saccept_r_PROC  // 块名：saccept_r的组合逻辑
      if(wburst_gif_active)  // 若GIF侧写突发正在进行（非首拍）
        begin
          saccept_r = saccept_wb;  // 仅需写数据缓冲区就绪即可接受
        end
      else  // 若为写突发首拍或读请求
        begin
          // 首拍需请求缓冲区+写数据缓冲区同时就绪（避免请求与数据不同步）
          saccept_r = saccept_reqb_block & saccept_wb;
        end
    end // always@ (*)

  assign saccept = saccept_r;  // 输出saccept：直接连接saccept_r（寄存器版本，避免毛刺）

  // --------------------------------------------------------------------------
  // GIF侧写突发计数器：时序逻辑，记录GIF侧写突发已传输的拍数
  // 设计思路：突发开始时从0计数，达到mlen（突发长度）时清零，标识突发结束
  // --------------------------------------------------------------------------
  assign wburst_gif_count_int = wburst_gif_count;  // 线网别名：避免时序逻辑中直接读取寄存器

  always@(posedge aclk or negedge aresetn)  // 同步时钟：aclk上升沿；异步复位：aresetn下降沿
    begin : wburst_gif_count_PROC  // 块名：wburst_gif_count的时序逻辑
      if(~aresetn)  // 复位：计数器清零
        wburst_gif_count <= {(`GM_BW){1'b0}};
      else
        begin
          if(gclken)  // 仅当全局时钟使能（gclken=1）时，计数器才更新
            begin
              // 条件1：计数器已达到突发长度（wburst_gif_count==mlen），且当前为写请求且被接受（mwrite&saccept）
              if((wburst_gif_count==mlen) && (mwrite & saccept))
                begin
                  wburst_gif_count <= {(`GM_BW){1'b0}};  // 突发结束，计数器清零
                end
              // 条件2：当前为写请求且被接受（mwrite&saccept）（未达到突发长度）
              else if(mwrite & saccept)
                begin
                  // 计数器加1（用wburst_gif_count_int避免组合环）
                  wburst_gif_count <= wburst_gif_count_int + {{(`GM_BW-1){1'b0}}, 1'b1} ;
                end
            end // if (gclken)
        end // else: !if(~aresetn)
    end // always@ (posedge aclk or negedge aresetn)

  // GIF侧写突发活跃标记：计数器非零表示突发正在进行（wburst_gif_count != 0）
  assign wburst_gif_active = (wburst_gif_count != {(`GM_BW){1'b0}} );

  // --------------------------------------------------------------------------
  // AXI侧写突发计数器：时序逻辑，记录AXI侧写突发已传输的拍数，生成wlast
  // 设计思路：与GIF侧计数器同步，达到wlen（突发长度）时，wlast=1（最后一拍）
  // --------------------------------------------------------------------------
  assign wburst_axi_count_int = wburst_axi_count;  // 线网别名：避免时序逻辑中直接读取寄存器

  always@(posedge aclk or negedge aresetn)  // 同步时钟：aclk上升沿；异步复位：aresetn下降沿
    begin : wburst_axi_count_PROC  // 块名：wburst_axi_count的时序逻辑
      if(~aresetn)  // 复位：计数器清零
        wburst_axi_count <= {(`GM_BW){1'b0}};
      else
        begin
          // 条件1：计数器已达到突发长度（wburst_axi_count==wlen），且写数据被接受（wready&wvalid）
          if((wburst_axi_count==wlen) && (wready & wvalid))
            begin
              wburst_axi_count <= {(`GM_BW){1'b0}};  // 突发结束，计数器清零
            end
          // 条件2：写数据被接受（wready&wvalid）（未达到突发长度）
          else if(wready & wvalid)
            begin
              // 计数器加1（用wburst_axi_count_int避免组合环）
              wburst_axi_count <= wburst_axi_count_int + {{(`GM_BW-1){1'b0}}, 1'b1};
            end
        end // else: !if(~aresetn)
    end // always@ (posedge aclk or negedge aresetn)

  // AXI写数据最后一拍：计数器达到突发长度时，wlast=1（当前为突发最后一拍）
  assign wlast = (wburst_axi_count==wlen);   

  // -------------------------------------------------------------------
  // RESPONSE PHASE：响应阶段逻辑（核心：接收AXI响应→缓存→转换为GIF响应）
  // 设计思路：通过响应缓冲区解耦AXI与GIF的时序差异；
  //          用bselect轮询处理读/写响应优先级，避免响应阻塞。
  // -------------------------------------------------------------------

  // --------------------------------------------------------------------------
  // 响应选择逻辑：时序逻辑，决定优先处理读响应（R通道）还是写响应（B通道）
  // 设计思路：同时有响应时轮询，仅单一响应时优先处理对应通道，确保响应不丢失
  // --------------------------------------------------------------------------
  always@(posedge aclk or negedge aresetn)  // 同步时钟：aclk上升沿；异步复位：aresetn下降沿
    begin : bselect_PROC  // 块名：bselect的时序逻辑
      if(~aresetn)  // 复位：默认优先处理读响应（bselect=0）
        bselect <= 1'b0;
      else
        begin
          // 情况1：读响应和写响应同时有效（rvalid&bvalid）→ 轮询翻转bselect
          if(rvalid & bvalid)
            begin
              if(bselect)
                bselect <= 1'b0;  // 上一次处理写响应，本次处理读响应
              else
                bselect <= 1'b1;  // 上一次处理读响应，本次处理写响应
            end
          // 情况2：仅写响应有效（bvalid）→ 优先处理写响应（bselect=1）
          else if(bvalid)
            bselect <= 1'b1;
          // 情况3：仅读响应有效（rvalid）或无响应→ 优先处理读响应（bselect=0）
          else
            bselect <= 1'b0;
        end
    end // always@ (posedge aclk or negedge aresetn)

  // --------------------------------------------------------------------------
  // 响应数据拼接：组合逻辑，根据bselect选择读/写响应，拼接为响应缓冲区输入格式
  // 设计思路：统一响应数据格式，便于响应缓冲区缓存，后续统一拆分给GIF
  // --------------------------------------------------------------------------
  always@(/*AUTOSENSE*/bid or bresp or bselect or bvalid or gready or rdata or rid or rlast or rresp or rvalid)
    begin : read_resp_PROC  // 块名：响应数据处理的组合逻辑
      if(bselect)  // 优先处理写响应（bselect=1）
        begin
          // 写响应数据拼接：ID（bid）+ 写响应标记（1'b1）+ 响应状态（bresp）+ 占位符（1'b1）+ 数据（rdata，未使用）
          respb_data_in =  {
          bid,        // 高位：写响应ID（位宽GM_ID）
          1'b1,       // 写响应标记（区分读/写响应：1=写）
          bresp,      // 写响应状态（2位，AXI标准）
          1'b1,       // 占位符（无实际意义，凑位宽）
          rdata       // 低位：数据（未使用，写响应无需数据）
          };
          gvalid = bvalid;  // 响应有效标记：写响应有效（bvalid）
          rready_gc = 1'b0; // 读响应接受使能：0=不接受读响应
          bready_gc = gready; // 写响应接受使能：响应缓冲区就绪（gready）时接受
        end
      else  // 优先处理读响应（bselect=0）
        begin
          // 读响应数据拼接：ID（rid）+ 最后一拍标记（rlast）+ 响应状态（rresp）+ 读响应标记（1'b0）+ 数据（rdata）
          respb_data_in =  {
          rid,        // 高位：读响应ID（位宽GM_ID）
          rlast,      // 读响应最后一拍标记（1位，与AXI的rlast对应）
          rresp,      // 读响应状态（2位，AXI标准）
          1'b0,       // 读响应标记（区分读/写响应：0=读）
          rdata       // 低位：读响应数据（位宽GM_DW）
          };
          gvalid = rvalid;  // 响应有效标记：读响应有效（rvalid）
          rready_gc = gready; // 读响应接受使能：响应缓冲区就绪（gready）时接受
          bready_gc = 1'b0; // 写响应接受使能：0=不接受写响应
        end // else: !if(bselect)
    end

  // --------------------------------------------------------------------------
  // 响应缓冲区控制信号：生成写入/读出使能，与全局时钟使能同步
  // --------------------------------------------------------------------------
  // 全局时钟使能域的响应缓冲区写入使能：响应有效（gvalid）且响应缓冲区就绪（gready）时，允许写入（低有效，故用~取反）
  assign respb_push_gc_n = ~(gvalid & gready);
  // 全局时钟使能域的响应缓冲区读出使能：GIF响应有效（svalid）且GIF接受响应（mready）时，允许读出（低有效，故用~取反）
  assign respb_pop_gc_n = ~(svalid & mready);

  // 响应缓冲区写入使能：仅当全局时钟使能（gclken=1）时，才允许写入（否则保持高电平，禁止写入）
  assign respb_push_n = (gclken==1'b1) ? respb_push_gc_n : 1'b1;
  // 响应缓冲区读出使能：仅当全局时钟使能（gclken=1）时，才允许读出（否则保持高电平，禁止读出）
  assign respb_pop_n = (gclken==1'b1) ? respb_pop_gc_n : 1'b1;  

  // spyglass disable_block W528：工具告警抑制（原因同前，未使用辅助端口）
  // RESPONSE BUFFER：实例化响应缓冲区（Synopsys标准FIFO模块DW_axi_gm_bcm65）
  DW_axi_gm_bcm65
   #(
     .DATA_WIDTH(`GM_DW+`GM_ID+4),  // 缓冲区数据宽度：与respb_data_in位宽一致（GM_DW+GM_ID+4）
     .DEPTH(`GM_RESP_BUFFER),        // 缓冲区深度：由GM_RESP_BUFFER宏定义
     .FULL_FLAG(1),                  // 满状态标记使能
     .EMPTY_FLAG(1),                 // 空状态标记使能
     .ALMOST_FULL_THRESH(`GM_RESP_BUFFER-1),  // “几乎满”阈值（未使用）
     .ALMOST_EMPTY_THRESH(0),        // “几乎空”阈值（未使用）
     .ADDR_WIDTH(`GM_RESP_BUFFER_AW) // 缓冲区地址位宽：由GM_RESP_BUFFER_AW宏定义
   )
      resp_buffer(
              .clk(aclk),                      // 时钟：与AXI时钟同步
              .rst_n(aresetn),                 // 复位：与模块复位同步
              .init_n(1'b1),                   // 初始化：1=不初始化
              .push_req_n(respb_push_n),       // 写入使能：低有效（respb_push_n）
              .pop_req_n(respb_pop_n),         // 读出使能：低有效（respb_pop_n）
              .diag_n(1'b1),                   // 诊断模式：1=禁用
              .data_in(respb_data_in),         // 输入数据：响应缓冲区输入（respb_data_in）
              .empty(respb_empty),             // 输出：缓冲区空状态（respb_empty）
              .almost_empty(unconnected_resp_almost_empty), // 未使用：几乎空
              .half_full(unconnected_resp_half_full),        // 未使用：半满
              .almost_full(unconnected_resp_almost_full),    // 未使用：几乎满
              .full(respb_full),               // 输出：缓冲区满状态（respb_full）
              .error(unconnected_resp_error),  // 未使用：错误状态
              .data_out(respb_data_out)        // 输出数据：响应缓冲区输出（respb_data_out）
              );
  // spyglass enable_block W528：恢复工具告警检查
  // Leda W287 on：工具告警标记（预留，无实际功能）

  // 响应缓冲区接受能力：响应缓冲区未满（~respb_full），或虽满但GIF刚接受一个响应（respb_full&mready，有空闲空间）
  assign gready = (~respb_full | (respb_full & mready)) ;

  // AXI读/写响应接受使能：仅当全局时钟使能（gclken=1）时，才允许接受响应（否则为0，禁止接受）
  assign rready = (gclken==1'b1) ? rready_gc : 1'b0;
  assign bready = (gclken==1'b1) ? bready_gc : 1'b0;  

  // --------------------------------------------------------------------------
  // GIF响应信号生成：从响应缓冲区输出数据（respb_data_out）中拆分GIF响应信号
  // --------------------------------------------------------------------------
  assign svalid = ~respb_empty;  // GIF响应有效：响应缓冲区非空（~respb_empty）
  // GIF响应ID：取respb_data_out最高GM_ID位（对应读响应的rid或写响应的bid）
  assign sid = respb_data_out[`GM_DW+`GM_ID+3:`GM_DW+4];
  // GIF突发响应最后一拍：取respb_data_out的GM_DW+3位（对应读响应的rlast，写响应固定为1）
  assign slast = respb_data_out[`GM_DW+3];
  // GIF响应状态：取respb_data_out的GM_DW~GM_DW+2位（扩展AXI响应为3位，与GIF需求匹配）
  assign sresp = {respb_data_out[`GM_DW+2:`GM_DW]};
  // GIF读响应数据：取respb_data_out最低GM_DW位（对应读响应的rdata，写响应未使用）
  assign sdata = respb_data_out[`GM_DW-1:0];

endmodule  // 模块结束