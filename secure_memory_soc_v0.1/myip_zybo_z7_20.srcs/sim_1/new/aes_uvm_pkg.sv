// aes_uvm_pkg.sv
`ifndef AES_UVM_PKG_SV
`define AES_UVM_PKG_SV

package aes_uvm_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // 선언 순서가 중요! 의존성 순서대로
    `include "aes_seq_item.sv"
    `include "aes_sequence.sv"
    `include "aes_driver.sv"
    `include "aes_monitor.sv"
    `include "aes_scoreboard.sv"
    `include "aes_env.sv"
    `include "aes_test.sv"

endpackage

`endif
