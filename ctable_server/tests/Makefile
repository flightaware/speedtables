
all: check trigger methods

check: test.ct test_server.tcl run_test.sh
	@echo "# Ready"

trigger: test_trigger.tcl
	./run_test.sh trigger

methods: test_methods.tcl
	./run_test.sh methods
