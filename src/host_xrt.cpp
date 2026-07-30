/**
* Copyright (C) 2019-2021 Xilinx, Inc
*
* Licensed under the Apache License, Version 2.0 (the "License"). You may
* not use this file except in compliance with the License. A copy of the
* License is located at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
* WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
* License for the specific language governing permissions and limitations
* under the License.
*/

#include <iostream>
#include <cstring>
#include <cstdlib>
#include <string>
#include <chrono>
#include <stdexcept>

// Fast file I/O
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

// XRT includes
#include "experimental/xrt_bo.h"
#include "experimental/xrt_ip.h"
#include "experimental/xrt_device.h"
#include "experimental/xrt_kernel.h"
#include "experimental/xrt_xclbin.h"

#define IP_RESET 0x0
#define IP_START 0x1
#define IP_IDLE 0x4
#define IP_DONE 0x2
#define CSR_OFFSET 0x0
#define GIR_OFFSET 0x4

using namespace std;

///////////////////////////////////////////////////////////////////////////////
// Fast file loading: mmap the whole file, then scan the raw bytes directly
// for integers (one per line). Avoids ifstream/stringstream/getline overhead
// entirely — no per-line heap allocations, no locale-aware parsing.
///////////////////////////////////////////////////////////////////////////////

struct MappedFile {
    const char* data = nullptr;
    size_t      size = 0;
    int         fd   = -1;
};

static MappedFile map_file(const std::string& path) {
    MappedFile mf;
    mf.fd = open(path.c_str(), O_RDONLY);
    if (mf.fd < 0) {
        throw std::runtime_error("Failed to open file: " + path);
    }

    struct stat st;
    if (fstat(mf.fd, &st) < 0) {
        close(mf.fd);
        throw std::runtime_error("fstat failed for file: " + path);
    }
    mf.size = static_cast<size_t>(st.st_size);

    if (mf.size == 0) {
        close(mf.fd);
        throw std::runtime_error("File is empty: " + path);
    }

    void* addr = mmap(nullptr, mf.size, PROT_READ, MAP_PRIVATE, mf.fd, 0);
    if (addr == MAP_FAILED) {
        close(mf.fd);
        throw std::runtime_error("mmap failed for file: " + path);
    }

    // Hint the kernel we'll read this sequentially, start to finish.
    madvise(addr, mf.size, MADV_SEQUENTIAL);

    mf.data = static_cast<const char*>(addr);
    return mf;
}

static void unmap_file(MappedFile& mf) {
    if (mf.data) munmap(const_cast<char*>(mf.data), mf.size);
    if (mf.fd >= 0) close(mf.fd);
    mf.data = nullptr;
    mf.fd = -1;
}

// Counts how many integer tokens are present (one pass, no conversion).
static size_t count_integers(const char* data, size_t size) {
    size_t count = 0;
    size_t i = 0;
    while (i < size) {
        while (i < size && (data[i] < '0' || data[i] > '9') && data[i] != '-') i++;
        if (i >= size) break;
        count++;
        if (data[i] == '-') i++;
        while (i < size && data[i] >= '0' && data[i] <= '9') i++;
    }
    return count;
}

// Parses integer tokens directly into dst. Returns number parsed.
// dst must have capacity for at least count_integers(data, size) entries.
static size_t parse_integers(const char* data, size_t size, int* dst) {
    size_t count = 0;
    size_t i = 0;
    while (i < size) {
        while (i < size && (data[i] < '0' || data[i] > '9') && data[i] != '-') i++;
        if (i >= size) break;

        bool neg = false;
        if (data[i] == '-') { neg = true; i++; }

        long val = 0;
        while (i < size && data[i] >= '0' && data[i] <= '9') {
            val = val * 10 + (data[i] - '0');
            i++;
        }
        dst[count++] = neg ? -static_cast<int>(val) : static_cast<int>(val);
    }
    return count;
}

