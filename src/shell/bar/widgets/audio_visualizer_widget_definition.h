#pragma once

#include "shell/bar/widget_definition.h"
#include "shell/bar/widgets/audio_visualizer_widget.h"

[[nodiscard]] const zynith::bar::WidgetDefinition<AudioVisualizerWidget::Options>& audioVisualizerWidgetDefinition();
