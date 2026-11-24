cmake_minimum_required(VERSION 3.10)
project(convnet)

# Target OS and Architecture Selection
# Default OS follows the host so Linux/WSL builds are not silently configured as Window.
if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux")
    set(_DEFAULT_TARGET_OS "Linux")
elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows")
    set(_DEFAULT_TARGET_OS "Window")
else()
    set(_DEFAULT_TARGET_OS "Window")
endif()
set(TARGET_OS "${_DEFAULT_TARGET_OS}" CACHE STRING "Target Operating System (Window, Linux, BareMetal)")
set(TARGET_ARCH "x86_64" CACHE STRING "Target Architecture (x86_64, riscv_32)")

message(STATUS "Configuring build for OS: ${TARGET_OS} | ARCH: ${TARGET_ARCH}")

if(TARGET_OS STREQUAL "Window" AND TARGET_ARCH STREQUAL "x86_64")
    message(STATUS "Selected DEFAULT configuration: Window | x86_64")
    add_compile_definitions(TARGET_OS_WINDOW TARGET_ARCH_X86_64)
elseif(TARGET_OS STREQUAL "Linux" AND TARGET_ARCH STREQUAL "x86_64")
    message(STATUS "Selected configuration: Linux | x86_64")
    add_compile_definitions(TARGET_OS_LINUX TARGET_ARCH_X86_64)
elseif(TARGET_OS STREQUAL "Linux" AND TARGET_ARCH STREQUAL "riscv_32")
    message(STATUS "Selected configuration: Linux | riscv_32 (riscv32-linux-gnu / glibc)")
    add_compile_definitions(TARGET_OS_LINUX TARGET_ARCH_RISCV32)
elseif(TARGET_OS STREQUAL "BareMetal" AND TARGET_ARCH STREQUAL "riscv_32")
    message(STATUS "Selected configuration: BareMetal | riscv_32 (riscv32-unknown-elf / newlib)")
    add_compile_definitions(TARGET_OS_BAREMETAL TARGET_ARCH_RISCV32)
else()
    message(FATAL_ERROR "Unsupported OS | ARCH combination: ${TARGET_OS} | ${TARGET_ARCH}")
endif()

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Set build type if not specified
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Choose the type of build." FORCE)
endif()

# Add compiler warnings
if(MSVC)
else()
    add_compile_options(-Wall -Wextra -Wpedantic)
endif()

# Find Doxygen
find_package(Doxygen)

# Add stb_image
add_library(stb_image INTERFACE)
target_include_directories(stb_image INTERFACE ${CMAKE_CURRENT_SOURCE_DIR}/third_party)

# Collect source files by module
set(LAYER_SOURCES
    src/modules/layers/DC_layer.cpp
    src/modules/layers/DC_CNNLayer_Conv2D.cpp
    src/modules/layers/DC_CNNLayer_MaxPool2D.cpp
    src/modules/layers/DC_CNNLayer_Dense.cpp
    src/modules/layers/DC_CNNLayer_Flatten.cpp
    src/modules/layers/DC_CNNLayer_Upsample.cpp
    src/modules/layers/DC_CNNLayer_Softmax.cpp
    src/modules/layers/DC_CNNLayer_SoftmaxND.cpp
    src/modules/layers/DC_CNNLayer_Route.cpp
    src/modules/layers/DC_CNNLayer_Shortcut.cpp
    src/modules/layers/DC_CNNLayer_AvgPool2D.cpp
    src/modules/layers/DC_CNNLayer_L2Norm.cpp
    src/modules/layers/DC_CNNLayer_Reshape.cpp
    src/modules/layers/DC_CNNLayer_Transpose.cpp
    src/modules/layers/DC_CNNLayer_Relu.cpp
    src/modules/layers/DC_CNNLayer_Gelu.cpp
    src/modules/layers/DC_CNNLayer_Gemm.cpp
    src/modules/layers/DC_CNNLayer_LayerNorm.cpp
    src/modules/layers/DC_CNNLayer_Gather.cpp
    src/modules/layers/DC_CNNLayer_Slice.cpp
    src/modules/layers/DC_CNNLayer_DeConv2D.cpp
    src/modules/layers/DC_CNNLayer_Resize.cpp
    src/modules/layers/DC_CNNLayer_Add.cpp
    src/modules/layers/DC_CNNLayer_Concat.cpp
    src/modules/layers/DC_CNNLayer_MatMul.cpp
    src/modules/layers/DC_CNNLayer_Mul.cpp
    src/modules/layers/DC_CNNLayer_SkipLayerNorm.cpp
)

set(YOLO_SOURCES
    src/modules/layers/DC_CNNLayer_YoloLayer.cpp
)

