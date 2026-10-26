#include "shell/bar/widgets/power_profile_widget_definition.h"

const zynith::bar::WidgetDefinition<std::monostate>& powerProfileWidgetDefinition() {
  static const zynith::bar::WidgetDefinition<std::monostate> definition{
      .type = "power_profile",
  };
  return definition;
}
