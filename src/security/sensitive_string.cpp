#include "security/sensitive_string.h"

#include <sodium.h>

namespace security {

  void wipeString(std::string& value) noexcept {
    if (value.capacity() == 0) {
      return;
    }
    // resize() to capacity never reallocates; it makes every allocated byte addressable for the wipe.
    value.resize(value.capacity());
    sodium_memzero(value.data(), value.size());
    value.clear();
  }

} // namespace security
