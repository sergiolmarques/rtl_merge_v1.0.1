VIVADO := $(XILINX_VIVADO)/bin/vivado
$(TEMP_DIR)/merge.xo: scripts/package_kernel.tcl scripts/gen_xo.tcl src/hdl/*.sv src/hdl/*.v 
	mkdir -p $(TEMP_DIR)
	$(VIVADO) -mode batch -source scripts/gen_xo.tcl -tclargs $(TEMP_DIR)/merge.xo merge $(TARGET) $(PLATFORM) $(XSA)
