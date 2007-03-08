
all: check sequence trigger

check: test.ct test_server.tcl run_test.sh
	@echo "# Ready"

sequence: test_sequence.tcl
	./run_test.sh sequence

trigger: test_trigger.tcl
	./run_test.sh trigger

