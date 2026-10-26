#include "shell/bar/widgets/nightlight_widget_definition.h"

const zynith::bar::WidgetDefinition<std::monostate>& nightlightWidgetDefinition() {
  static const zynith::bar::WidgetDefinition<std::monostate> definition{
      .type = "nightlight",
  };
  return definition;
}