// Standard 2-way merge (as in the merge step of merge sort). Assumes both
// src_a[0..n_a) and src_b[0..n_b) are individually sorted in ascending
// order; produces a single ascending-sorted sequence of length n_a + n_b
// in dst.
static void merge_sorted(const int* src_a, size_t n_a,
                          const int* src_b, size_t n_b,
                          int* dst) {
    size_t i = 0, j = 0, k = 0;
    while (i < n_a && j < n_b) {
        dst[k++] = (src_a[i] <= src_b[j]) ? src_a[i++] : src_b[j++];
    }
    while (i < n_a) dst[k++] = src_a[i++];
    while (j < n_b) dst[k++] = src_b[j++];
}

int main(int argc, char** argv) {

    ios::sync_with_stdio(false);
    cin.tie(nullptr);

    using namespace std::chrono;

    //if (argc < 3) {
    if (argc < 4) {
        //std::cerr << "Usage: " << argv[0] << " <file_a> <file_b> " << std::endl;
        std::cerr << "Usage: " << argv[0] << " <file_a> <file_b> <xclbin_file>" << std::endl;
        std::cerr << "  Each file must contain one integer per line." << std::endl;
        return EXIT_FAILURE;
    }

    std::string file_a = argv[1];
    std::string file_b = argv[2];

    int device_index = 0;

    std::cout << "Open the device" << device_index << std::endl;
    auto device = xrt::device(device_index);
    std::cout << "Load the xclbin " << "merge.xclbin" << std::endl;
    //std::string filename = "/home/smarques/rtl_merge_v1.0.1/build_dir.hw_emu.xilinx_u50_gen3x16_xdma_5_202210_1/merge.link.xclbin";
    //std::string filename = "/home/smarques/rtl_merge_v1.0.1/build_dir.hw.xilinx_u55c_gen3x16_xdma_3_202210_1/merge.xclbin";
    std::string filename = argv[3];
    //std::string filename = "/home/smarques/rtl_merge_v1.0.1/build_dir.hw_emu.xilinx_u55c_gen3x16_xdma_3_202210_1/merge.xclbin";
    //auto uuid = device.load_xclbin("/home/smarques/rtl_merge_v1.0.1/build_dir.hw_emu.xilinx_u50_gen3x16_xdma_5_202210_1/merge.link.xclbin");
    //auto uuid = device.load_xclbin("/home/smarques/rtl_merge_v1.0.1/build_dir.hw.xilinx_u55c_gen3x16_xdma_3_202210_1/merge.xclbin");
    //auto uuid = device.load_xclbin("/home/smarques/rtl_merge_v1.0.1/build_dir.hw_emu.xilinx_u55c_gen3x16_xdma_3_202210_1/merge.xclbin");
    auto uuid = device.load_xclbin(filename);

    std::cout << "After Load the xclbin " << "merge.xclbin" << std::endl;

    // ---------------------------------------------------------------------
    // Load input files (mmap + manual scan for max read/parse throughput)
    // ---------------------------------------------------------------------
    std::cout << "Reading input file A: " << file_a << std::endl;
    MappedFile mf_a = map_file(file_a);
    std::cout << "Reading input file B: " << file_b << std::endl;
    MappedFile mf_b = map_file(file_b);

    // Distinct variables holding the number of values read from each file.
    size_t num_values_a = count_integers(mf_a.data, mf_a.size);
    size_t num_values_b = count_integers(mf_b.data, mf_b.size);

    std::cout << "Values found in file A: " << num_values_a << std::endl;
    std::cout << "Values found in file B: " << num_values_b << std::endl;

    if (num_values_a == 0 || num_values_b == 0) {
        unmap_file(mf_a);
        unmap_file(mf_b);
        throw std::runtime_error("One or both input files contain no values");
    }
    /*if (num_values_a != num_values_b) {
        unmap_file(mf_a);
        unmap_file(mf_b);
        throw std::runtime_error("Input files contain a different number of values ("
                                  + std::to_string(num_values_a) + " vs "
                                  + std::to_string(num_values_b) + ")");
    }*/

    size_t vector_size_bytes_a  = sizeof(int) * num_values_a;
    size_t vector_size_bytes_b  = sizeof(int) * num_values_b;
    size_t vector_size_bytes2   = vector_size_bytes_a + vector_size_bytes_b;
    std::cout << "vector_size_bytes_a " << vector_size_bytes_a << std::endl;
    std::cout << "vector_size_bytes_b " << vector_size_bytes_b << std::endl;

    xrt::xclbin::mem mem_used;
    xrt::xclbin::kernel kernel_used;

    std::vector<xrt::xclbin::ip> cu;
    auto ip = xrt::ip(device, uuid, "krnl_merge_rtl");

    //std::string filename = "/home/smarques/rtl_user_managed/build_dir.hw_emu.xilinx_u50_gen3x16_xdma_5_202210_1/merge.link.xclbin";
    auto xclbin = xrt::xclbin(filename);

    std::cout << "Fetch compute Units" << std::endl;
    for (auto& kernel : xclbin.get_kernels()) {
        if (kernel.get_name() == "krnl_merge_rtl") {
            cu = kernel.get_cus();
        }
    }

    if (cu.empty()) throw std::runtime_error("IP krnl_merge_rtl not found in the provided xclbin");

    std::cout << "Determine memory index\n";
    for (auto& mem : xclbin.get_mems()) {
        if (mem.get_used()) {
            mem_used = mem;
            break;
        }
    }

    std::cout << "Allocate Buffer in Global Memory\n";
    auto bo0    = xrt::bo(device, vector_size_bytes_a, mem_used.get_index());
    auto bo1    = xrt::bo(device, vector_size_bytes_b, mem_used.get_index());
    auto bo_out = xrt::bo(device, vector_size_bytes2,  mem_used.get_index());

    // Map the contents of the buffer object into host memory
    auto bo0_map    = bo0.map<int*>();
    auto bo1_map    = bo1.map<int*>();
    auto bo_out_map = bo_out.map<int*>();

    // ---------------------------------------------------------------------
    // Parse directly into the device-mapped host buffers — no intermediate
    // std::vector copy.
    // ---------------------------------------------------------------------
    auto t_parse_start = high_resolution_clock::now();
    parse_integers(mf_a.data, mf_a.size, bo0_map);
    parse_integers(mf_b.data, mf_b.size, bo1_map);
    auto t_parse_end = high_resolution_clock::now();
    std::cout << "Parsed input files in "
              << duration_cast<microseconds>(t_parse_end - t_parse_start).count()
              << " us" << std::endl;

    unmap_file(mf_a);
    unmap_file(mf_b);

    // CPU-side reference: bo0_map and bo1_map merged into a single
    // ascending-sorted sequence (as in the merge step of merge sort).
    // Assumes each input file is itself already sorted in ascending order.
    std::vector<int> bufReference(num_values_a + num_values_b);
    merge_sorted(bo0_map, num_values_a, bo1_map, num_values_b, bufReference.data());

    std::cout << "loaded the data" << std::endl;
    uint64_t buf_addr[3];
    buf_addr[0] = bo0.address();
    buf_addr[1] = bo1.address();
    buf_addr[2] = bo_out.address();

    // Synchronize buffer content with device side
    std::cout << "synchronize input buffer data to device global memory\n";
    bo0.sync(XCL_BO_SYNC_BO_TO_DEVICE);
    bo1.sync(XCL_BO_SYNC_BO_TO_DEVICE);

    std::cout << "INFO: Setting IP Data" << std::endl;

    auto args = cu[0].get_args();

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

    uint32_t axi_ctrl = 0;
    uint32_t val = 0;

    std::cout << "INFO: IP Start" << std::endl;
    axi_ctrl = IP_START;
    ip.write_register(CSR_OFFSET, axi_ctrl);
        /*std::cout << "axi_ctrl ------------>> " << axi_ctrl << std::endl;
        val = ip.read_register(0x44);
        std::cout << "data0 state ------------>> " << val << std::endl;
        val = ip.read_register(0x48);
        std::cout << "data1 start ------------>> " << val << std::endl;
        val = ip.read_register(0x4c);
        std::cout << "data2 end_data_processing ------------>> " << val << std::endl;
        val = ip.read_register(0x50);
        std::cout << "data3 vtotal0 ------------>> " << val << std::endl;
        val = ip.read_register(0x54);
        std::cout << "data4 vtotal1 ------------>> " << val << std::endl;
        val = ip.read_register(0x58);
        std::cout << "data5 end_data_ingestion ------------>> " << val << std::endl;
        val = ip.read_register(0x5c);
        std::cout << "data6 end_data_ingestion1 ------------>> " << val << std::endl;
        val = ip.read_register(0x60);
        std::cout << "data7 wr_fifo_tdata_a ------------>> " << val << std::endl;
        val = ip.read_register(0x64);
        std::cout << "data8 wr_fifo_tdata_b ------------>> " << val << std::endl;
*/

    // Wait until the IP is DONE
    axi_ctrl = 0;
    //while ((axi_ctrl & IP_IDLE) != IP_IDLE) {
    size_t sync_size = 512 * sizeof(uint32_t);
    //size_t my_offset = xq_offset * sizeof(uint32_t);
    size_t my_offset = 0 * sizeof(uint32_t);
    while ((axi_ctrl & IP_DONE) != IP_DONE) {
        axi_ctrl = ip.read_register(CSR_OFFSET);
	std::cout << "axi_ctrl ------------>> " << axi_ctrl << std::endl;
	val = ip.read_register(0x44);
	//if(val==4) break;
        std::cout << "data0 ------------>> " << val << std::endl;
        val = ip.read_register(0x48);
        std::cout << "data1 ------------>> " << val << std::endl;
        val = ip.read_register(0x4c);
        std::cout << "data2 ------------->> " << val << std::endl;
        val = ip.read_register(0x50);
        std::cout << "data3 ------------->> " << val << std::endl;
        val = ip.read_register(0x54);
        std::cout << "data4 ------------->> " << val << std::endl;
        val = ip.read_register(0x58);
        std::cout << "data5 ------------->> " << val << std::endl;
        val = ip.read_register(0x5c);
        std::cout << "data6 ------------->> " << val << std::endl;
        val = ip.read_register(0x60);
        std::cout << "data7 ------------->> " << val << std::endl;
        val = ip.read_register(0x64);
        std::cout << "data8 ------------->> " << val << std::endl;
        val = ip.read_register(0x68);
        std::cout << "data9 ------------->> " << val << std::endl;
        val = ip.read_register(0x6c);
        std::cout << "data10 ------------>> " << val << std::endl;
        val = ip.read_register(0x70);
        std::cout << "data11 ------------>> " << val << std::endl;
        val = ip.read_register(0x74);
        std::cout << "data12 ------------>> " << val << std::endl;
        val = ip.read_register(0x78);
        std::cout << "data13 ------------>> " << val << std::endl;
        val = ip.read_register(0x7c);
        std::cout << "data14 ------------>> " << val << std::endl;
        val = ip.read_register(0x80);
        std::cout << "data15 ------------>> " << val << std::endl;
    
    }

    std::cout << "INFO: IP Done" << std::endl;

    // Get the output
    std::cout << "Get the output data from the device" << std::endl;
    bo_out.sync(XCL_BO_SYNC_BO_FROM_DEVICE);

    std::cout << "Errors------------" << std::endl;
    for (size_t i = 0; i < num_values_a + num_values_b; ++i) {
	if (bo_out_map[i] != bufReference[i])
	   std::cout << "Err: --> "<< i << " - " << bo_out_map[i] << " - " << bufReference[i] << std::endl;
    }
    std::cout << "Merged------------" << std::endl;
    for (size_t i = 0; i < num_values_a + num_values_b; ++i) {
    //for (size_t i = 0; i < num_values_a; ++i) {
        std::cout << bo_out_map[i];
        if ((i % 32) == 0)
            std::cout << std::endl;
        else
            std::cout << ",";
    }
    std::cout << "---------------" << std::endl;

    // Validate our results
    if (std::memcmp(bo_out_map, bufReference.data(), vector_size_bytes2)) {
        throw std::runtime_error("Value read back does not match reference");
    }

    std::cout << "TEST PASSED\n";
    return 0;
}
