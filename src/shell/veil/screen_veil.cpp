#include "shell/veil/screen_veil.h"

#include "capture/screencopy_capture.h"
#include "core/log.h"
#include "render/core/render_styles.h"
#include "render/core/shared_texture_cache.h"
#include "render/render_context.h"
#include "render/scene/wallpaper_node.h"
#include "ui/builders.h"
#include "ui/controls/box.h"
#include "ui/palette.h"
#include "wayland/wayland_connection.h"

#include <algorithm>
#include <utility>

namespace {
  constexpr Logger kLog("veil");
  constexpr int kBlurRounds = 3; // same as the lock screen and backdrop
} // namespace

ScreenVeil::ScreenVeil(WaylandConnection& wayland, RenderContext* renderContext, SharedTextureCache* textureCache)
    : m_wayland(wayland), m_renderContext(renderContext), m_textureCache(textureCache) {}

ScreenVeil::~ScreenVeil() {
  // Stop animations before the scene they point into goes away.
  m_animations.cancelAll();
  releaseTextures();
  m_surface.reset();
}

bool ScreenVeil::showWallpaper(wl_output* output, std::string path, const Style& style, float initialOpacity) {
  m_wallpaperPath = std::move(path);
  m_capture.reset();
  m_tintOnly = false;
  return create(output, style, initialOpacity);
}

bool ScreenVeil::showTint(wl_output* output, const Style& style, float initialOpacity) {
  m_wallpaperPath.clear();
  m_capture.reset();
  m_tintOnly = true;
  if (!create(output, style, initialOpacity)) {
    return false;
  }
  // No image node: the tint box alone composites over live content below. The
  // surface's own configure/prepare cycle sizes and paints it.
  m_ready = true;
  return true;
}

bool ScreenVeil::showImage(wl_output* output, ScreencopyImage image, const Style& style, float initialOpacity) {
  m_wallpaperPath.clear();
  m_tintOnly = false;
  m_capture = std::make_unique<ScreencopyImage>(std::move(image));
  return create(output, style, initialOpacity);
}

bool ScreenVeil::create(wl_output* output, const Style& style, float initialOpacity) {
  if (m_renderContext == nullptr || output == nullptr) {
    return false;
  }
  m_output = output;
  m_style = style;

  m_root = ui::node({});
  m_root->setOpacity(std::clamp(initialOpacity, 0.0F, 1.0F));
  if (!m_tintOnly) {
    auto image = std::make_unique<WallpaperNode>();
    m_image = static_cast<WallpaperNode*>(m_root->addChild(std::move(image)));
    m_image->setZIndex(0);
  }
  m_root->addChild(
      ui::box({
          .out = &m_tint,
          .visible = m_style.tintIntensity > 0.0F,
          .configure = [](Box& box) { box.setZIndex(1); },
      })
  );
  m_root->setAnimationManager(&m_animations);

  auto config = LayerSurfaceConfig{
      .nameSpace = m_style.nameSpace,
      .layer = m_style.layer,
      .anchor = LayerShellAnchor::Top | LayerShellAnchor::Bottom | LayerShellAnchor::Left | LayerShellAnchor::Right,
      .width = 0,
      .height = 0,
      .exclusiveZone = -1, // cover bars too
      .keyboard = LayerShellKeyboard::None,
  };
  m_surface = std::make_unique<LayerSurface>(m_wayland, std::move(config));
  m_surface->setRenderContext(m_renderContext);
  m_surface->setAnimationManager(&m_animations);
  m_surface->setConfigureCallback([this](std::uint32_t /*w*/, std::uint32_t /*h*/) {
    m_contentDirty = true;
    m_surface->requestLayout();
  });
  m_surface->setPrepareFrameCallback([this](bool needsUpdate, bool needsLayout) {
    prepareFrame(needsUpdate, needsLayout);
  });
  if (!m_surface->initialize(output)) {
    kLog.warn("failed to initialize veil surface");
    m_surface.reset();
    return false;
  }
  m_surface->setInputRegion({}); // purely visual: pointer and keyboard pass straight through
  m_surface->setSceneRoot(m_root.get());
  return true;
}

void ScreenVeil::fadeTo(float opacity, float durationMs, Easing easing, std::function<void()> onDone) {
  if (m_root == nullptr) {
    if (onDone) {
      onDone();
    }
    return;
  }
  Node* root = m_root.get();
  m_animations.cancelForOwner(root);
  m_animations.animate(
      root->opacity(), std::clamp(opacity, 0.0F, 1.0F), durationMs, easing, [root](float v) { root->setOpacity(v); },
      std::move(onDone), root
  );
  if (m_surface != nullptr) {
    m_surface->requestRedraw();
  }
}

void ScreenVeil::fadeOutOnPresent(motion::Role role, std::function<void()> onDone) {
  if (m_root == nullptr) {
    if (onDone) {
      onDone();
    }
    return;
  }
  m_pendingFade =
      PendingFade{.role = role, .onDone = std::move(onDone), .requestedAt = std::chrono::steady_clock::now()};
  if (m_surface != nullptr) {
    // An update (not just a redraw): prepareFrame(), which starts the fade, only runs for update/layout
    // requests. Deferred by the surface until the compositor releases its frame callback.
    m_surface->requestUpdate();
  }
}

