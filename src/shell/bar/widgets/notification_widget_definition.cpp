#include "shell/bar/widgets/notification_widget_definition.h"

const zynith::bar::WidgetDefinition<NotificationWidget::Options>& notificationWidgetDefinition() {
  using zynith::bar::field;
  using Options = NotificationWidget::Options;

  static const zynith::bar::WidgetDefinition<Options> definition{
      .type = "notifications",
      .fields = {
          field<&Options::hideWhenNoUnread>({
              .key = "hide_when_no_unread",
          }),
      },
  };
  return definition;
}
