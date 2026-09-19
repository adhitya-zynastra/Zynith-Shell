#pragma once

#include <string>
#include <string_view>
#include <unordered_map>

class DependencyService {
public:
  DependencyService();

  [[nodiscard]] bool has(std::string_view name) const;
  [[nodiscard]] bool hasDdcutil() const { return has("ddcutil"); }

  void rescan();

private:
  std::unordered_map<std::string, bool> m_present;
};
