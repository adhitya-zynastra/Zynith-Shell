#pragma once

#include <string>

// zynith: wipe a std::string that held secret material (a password being typed, a PAM copy).
//
// Clearing a string only moves its end; the characters stay in the buffer until it is reused or freed, and a freed
// buffer is not zeroed. wipeString() zeroes the whole allocated capacity (not just size(), which misses what earlier,
// longer contents left behind) with sodium_memzero, which the optimiser may not remove, and leaves the string empty
// with its capacity kept — so a password field that reserved its buffer never reallocates and strands a prefix.
namespace security {

  void wipeString(std::string& value) noexcept;

  // Capacity a password buffer reserves up front: typing never reallocates (and leaves a copy behind) below this.
  inline constexpr std::size_t kPasswordBufferReserve = 256;

} // namespace security
