#pragma once

#include "DC_OffChipMemory.h"

#include <vector>

namespace DC_ConvNet {

	/**
	 * @class DC_HW_Memory_IF
	 * @brief Thin hardware-like interface to the off-chip memory model.
	 *
	 * This class wraps a `DC_OffChipMemory` instance and provides convenience
	 * methods to write contiguous blocks as well as retrieve typed regions
	 * (inputs, weights, biases, outputs) by address and size. It is intended
	 * to mimic a simple HW memory interface for the accelerator model.
	 */
	class DC_HW_Memory_IF final {
	public:
		/**
		 * @brief Construct the memory interface around an existing off-chip memory.
		 * @param off_chip_memory Reference to the external memory model.
		 */
		DC_HW_Memory_IF(DC_OffChipMemory& off_chip_memory);

		/**
		 * @brief Write a contiguous block of floats into off-chip memory.
		 * @param mem_seek Base address (index) in external memory to start writing at.
		 * @param mem      Source data to be written.
		 * @return Number of elements written (i.e., `mem.size()`).
		 */
		size_t Write(size_t mem_seek, const std::vector<float>& mem)
		{
			for (size_t i = 0; i < mem.size(); i++)
				m_off_chip_memory.Write(mem_seek + i, mem[i]);

			return mem.size();
		}

		/**
		 * @brief Read a contiguous block interpreted as input tensor data.
		 * @param addr Base address in external memory.
		 * @param size Number of floats to read.
		 * @return Vector containing the requested input data.
		 */
		std::vector<float> GetOffChipInputByAddr(size_t addr, size_t size);

		/**
		 * @brief Read a contiguous block interpreted as weight tensor data.
		 * @param addr Base address in external memory.
		 * @param size Number of floats to read.
		 * @return Vector containing the requested weights.
		 */
		std::vector<float> GetOffChipWeightsByAddr(size_t addr, size_t size);

		/**
		 * @brief Read a contiguous block interpreted as bias tensor data.
		 * @param addr Base address in external memory.
		 * @param size Number of floats to read.
		 * @return Vector containing the requested biases.
		 */
		std::vector<float> GetOffChipBiasByAddr(size_t addr, size_t size);

		/**
		 * @brief Read a contiguous block interpreted as output tensor data.
		 * @param addr Base address in external memory.
		 * @param size Number of floats to read.
		 * @return Vector containing the requested outputs.
		 */
		std::vector<float> GetOffChipOutputByAddr(size_t addr, size_t size);

		/**
		 * @brief Get a reference to the underlying off-chip buffer.
		 * @return Reference to the raw off-chip memory buffer.
		 */
		std::vector<float>& GetOffChipBuffer();

	private:
		/// Underlying external memory model used for all accesses.
		DC_OffChipMemory& m_off_chip_memory;
	};
}