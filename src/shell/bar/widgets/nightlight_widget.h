#pragma once

#include "shell/bar/widget.h"

class Glyph;
class InputArea;
class GammaService;

class NightLightWidget : public Widget {
public:
  explicit NightLightWidget(GammaService* nightLight);

  void create() override;

private:
  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void doUpdate(Renderer& renderer) override;
  void syncState(Renderer& renderer);

  GammaService* m_nightLight = nullptr;
  InputArea* m_area = nullptr;
  Glyph* m_glyph = nullptr;
  bool m_lastEnabled = false;
  bool m_lastActive = false;
  bool m_lastForced = false;
};
