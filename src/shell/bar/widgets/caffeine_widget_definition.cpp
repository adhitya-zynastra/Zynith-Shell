#include "shell/bar/widgets/caffeine_widget_definition.h"

const zynith::bar::WidgetDefinition<std::monostate>& caffeineWidgetDefinition() {
  static const zynith::bar::WidgetDefinition<std::monostate> definition{
      .type = "caffeine",
  };
  return definition;
}
