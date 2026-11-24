/******************************************************************************
 * @file    DC_CNN_HW_Command.h
 * @authors Oleksandr Karpenko
 *          DC Vision Systems GmbH
 * @brief   Abstract base for hardware accelerator FIFO commands
 * @version 1.0.0
 * @date    2026-07-01
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Copyright (c) 2025 DC Vision Systems GmbH
 ******************************************************************************/

#pragma once

#include <vector>

namespace DC_ConvNet {

	/**
	 * @brief Opcode identifying the accelerator instruction encoded in a command
	 */
	enum class InstructionType {
		LOAD_ON_CHIP_WEIGHTS,   /**< DMA load weights into on-chip memory */
		LOAD_ON_CHIP_INPUTS,    /**< DMA load input feature map into on-chip memory */
		LOAD_ON_CHIP_BIASES,    /**< DMA load bias terms into on-chip memory */
		RESET_ON_CHIP_MEMORY,   /**< Clear / reset on-chip buffers */
		STORE_OFF_CHIP_OUTPUTS, /**< DMA store results back to off-chip memory */
		COMPUTE_CONV,           /**< Run convolution compute kernel */
		COMPUTE_MAX_POOL,       /**< Run max-pooling compute kernel */
		COMPUTE_DENSE,          /**< Run dense / fully-connected compute kernel */
		COMPUTE_ROUTE,          /**< Run route / concat-style data movement */
		COMPUTE_UPSAMPLE,       /**< Run upsample compute kernel */
		IDLE                    /**< No-op / idle instruction */
	};

	/**
	 * @brief Polymorphic HW command with type tag and binary serialization
	 *
	 * Concrete subclasses encode accelerator instructions that are pushed into
	 * the hardware FIFO after serialize().
	 */
	class DC_CNN_HW_Command	{
	public:
		virtual ~DC_CNN_HW_Command() = default;

		/**
		 * @brief Serialize this command to a byte stream for the HW FIFO interface
		 *
		 * @return std::vector<unsigned char> Encoded command bytes
		 */
		virtual std::vector<unsigned char> serialize() const = 0;

		/**
		 * @brief Return the instruction opcode for this command
		 *
		 * @return InstructionType Instruction type tag
		 */
		InstructionType get_instruction_type() const noexcept { return m_instruction_type; }

	protected:
		/**
		 * @brief Construct a command with the given instruction type
		 *
		 * @param type Instruction opcode stored with this command
		 */
		DC_CNN_HW_Command(InstructionType type) noexcept
			: m_instruction_type(type) {}

	private:
		InstructionType m_instruction_type { InstructionType::IDLE };
	};
}
