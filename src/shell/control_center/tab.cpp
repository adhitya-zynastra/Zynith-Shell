#include "shell/control_center/tab.h"

#include "ui/builders.h"
#include "ui/semantic_color.h"
#include "ui/tokens.h"
#include "ui/typography.h"

#include <memory>

namespace control_center {

  namespace {
    bool g_zynithSurfaces = false;

    // zynith: a section is an embedded plate — a tone step inside the panel's glass, not a bordered
    // card. It is lighter than the classic card so that content, not containers, carries the section;
    // the edge appears only when [shell].card_borders asks for one, as a hairline.
    void applyZynithPlate(Flex& card, float scale, float fillOpacity) {
      card.setFill(colorSpecFromRole(ColorRole::SurfaceVariant, fillOpacity * 0.72F));
      if (Style::cardBordersEnabled()) {
        card.setBorder(ui::color::spec(ui::color::Semantic::Hairline), ui::tokens::kHairline * scale);
      } else {
        card.clearBorder();
      }
      card.setRadius(ui::tokens::radius(ui::tokens::Radius::Plate, scale));
    }
  } // namespace

  void setZynithSurfaces(bool zynith) noexcept { g_zynithSurfaces = zynith; }
  bool zynithSurfaces() noexcept { return g_zynithSurfaces; }

  void applySectionCardStyle(Flex& card, float scale, float fillOpacity) {
    if (g_zynithSurfaces) {
      applyZynithPlate(card, scale, fillOpacity);
    } else {
      card.setCardStyle(scale, fillOpacity);
    }
    card.setDirection(FlexDirection::Vertical);
    card.setAlign(FlexAlign::Stretch);
    card.setGap(Style::spaceSm * scale);
    card.setPadding(Style::spaceMd * scale);
  }

  Label* addTitle(Flex& parent, const std::string& text, float scale) {
    Label* ptr = nullptr;
    if (g_zynithSurfaces) {
      // The Subtitle role: the same size as the titles most sections build themselves (Title size, bold),
      // one weight lighter, so helper-built and hand-built headings read as one family. (A quieter muted
      // label was tried first; next to the hand-built bold titles it read as inconsistent, not calm.)
      auto label = ui::label({.out = &ptr, .text = text, .color = ui::color::spec(ui::color::Semantic::OnSurface)});
      ui::type::apply(*ptr, ui::type::Role::Subtitle, scale);
      parent.addChild(std::move(label));
      return ptr;
    }
    auto label = ui::label({
        .out = &ptr,
        .text = text,
        .fontSize = Style::fontSizeTitle * scale,
        .fontWeight = FontWeight::Bold,
        .color = colorSpecFromRole(ColorRole::OnSurface),
    });
    parent.addChild(std::move(label));
    return ptr;
  }

  void addBody(Flex& parent, const std::string& text, float scale) {
    parent.addChild(
        ui::label({
            .text = text,
            .fontSize = Style::fontSizeBody * scale,
            .color = colorSpecFromRole(ColorRole::OnSurfaceVariant),
        })
    );
  }

  std::unique_ptr<Flex> makeCardHeaderRow(const std::string& title, float scale) {
    if (g_zynithSurfaces) {
      Label* heading = nullptr;
      auto row = ui::row(
          {.align = FlexAlign::Center, .gap = Style::spaceSm * scale, .minHeight = Style::controlHeightSm * scale},
          ui::label({
              .out = &heading,
              .text = title,
              .color = ui::color::spec(ui::color::Semantic::OnSurface),
              .flexGrow = 1.0F,
          })
      );
      ui::type::apply(*heading, ui::type::Role::Subtitle, scale);
      return row;
    }
    return ui::row(
        {.align = FlexAlign::Center, .gap = Style::spaceSm * scale, .minHeight = Style::controlHeightSm * scale},
        ui::label({
            .text = title,
            .fontSize = Style::fontSizeBody * scale,
            .fontWeight = FontWeight::Bold,
            .color = colorSpecFromRole(ColorRole::OnSurface),
            .flexGrow = 1.0F,
        })
    );
  }

} // namespace control_center

std::unique_ptr<Flex> Tab::createHeaderActions() { return nullptr; }
