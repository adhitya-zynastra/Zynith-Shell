#pragma once

#include "shell/bar/widget_definition.h"
#include "shell/bar/widgets/control_center_widget.h"

[[nodiscard]] const zynith::bar::WidgetDefinition<ControlCenterWidget::Options>& controlCenterWidgetDefinition();
