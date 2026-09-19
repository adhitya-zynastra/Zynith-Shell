#pragma once

struct wl_output;

class OutputLifecycleObserver {
public:
  virtual ~OutputLifecycleObserver() = default;
  virtual void onOutputAdded(wl_output* output) = 0;
  virtual void onOutputRemoved(wl_output* output) = 0;
};
