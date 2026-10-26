#include "shell/bar/widgets/brightness_widget_definition.h"

const zynith::bar::WidgetDefinition<BrightnessWidget::Options>& brightnessWidgetDefinition() {
  using zynith::bar::field;
  using Options = BrightnessWidget::Options;

  static const zynith::bar::WidgetDefinition<Options> definition{
      .type = "brightness",
      .fields = {
          field<&Options::showLabel>({
              .key = "show_label",
          }),
      },
  };
  return definition;
}
