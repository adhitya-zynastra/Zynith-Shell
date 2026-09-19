#pragma once

// ScreenVeil — a short-lived, full-screen, click-through layer surface that draws a blurred
// texture under a palette-tinted dim, and fades its whole scene with the shell's own
// AnimationManager (so it follows [shell.animation] speed / reduced motion).
//
// It is purely visual: no keyboard interactivity, empty input region, no timers or polling.
// Owners create it for a transition and destroy it when the fade completes.
//
// Sources:
//   - wallpaper path  → same texture cache + blur as the lock screen background
//   - RGBA image      → e.g. a one-shot screencopy of the desktop

#include "config/config_types.h"
#include "render/animation/animation.h"
#include "render/animation/animation_manager.h"
#include "render/core/blur_cache.h"
#include "render/core/color.h"
#include "render/core/texture_manager.h"
#include "render/scene/node.h"
#include "wayland/layer_surface.h"

#include <functional>
#include <memory>
#include <optional>
#include <string>

class Box;
class RenderContext;
class SharedTextureCache;
class WallpaperNode;
class WaylandConnection;
struct ScreencopyImage;
struct wl_output;

class ScreenVeil {
public:
  struct Style {
    std::string nameSpace = "noctalia-veil";
    LayerShellLayer layer = LayerShellLayer::Overlay;
    float blurIntensity = 0.0F; // lock-screen semantics: radius = intensity * 40, 3 rounds
    float tintIntensity = 0.0F; // Surface role at this alpha, drawn over the image
    WallpaperFillMode fillMode = WallpaperFillMode::Crop;
    Color fillColor = rgba(0.0F, 0.0F, 0.0F, 1.0F);
  };

  ScreenVeil(WaylandConnection& wayland, RenderContext* renderContext, SharedTextureCache* textureCache);
  ~ScreenVeil();
  ScreenVeil(const ScreenVeil&) = delete;
  ScreenVeil& operator=(const ScreenVeil&) = delete;

  // Create the surface on `output` showing the wallpaper at `path` (or the given image).
  bool showWallpaper(wl_output* output, std::string path, const Style& style, float initialOpacity);
  bool showImage(wl_output* output, ScreencopyImage image, const Style& style, float initialOpacity);

  // Fade the whole veil. Base duration: divided by [shell.animation] speed like every shell fade.
  void fadeTo(float opacity, float durationMs, Easing easing, std::function<void()> onDone = {});

  // True once the veil has prepared a frame with its content (safe to reveal things under it).
  [[nodiscard]] bool ready() const noexcept { return m_ready; }
  [[nodiscard]] wl_output* output() const noexcept { return m_output; }

private:
  bool create(wl_output* output, const Style& style, float initialOpacity);
  void prepareFrame(bool needsUpdate, bool needsLayout);
  void applyContent();
  void releaseTextures();

  WaylandConnection& m_wayland;
  RenderContext* m_renderContext = nullptr;
  SharedTextureCache* m_textureCache = nullptr;
  wl_output* m_output = nullptr;
  Style m_style;

  // Declared before the scene so it outlives it (~Node cancels its animations through this).
  AnimationManager m_animations;
  std::unique_ptr<Node> m_root;
  WallpaperNode* m_image = nullptr;
  Box* m_tint = nullptr;
  std::unique_ptr<LayerSurface> m_surface;

  std::string m_wallpaperPath;
  std::unique_ptr<ScreencopyImage> m_capture;
  TextureHandle m_sourceTexture{};  // wallpaper (cache-owned) or capture upload (owned)
  bool m_sourceFromCache = false;
  TextureHandle m_blurredTexture{};
  BlurCache m_blurCache;
  bool m_contentDirty = true;
  bool m_ready = false;
};
