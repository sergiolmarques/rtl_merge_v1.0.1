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
#include "xcl2.hpp"
#include <vector>

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

#define DATA_SIZE 256

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
    //if (argc != 2) {
    if (argc < 4) {
        //std::cout << "Usage: " << argv[0] << " <XCLBIN File>" << std::endl;
        std::cerr << "Usage: " << argv[0] << " <file_a> <file_b> <xclbin_file>" << std::endl;
        std::cerr << "  Each file must contain one integer per line." << std::endl;
        return EXIT_FAILURE;
    }

    std::string file_a = argv[1];
    std::string file_b = argv[2];
    std::string binaryFile = argv[3];

    cl_int err;
    cl::CommandQueue q;
    cl::Context context;
    cl::Kernel krnl_merge;
    auto size = DATA_SIZE;
    // Allocate Memory in Host Memory
    auto vector_size_bytes = sizeof(int) * size;
    
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

    size_t vector_size_bytes_a  = sizeof(int) * num_values_a;
    size_t vector_size_bytes_b  = sizeof(int) * num_values_b;
    size_t vector_size_bytes2   = vector_size_bytes_a + vector_size_bytes_b;
    std::cout << "vector_size_bytes_a " << vector_size_bytes_a << std::endl;
    std::cout << "vector_size_bytes_b " << vector_size_bytes_b << std::endl;
    // ---------------------------------------------------------------------
    // End Load input files
    // ---------------------------------------------------------------------
        
    std::vector<int, aligned_allocator<int> > source_input1(vector_size_bytes_a);
    std::vector<int, aligned_allocator<int> > source_input2(vector_size_bytes_b);
    std::vector<int, aligned_allocator<int> > source_hw_results(vector_size_bytes2);
    std::vector<int, aligned_allocator<int> > source_sw_results(vector_size_bytes2);

    // ---------------------------------------------------------------------
    // Parse directly into the device-mapped host buffers — no intermediate
    // std::vector copy.
    // ---------------------------------------------------------------------
    auto t_parse_start = high_resolution_clock::now();
    //load_input_files(file_a, file_b, source_in1, source_in2);
    parse_integers(mf_a.data, mf_a.size, source_in1.data());
    parse_integers(mf_b.data, mf_b.size, source_in2.data());
    auto t_parse_end = high_resolution_clock::now();
    std::cout << "Parsed input files in "
              << duration_cast<microseconds>(t_parse_end - t_parse_start).count()
              << " us" << std::endl;
    //unmap_file(mf_a);
    //unmap_file(mf_b);
    // ------------------------------------------------------------------------
    // End Parse directly into the device-mapped host buffers — no intermediate
    // std::vector copy.
    // ------------------------------------------------------------------------


    // Create the test data and Software Result
    //for (int i = 0; i < size; i++) {
    //    source_input1[i] = i;
    //    source_input2[i] = i;
    //    source_sw_results[i] = source_input1[i] + source_input2[i];
    //    source_hw_results[i] = 0;
    //}
    merge_sorted(source_in1.data(), num_values_a, source_in2.data(), num_values_b, source_sw_results);

    // OPENCL HOST CODE AREA START
    // Create Program and Kernel
    auto devices = xcl::get_xil_devices();

    // read_binary_file() is a utility API which will load the binaryFile
    // and will return the pointer to file buffer.
    auto fileBuf = xcl::read_binary_file(binaryFile);
    cl::Program::Binaries bins{{fileBuf.data(), fileBuf.size()}};
    bool valid_device = false;
    for (unsigned int i = 0; i < devices.size(); i++) {
        auto device = devices[i];
        // Creating Context and Command Queue for selected Device
        OCL_CHECK(err, context = cl::Context(device, nullptr, nullptr, nullptr, &err));
        OCL_CHECK(err, q = cl::CommandQueue(context, device, CL_QUEUE_PROFILING_ENABLE, &err));

        std::cout << "Trying to program device[" << i << "]: " << device.getInfo<CL_DEVICE_NAME>() << std::endl;
        cl::Program program(context, {device}, bins, nullptr, &err);
        if (err != CL_SUCCESS) {
            std::cout << "Failed to program device[" << i << "] with xclbin file!\n";
        } else {
            std::cout << "Device[" << i << "]: program successful!\n";
            OCL_CHECK(err, krnl_merge = cl::Kernel(program, "krnl_merge_rtl", &err));
            valid_device = true;
            break; // we break because we found a valid device
        }
    }
    if (!valid_device) {
        std::cout << "Failed to program any device found, exit!\n";
        exit(EXIT_FAILURE);
    }

    // Allocate Buffer in Global Memory
    OCL_CHECK(err, cl::Buffer buffer_r1(context, CL_MEM_USE_HOST_PTR | CL_MEM_READ_ONLY, vector_size_bytes,
                                        source_input1.data(), &err));
    OCL_CHECK(err, cl::Buffer buffer_r2(context, CL_MEM_USE_HOST_PTR | CL_MEM_READ_ONLY, vector_size_bytes,
                                        source_input2.data(), &err));
    OCL_CHECK(err, cl::Buffer buffer_w(context, CL_MEM_USE_HOST_PTR | CL_MEM_WRITE_ONLY, vector_size_bytes,
                                       source_hw_results.data(), &err));

    // Set the Kernel Arguments
    OCL_CHECK(err, err = krnl_merge.setArg(0, buffer_r1));
    OCL_CHECK(err, err = krnl_merge.setArg(1, buffer_r2));
    OCL_CHECK(err, err = krnl_merge.setArg(2, buffer_w));
    //OCL_CHECK(err, err = krnl_merge.setArg(3, size));
    OCL_CHECK(err, err = krnl_vector_merge.setArg(3, (uint32_t)num_values_a)); //size
    OCL_CHECK(err, err = krnl_vector_merge.setArg(4, (uint32_t)num_values_b)); //size

    // Copy input data to device global memory
    OCL_CHECK(err, err = q.enqueueMigrateMemObjects({buffer_r1, buffer_r2}, 0 /* 0 means from host*/));

    // Launch the Kernel
    OCL_CHECK(err, err = q.enqueueTask(krnl_merge));

    // Copy Result from Device Global Memory to Host Local Memory
    OCL_CHECK(err, err = q.enqueueMigrateMemObjects({buffer_w}, CL_MIGRATE_MEM_OBJECT_HOST));
    OCL_CHECK(err, err = q.finish());

    // OPENCL HOST CODE AREA END

    // Compare the results of the Device to the simulation
    int match = 0;
    for (int i = 0; i < num_values_a + num_values_b; i++) {
    //for (int i = 0; i < size; i++) {
        if (source_hw_results[i] != source_sw_results[i]) {
            std::cout << "Error: Result mismatch" << std::endl;
            std::cout << "i = " << i << " Software result = " << source_sw_results[i]
                      << " Device result = " << source_hw_results[i] << std::endl;
            match = 1;
            break;
        }
    }
   std::cout << "source_in1------------" << std::endl;
    for (int i = 0; i < num_values_a; i++) {
        std::cout << source_in1[i];
        if ((i % 32) == 0)
            std::cout << std::endl;
        else
            std::cout << ",";
    }
    std::cout << "---------------" << std::endl;
    std::cout << "source_in2------------" << std::endl;
    for (int i = 0; i < num_values_b; i++) {
        std::cout << source_in2[i];
        if ((i % 32) == 0)
            std::cout << std::endl;
        else
            std::cout << ",";
    }
    std::cout << "---------------" << std::endl;
    std::cout << "Merged sw------------" << std::endl;
    for (int i = 0; i < num_values_a + num_values_b; i++) {
        std::cout << source_sw_results[i];
        if ((i % 32) == 0)
            std::cout << std::endl;
        else
            std::cout << ",";
    }
    std::cout << "---------------" << std::endl;
    for (int i = 0; i < num_values_a + num_values_b; i++)
            std::cout << source_hw_results[i] << " ";
    std::cout << std::endl;
    std::cout << "Merged hw------------" << std::endl;
    for (int i = 0; i < num_values_a + num_values_b; i++) {
        std::cout << source_hw_results[i];
        if ((i % 32) == 0)
            std::cout << std::endl;
        else
            std::cout << ",";
    }
    std::cout << "---------------" << std::endl;

    std::cout << "TEST " << (match ? "FAILED" : "PASSED") << std::endl;
    return (match ? EXIT_FAILURE : EXIT_SUCCESS);
}
