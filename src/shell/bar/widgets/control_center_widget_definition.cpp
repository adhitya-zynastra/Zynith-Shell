#include "shell/bar/widgets/control_center_widget_definition.h"

#include "shell/bar/widgets/glyph_button_definition.h"

const zynith::bar::WidgetDefinition<ControlCenterWidget::Options>& controlCenterWidgetDefinition() {
  using Options = ControlCenterWidget::Options;

  static const zynith::bar::WidgetDefinition<Options> definition{
      .type = "control-center",
      .fields = zynith::bar::glyphButtonFields<Options>(),
      .glyph = [](const Options& options) { return options.glyph; },
  };
  return definition;
}