set(UTILS_SOURCES
    src/modules/utils/DC_image_utils.cpp
    src/modules/utils/DC_config_parser.cpp
    src/modules/utils/DC_network_builder.cpp
    src/modules/utils/DC_weight_loader.cpp
    src/modules/utils/DC_yolo_utils.cpp
    src/modules/utils/DC_depth_utils.cpp
    src/modules/utils/DC_print_utils.cpp
    src/modules/utils/DC_PerformanceStats.cpp
    src/modules/utils/DC_embedded_yolo.cpp
    src/modules/utils/DC_embedded_feature.cpp
)

set(STATS_SOURCES
    src/modules/stats/DC_CNNLayer_Stats.cpp
)

set(NETWORK_SOURCES
    src/modules/DC_CNN_Network.cpp
)

set(FIFO_SOURCES
    src/modules/fifo/DC_FifoCommandBuilder_CNNLayer_Conv2D.cpp
    src/modules/fifo/DC_FifoCommandBuilder_CNNLayer_MaxPool2D.cpp
    src/modules/fifo/DC_FifoCommandBuilder_CNNLayer_Route.cpp
    src/modules/fifo/DC_FifoCommandBuilder_CNNLayer_Upsample.cpp
)

set(ACCELERATOR_SOURCES
    src/modules/accelerator/DC_CNN_HW_AI_Accelerator.cpp
    src/modules/accelerator/DC_CNN_HW_Compute_Engine.cpp
    src/modules/accelerator/DC_CNN_HW_CommandBuilder.cpp
    src/modules/accelerator/DC_CNN_HW_DMA_Engine.cpp
    src/modules/accelerator/DC_HW_Memory_IF.cpp
    src/modules/accelerator/DC_OnChipCompute.cpp
)

# Create library target for shared code
add_library(net_lib STATIC
    ${LAYER_SOURCES}
    ${YOLO_SOURCES}
    ${UTILS_SOURCES}
    ${STATS_SOURCES}
    ${FIFO_SOURCES}
    ${NETWORK_SOURCES}
    ${ACCELERATOR_SOURCES}
)

# Add include directories for the library
target_include_directories(net_lib PUBLIC 
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/include/modules
    ${CMAKE_CURRENT_SOURCE_DIR}/include/modules/tensor
    ${CMAKE_CURRENT_SOURCE_DIR}/include/modules/layers
    ${CMAKE_CURRENT_SOURCE_DIR}/include/modules/utils
    ${CMAKE_CURRENT_SOURCE_DIR}/include/modules/stats
    ${CMAKE_CURRENT_SOURCE_DIR}/include/modules/fifo
    ${CMAKE_CURRENT_SOURCE_DIR}/include/modules/accelerator
    ${CMAKE_CURRENT_SOURCE_DIR}/include/modules/owas_top_level
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party
)

# Bare-metal / sim (DemoApp): warning suppressions for bring-up (CPU path; no HW accelerator).
if(TARGET_OS STREQUAL "BareMetal" AND CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(net_lib PRIVATE
        -Wno-overloaded-virtual
        -Wno-missing-field-initializers
        -Wno-unused-but-set-variable
        -Wno-unused-parameter
        -Wno-maybe-uninitialized
        -Wno-array-bounds
    )
endif()

# Create main executable
add_executable(net src/DC_main.cpp)
target_link_libraries(net PRIVATE net_lib)
target_compile_definitions(net_lib PUBLIC SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(net PUBLIC SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}")
if(TARGET_OS STREQUAL "BareMetal" AND CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(net PRIVATE -Wno-overloaded-virtual)
endif()

# std::filesystem support for GNU toolchains older than GCC 9.
if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU" AND CMAKE_CXX_COMPILER_VERSION VERSION_LESS 9.0)
    target_link_libraries(net PRIVATE stdc++fs)
endif()

# std::filesystem support for GNU toolchains older than GCC 9.
if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU" AND CMAKE_CXX_COMPILER_VERSION VERSION_LESS 9.0)
    target_link_libraries(net PRIVATE stdc++fs)
endif()

# Set output directories
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)

# Configure Doxygen
option(COMPUTE_IN_FIFO_QUEUE "Enable FIFO queue computation mode" OFF)

if(COMPUTE_IN_FIFO_QUEUE)
    add_compile_definitions(COMPUTE_IN_FIFO_QUEUE)
else()
    add_compile_definitions(COMPUTE_IN_LAYERS)
endif()

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/docs/Doxyfile.in")
    set(DOXYGEN_IN ${CMAKE_CURRENT_SOURCE_DIR}/docs/Doxyfile.in)
    set(DOXYGEN_OUT ${CMAKE_CURRENT_BINARY_DIR}/Doxyfile)

    configure_file(${DOXYGEN_IN} ${DOXYGEN_OUT} @ONLY)

    add_custom_target(docs
        COMMAND ${DOXYGEN_EXECUTABLE} ${DOXYGEN_OUT}
        WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
        COMMENT "Generating API documentation with Doxygen"
        VERBATIM
    )
endif()
