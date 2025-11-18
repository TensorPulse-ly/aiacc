find . -name "*.v" -o -name "*.vh" -type f > flist_auto.f
#vcs -full64 +v2k -sverilog -f flist_auto.f -l lint.log +lint=TFIPC-L -notice
vcs -full64 +v2k -sverilog -f flist_auto.f -l lint.log +lint=all,TFIPC-L -error=multiDriven -xzcheck=all -notice +incdir+./vsrc +define+FSDB_GENERAL
# vcs -cc gcc-4 -LDFLAGS -Wl,--no-as-needed -full64 +v2k -kdb  -sverilog -debug_access+all -f flist_auto.f -l compiler.log +lint=TFIPC-L +define+SYNTHESIS +warn=multiDriver+output+noopAssign+OBSV2C -override_timescale=1ns/1ps
# vcs -LDFLAGS -Wl,--no-as-needed -full64 +v2k -kdb  -sverilog -debug_access+all -f flist_auto.f -l compiler.log +lint=TFIPC-L +define+SYNTHESIS +warn=multiDriver -override_timescale=1ns/1ps

#vcs -LDFLAGS -Wl,--no-as-needed -full64 +v2k -kdb -sverilog -debug_access+all -f flist_auto.f -l compiler.log +lint=TFIPC-L +define+SYNTHESIS -wall -override_timescale=1ns/1psPDW_axi_gs_all_includes.vh