#pragma once

// zynith: changes the Zynith UI shows, pushed to it instead of polled. One line per event on the UI's command
// socket ($XDG_RUNTIME_DIR/zynith/ui.sock):
//
//   event <name> [payload]
//
// Fire and forget: a non-blocking connect and send, never a wait for the reply. When the UI is not running
// the connect fails at once and the event is dropped; the UI asks for current state when it starts.

#include <string_view>

namespace zynith {

  void notifyUi(std::string_view name, std::string_view payload = {});

} // namespace zynith
