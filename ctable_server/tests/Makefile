
all: check trigger

check: test.ct test_server.tcl run_test.sh
	@echo "# Ready"

trigger: test_trigger.tcl
	./run_test.sh trigger

