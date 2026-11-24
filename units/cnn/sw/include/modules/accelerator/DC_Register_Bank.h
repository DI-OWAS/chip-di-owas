#pragma once

namespace DC_ConvNet {

	/**
	 * @brief Simple register bank used by the HW accelerator to track memory accesses.
	 *
	 * The counters in this structure accumulate how many read/write "seeks"
	 * were performed for different tensor categories (weights, biases, inputs,
	 * outputs) during execution. This is mainly intended for performance
	 * analysis and debugging of memory traffic.
	 */
	struct DC_Register_Bank {
		/// Number of memory seeks performed for weight tensors.
		size_t m_weights_on_chip_mem_seeks = 0u;

		/// Number of memory seeks performed for bias tensors.
		size_t m_biases_mem_seeks = 0u;

		/// Per-input-buffer memory seek counters (fixed capacity currently set to 50).
		std::vector<size_t> m_inputs_mem_seeks = std::vector<size_t>(50, 0u);

		/// Number of memory seeks performed for output tensors.
		size_t m_outputs_mem_seeks = 0u;
	};

} // namespace DC_ConvNet
