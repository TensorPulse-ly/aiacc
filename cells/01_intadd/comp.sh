find . -name "*.v" -type f > flist_auto.f
#vcs -full64 +v2k -sverilog -f flist_auto.f -l lint.log +lint=TFIPC-L -notice
vcs -full64 +v2k -sverilog -f flist_auto.f -l lint.log +lint=all,TFIPC-L -error=multiDriven -xzcheck=all -notice +define+FSDB_GENERAL
