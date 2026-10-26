#pragma once

#include "shell/bar/widget_definition.h"
#include "shell/bar/widgets/clipboard_widget.h"

[[nodiscard]] const zynith::bar::WidgetDefinition<ClipboardWidget::Options>& clipboardWidgetDefinition();
