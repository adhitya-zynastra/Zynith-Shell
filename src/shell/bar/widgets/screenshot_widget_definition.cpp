#include "shell/bar/widgets/screenshot_widget_definition.h"

#include "shell/bar/widgets/glyph_button_definition.h"

const zynith::bar::WidgetDefinition<ScreenshotWidget::Options>& screenshotWidgetDefinition() {
  using Options = ScreenshotWidget::Options;

  static const zynith::bar::WidgetDefinition<Options> definition{
      .type = "screenshot",
      .fields = zynith::bar::glyphButtonFields<Options>(),
  };
  return definition;
}
