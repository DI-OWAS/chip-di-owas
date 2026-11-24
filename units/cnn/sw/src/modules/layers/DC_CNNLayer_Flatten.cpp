#include "DC_CNNLayer_Flatten.h"
#include "DC_PerformanceStats.h"
#include "DC_CNNLayer_Stats.h"

namespace DC_ConvNet
{
    /**
     * @brief Performs forward propagation through the flatten layer
     */
    DC_Tensor DC_CNNLayer_Flatten::forward(const DC_Tensor& input) const {
        auto& stats = DC_PerformanceStats::getInstance().AllocateLayerStats(m_layer_name, m_layer_type);

        DC_Tensor output(input.m_height, input.m_width, input.m_channels, input.m_mem_order);

        output.m_data = input.m_data;

        //Update statistics
        populate_stats_flatten(input, stats);

        return output;
    }
} // namespace DC_ConvNet
