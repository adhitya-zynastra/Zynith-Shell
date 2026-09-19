#pragma once

#include <string>

namespace compositors::sway {

  class SwayRuntime {
  public:
    SwayRuntime() = default;

    [[nodiscard]] const std::string& socketPath() const;
    [[nodiscard]] const std::string& msgCommand() const;
    [[nodiscard]] const std::string& outputCommand() const;
    [[nodiscard]] bool hasMsgCommand() const;
    [[nodiscard]] bool hasOutputCommand() const;
    void refresh();

  private:
    void ensureResolved() const;
    void resolveSocketPath() const;
    void resolveCommands() const;

    mutable bool m_resolved = false;
    mutable std::string m_socketPath;
    mutable std::string m_msgCommand;
    mutable std::string m_outputCommand;
  };

} // namespace compositors::sway
