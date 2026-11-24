#include "DC_HW_Memory_IF.h"

DC_ConvNet::DC_HW_Memory_IF::DC_HW_Memory_IF(DC_OffChipMemory& off_chip_memory)
	: m_off_chip_memory(off_chip_memory)
{
}

std::vector<float> DC_ConvNet::DC_HW_Memory_IF::GetOffChipInputByAddr(size_t addr, size_t size)
{
	std::vector<float> input;

	input.reserve(size);

	for (size_t i = 0; i < size; i++) {
		input.push_back(m_off_chip_memory.Read(addr + i));
	}

	return input;
}

std::vector<float> DC_ConvNet::DC_HW_Memory_IF::GetOffChipWeightsByAddr(size_t addr, size_t size)
{
	std::vector<float> weights;

	weights.reserve(size);

	for (size_t i = 0; i < size; i++) {
		weights.push_back(m_off_chip_memory.Read(addr + i));
	}

	return weights;
}

std::vector<float> DC_ConvNet::DC_HW_Memory_IF::GetOffChipBiasByAddr(size_t addr, size_t size) 
{
	std::vector<float> bias;
	bias.reserve(size);
	for (size_t i = 0; i < size; i++) {
		bias.push_back(m_off_chip_memory.Read(addr + i));
	}
	return bias;
}

std::vector<float> DC_ConvNet::DC_HW_Memory_IF::GetOffChipOutputByAddr(size_t addr, size_t size) 
{
	std::vector<float> output;
	output.reserve(size);
	for (size_t i = 0; i < size; i++) {
		output.push_back(m_off_chip_memory.Read(addr + i));
	}
	return output;
}

std::vector<float>& DC_ConvNet::DC_HW_Memory_IF::GetOffChipBuffer() 
{
	return m_off_chip_memory.GetBuffer();
}
