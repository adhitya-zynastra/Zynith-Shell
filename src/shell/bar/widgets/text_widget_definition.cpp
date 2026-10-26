#include "shell/bar/widgets/text_widget_definition.h"

const zynith::bar::WidgetDefinition<TextWidget::Options>& textWidgetDefinition() {
  using zynith::bar::field;
  using Options = TextWidget::Options;

  static const zynith::bar::WidgetDefinition<Options> definition{
      .type = "text",
      .fields = {
          field<&Options::text>({
              .key = "text",
          }),
      },
  };
  return definition;
}
