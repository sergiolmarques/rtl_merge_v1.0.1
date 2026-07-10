# rtl_merge_v1.0.1

# Arrays Merge with Hardware Acceleration

Combine two sorted contiguous arrays into a single, cohesive sorted vector.

## Kernel rtl_merge_v1.0 type

### Port Description

| Signal Name		| Interface		| Signal Type	| Init Status	| Description	    |
| :------------ | :------------ | :------------ | :------------ | :------------ |
| ap_clk				| Clock			| I				|				| Clock signal		|
| ap_rst_n			| Reset			| I				|				| Active low reset	|
| m_axi_gmem_*		 	| AXI4 manager interface				| I/O				|				|  
| m_axi_gmem1_*		 	| AXI4 manager interface				| I/O				|				|  
| s_axi_control_*		 	| AXI4-lite subordinate interface				| I/O				|				|  

## Host

```
// Allocate Buffer in Global Memory
auto bo0    = xrt::bo(device, vector_size_bytes_a, mem_used.get_index());
auto bo1    = xrt::bo(device, vector_size_bytes_b, mem_used.get_index());
auto bo_out = xrt::bo(device, vector_size_bytes2,  mem_used.get_index());

// Map the contents of the buffer object into host memory
auto bo0_map = bo0.map<int*>();
auto bo1_map    = bo1.map<int*>();
auto bo_out_map = bo_out.map<int*>();

// Upload dataset to bo0_map and bo1_map

// Synchronize buffer content with device side
bo0.sync(XCL_BO_SYNC_BO_TO_DEVICE);
bo1.sync(XCL_BO_SYNC_BO_TO_DEVICE);

// Setting IP Data
auto args = cu[0].get_args();

uint64_t buf_addr[2];
// Get the buffer physical address
buf_addr[0] = bo0.address();
buf_addr[1] = bo1.address();
buf_addr[2] = bo_out.address();

std::cout << "Setting the 1st Register \"a\" (Input Address)" << std::endl;
ip.write_register(args[0].get_offset(), buf_addr[0]);
ip.write_register(args[0].get_offset() + 4, buf_addr[0] >> 32);

std::cout << "Setting the 2nd Register \"b\" (Input Address)" << std::endl;
ip.write_register(args[1].get_offset(), buf_addr[1]);
ip.write_register(args[1].get_offset() + 4, buf_addr[1] >> 32);

std::cout << "Setting the 3rd Register \"c\" (Output Address)" << std::endl;
ip.write_register(args[2].get_offset(), buf_addr[2]);
ip.write_register(args[2].get_offset() + 4, buf_addr[2] >> 32);

std::cout << "Setting the 4th Register \"length_r\"" << std::endl;
ip.write_register(args[3].get_offset(), static_cast<uint32_t>(num_values_a));

std::cout << "Setting the 5th Register \"length_r1\"" << std::endl;
ip.write_register(args[4].get_offset(), static_cast<uint32_t>(num_values_b));

std::cout << "IP Start" << std::endl;
axi_ctrl = IP_START;
ip.write_register(CSR_OFFSET, axi_ctrl);

axi_ctrl = 0;
// Two ways: spin lock or read interrupt request 
while ((axi_ctrl & IP_IDLE) != IP_IDLE) {
    axi_ctrl = ip.read_register(CSR_OFFSET);
}

std::cout << "Get the output data from the device" << std::endl;
bo_out.sync(XCL_BO_SYNC_BO_FROM_DEVICE);

// Merged array is stored in bo_out_map
```

