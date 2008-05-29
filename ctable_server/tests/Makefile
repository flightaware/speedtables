
all: check test

check: test.ct test_server.tcl run_test.sh
	@echo "# Ready"

test: test_trigger.tcl test_methods.tcl test_restart.tcl
	./run_test.sh trigger methods restart

trigger: test_trigger.tcl
	./run_test.sh trigger

methods: test_methods.tcl
	./run_test.sh methods

restart: test_restart.tcl
	./run_test.sh restart
