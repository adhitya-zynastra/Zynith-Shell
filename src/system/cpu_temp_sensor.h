#pragma once

#include <filesystem>
#include <optional>
#include <string>

namespace zynith::system::cpu_temp {

  struct Reading {
    double tempC = 0.0;
    std::string source;
  };

  struct ProbeResult {
    std::optional<Reading> reading;
    std::string error;
  };

  [[nodiscard]] ProbeResult read(
      const std::filesystem::path& hwmonRoot, const std::filesystem::path& thermalRoot,
      const std::string& configuredSensorPath
  );

} // namespace zynith::system::cpu_temp
