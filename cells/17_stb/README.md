build.sh: 
    lint rtl
    run simulation
    generate fsdb
    configure DPI
    generate coverage rate report
    generate urg report

build_state_reset.sh
    to cover the transition from the other state to IDLE in the FSM (when reset)

comp.sh
    lint rtl

compare.sh
    the source data is saved in the file sim_output\src.txt
    the destination data is saved in the file sim_output\dst.txt
    compare the data in src.txt and dst.txt



