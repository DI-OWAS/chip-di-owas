#pragma once

#include "DC_CNN_HW_AI_Accelerator.h"
#include "DC_HW_Memory_IF.h"
#include "DC_OffChipMemory.h"
#include "DC_PerformanceStats.h"
#include <vector>

namespace DC_OWAS {

	/**
	 * @struct DC_OWAS_TopLevel
	 * @brief Convenience wrapper that owns the HW accelerator and its memory hierarchy.
	 *
	 * This top-level object wires together off-chip memory, the HW memory interface,
	 * and the CNN HW accelerator. It also tracks per-layer weight/bias/output offsets
	 * within off-chip memory for later use by the accelerator and host code.
	 */
	struct DC_OWAS_TopLevel {

		/**
		 * @brief Construct the top-level OWAS object and initialize accelerator wiring.
		 *
		 * Binds the hardware memory interface to the internal off-chip memory instance
		 * and constructs the CNN HW accelerator on top of that interface.
		 */
		DC_OWAS_TopLevel() :
			m_memory_if(m_off_chip_memory),
			m_cnn_accelerator(m_memory_if){
		}

		/**
		 * @brief Ensure per-layer seek vectors can hold @p layer_count entries.
		 *
		 * Layers without stored weights/biases keep a seek value of 0.
		 */
		void EnsureLayerMemSeekCapacity(size_t layer_count) noexcept {
			if (layer_count > m_weights_mem_seeks.size()) {
				m_weights_mem_seeks.resize(layer_count, 0u);
			}
			if (layer_count > m_biases_mem_seeks.size()) {
				m_biases_mem_seeks.resize(layer_count, 0u);
			}
		}

		/**
		 * @brief Write a layer's weights array to off-chip memory.
		 *
		 * Stores @p mem contiguously at the current @ref m_mem_seek position and
		 * records the starting address in @ref m_weights_mem_seeks for @p layer_id.
		 */
		void WriteWeightsToOffChip(size_t layer_id, const std::vector<float>& mem) noexcept {
			if (layer_id >= m_weights_mem_seeks.size()) {
				m_weights_mem_seeks.resize(layer_id + 1, 0u);
			}

			m_weights_mem_seeks[layer_id] = m_mem_seek;

			m_mem_seek += m_memory_if.Write(m_mem_seek, mem);
		}

		/**
		 * @brief Write a single input tensor to off-chip memory.
		 *
		 * The starting address is stored in @ref m_outputs_mem_seeks at index 0 for
		 * later retrieval by host code or accelerator commands.
		 */
		void WriteInputToOffChip(const std::vector<float>& mem) noexcept {
			if (m_outputs_mem_seeks.empty()) {
				m_outputs_mem_seeks.resize(1, 0u);
			}

			m_outputs_mem_seeks[0] = m_mem_seek;

			m_mem_seek += m_memory_if.Write(m_mem_seek, mem);
		}

		/**
		 * @brief Write an input tensor to off-chip memory for a given buffer slot.
		 *
		 * Currently unimplemented; reserved for multi-buffer input support.
		 */
		void WriteInputsToOffChip(const std::vector<float>& /*mem*/, size_t /*buff_id*/ = 0) noexcept {
		}

		/**
		 * @brief Write a layer's bias array to off-chip memory.
		 *
		 * Stores @p mem contiguously at the current @ref m_mem_seek position and
		 * records the starting address in @ref m_biases_mem_seeks for @p layer_id.
		 */
		void WriteBiasToOffChip(size_t layer_id, const std::vector<float>& mem) noexcept {
			if (layer_id >= m_biases_mem_seeks.size()) {
				m_biases_mem_seeks.resize(layer_id + 1, 0u);
			}

			m_biases_mem_seeks[layer_id] = m_mem_seek;

			m_mem_seek += m_memory_if.Write(m_mem_seek, mem);
		}

		/**
		 * @brief Read a contiguous slice of outputs from off-chip memory.
		 *
		 * @param start_addr   Starting address in off-chip memory.
		 * @param num_elements Number of float elements to read.
		 * @return Vector containing the requested output values.
		 */
		std::vector<float> ReadOutputsFromOffChipByAddr(size_t start_addr, size_t num_elements) const noexcept {
			std::vector<float> output;
			output.reserve(num_elements);
			for (size_t i = start_addr; i < start_addr + num_elements; i++) {
				output.push_back(m_off_chip_memory.Read(i));
			}
			return output;
		}

		/// Access the underlying CNN HW accelerator instance.
		DC_ConvNet::DC_CNN_HW_AI_Accelerator& GetAccelerator() { return m_cnn_accelerator; }

		/// Attach a statistics collector to the underlying accelerator.
		void SetStatsCollector(DC_ConvNet::LayerStats& stats) { m_cnn_accelerator.SetStatsCollector(stats); }

		/// Off-chip memory backing store.
		DC_ConvNet::DC_OffChipMemory m_off_chip_memory;

		/// Hardware-like memory interface used by the accelerator.
		DC_ConvNet::DC_HW_Memory_IF m_memory_if;

		/// CNN HW accelerator instance.
		DC_ConvNet::DC_CNN_HW_AI_Accelerator m_cnn_accelerator;

		/// Global seek pointer for sequential allocations in off-chip memory.
		size_t m_mem_seek = 0u;

		/// Per-layer starting addresses for weights written to off-chip memory.
		std::vector<size_t> m_weights_mem_seeks = std::vector<size_t>(50, 0u);

		/// Per-layer starting addresses for biases written to off-chip memory.
		std::vector<size_t> m_biases_mem_seeks = std::vector<size_t>(50, 0u);

		/// Per-buffer starting addresses for outputs written to off-chip memory.
		std::vector<size_t> m_outputs_mem_seeks = std::vector<size_t>(50, 0u);
	};
}