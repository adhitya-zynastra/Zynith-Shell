#include "shell/bar/widgets/test_widget_definition.h"

const zynith::bar::WidgetDefinition<std::monostate>& testWidgetDefinition() {
  static const zynith::bar::WidgetDefinition<std::monostate> definition{
      .type = "test",
  };
  return definition;
}