void ScreenVeil::prepareFrame(bool needsUpdate, bool needsLayout) {
  if (m_surface == nullptr || m_renderContext == nullptr || m_surface->width() == 0 || m_surface->height() == 0) {
    return;
  }
  m_renderContext->makeCurrent(m_surface->renderTarget());

  if (m_finishFramesLeft > 0) {
    if (--m_finishFramesLeft == 0) {
      kLog.info(
          "veil fade: {} frames over {:.0f} ms, zero-opacity frame presented", m_fadeFrames,
          std::chrono::duration<float, std::milli>(std::chrono::steady_clock::now() - m_fadeStartedAt).count()
      );
      if (auto done = std::move(m_finishAfterPresent)) {
        done();
      }
    } else {
      m_surface->requestUpdate();
    }
  } else if (m_fadeFrames > 0 || m_pendingFade.has_value()) {
    ++m_fadeFrames;
  }

  if (m_pendingFade.has_value() && m_root != nullptr) {
    PendingFade fade = std::move(*m_pendingFade);
    m_pendingFade.reset();
    const float waitedMs =
        std::chrono::duration<float, std::milli>(std::chrono::steady_clock::now() - fade.requestedAt).count();
    kLog.info("veil fade starts on first presented frame, {:.1f} ms after the request", waitedMs);
    Node* root = m_root.get();
    m_fadeStartedAt = std::chrono::steady_clock::now();
    m_animations.cancelForOwner(root);
    m_animations.animate(
        fade.role, root->opacity(), 0.0F,
        [this, root](float v) {
          root->setOpacity(v);
          m_surface->requestUpdate(); // every step must reach the screen, not only the first
        },
        [this, done = std::move(fade.onDone)]() mutable {
          m_finishAfterPresent = std::move(done);
          m_finishFramesLeft = 2; // render the 0-opacity frame, then wait for its presentation
          m_surface->requestUpdate();
        },
        root
    );
    m_surface->requestUpdate();
  }

  if (m_contentDirty) {
    applyContent();
  }

  if (needsUpdate || needsLayout) {
    const auto w = static_cast<float>(m_surface->width());
    const auto h = static_cast<float>(m_surface->height());
    m_root->setSize(w, h);
    if (m_image != nullptr) {
      m_image->setPosition(0.0F, 0.0F);
      m_image->setSize(w, h);
    }
    if (m_tint != nullptr) {
      m_tint->setPosition(0.0F, 0.0F);
      m_tint->setSize(w, h);
      m_tint->setStyle(
          RoundedRectStyle{
              .fill = colorForRole(ColorRole::Surface, m_style.tintIntensity),
              .fillMode = FillMode::Solid,
          }
      );
    }
  }
}

void ScreenVeil::applyContent() {
  if (m_tintOnly || m_image == nullptr) {
    m_contentDirty = false;
    m_ready = true;
    return;
  }
  auto& tm = m_renderContext->textureManager();
  releaseTextures();

  if (m_capture != nullptr && !m_capture->rgba.empty() && m_capture->width > 0 && m_capture->height > 0) {
    m_sourceTexture = tm.loadFromRgba(m_capture->rgba.data(), m_capture->width, m_capture->height, false);
    m_sourceFromCache = false;
    m_capture.reset(); // pixels now live on the GPU
  } else if (!m_wallpaperPath.empty() && m_textureCache != nullptr) {
    m_sourceTexture = m_textureCache->acquire(m_wallpaperPath);
    m_sourceFromCache = m_sourceTexture.id != 0;
    if (m_sourceTexture.id == 0 && !m_textureCache->shared()) {
      m_sourceTexture = tm.loadFromFile(m_wallpaperPath, 0, true);
    }
  }

  if (m_sourceTexture.id == 0) {
    // Nothing to show: fall back to the fill colour so the veil still covers the handoff.
    m_image->setSources(
        WallpaperSourceKind::Color, {}, m_style.fillColor, WallpaperSourceKind::Image, {}, rgba(0.0F, 0.0F, 0.0F, 1.0F),
        0.0F, 0.0F, 0.0F, 0.0F
    );
    m_contentDirty = false;
    m_ready = true;
    return;
  }

  TextureHandle shown = m_sourceTexture;
  if (m_style.blurIntensity > 0.0F) {
    m_blurredTexture = m_blurCache.get(
        m_renderContext->backend(), m_sourceTexture, m_surface->renderTarget().bufferWidth(),
        m_surface->renderTarget().bufferHeight(), m_style.blurIntensity * 40.0F, kBlurRounds
    );
    if (m_blurredTexture.id != 0) {
      shown = m_blurredTexture;
    }
  }
  m_image->setTextures(shown.id, {}, static_cast<float>(shown.width), static_cast<float>(shown.height), 0.0F, 0.0F);
  m_image->setTransition(WallpaperTransition::Fade, 0.0F, TransitionParams{});
  m_image->setFillMode(m_style.fillMode);
  m_image->setFillColor(m_style.fillColor);
  m_contentDirty = false;
  m_ready = true;
}

void ScreenVeil::releaseTextures() {
  if (m_renderContext == nullptr) {
    return;
  }
  if (m_surface != nullptr) {
    m_renderContext->makeCurrent(m_surface->renderTarget());
  }
  auto& tm = m_renderContext->textureManager();
  m_blurCache.destroy();
  m_blurredTexture = {};
  if (m_sourceTexture.id != 0) {
    if (m_sourceFromCache && m_textureCache != nullptr) {
      m_textureCache->release(m_sourceTexture, m_wallpaperPath);
    } else {
      tm.unload(m_sourceTexture);
    }
  }
  m_sourceTexture = {};
  m_sourceFromCache = false;
}
