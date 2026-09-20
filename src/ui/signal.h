#pragma once

#include <algorithm>
#include <cstdint>
#include <functional>
#include <memory>
#include <utility>
#include <vector>

// A minimal signal/slot primitive for reactive UI updates.
//
// Dispatch is safe when a callback connects, disconnects, or **destroys**
// another subscriber. That last case is the reason this does not snapshot the
// slot list: a snapshot keeps its own copies of the std::functions, so a
// subscriber destroyed part-way through a dispatch would still be invoked
// through the copy, with its captured `this` already freed. (That was a real
// use-after-free: a palette transition emits every frame, and a handler can
// tear down nodes that are themselves subscribed.)
//
// Instead, emit() walks the canonical list and re-reads each slot immediately
// before calling it, so a slot disconnected earlier in the same dispatch is
// skipped. Disconnecting during a dispatch tombstones the slot rather than
// erasing it, keeping indices stable; tombstones are reaped when the outermost
// dispatch finishes.
//
// ScopedConnection is move-only RAII — it disconnects on destruction. Store
// one as a member of whatever object subscribes, and the subscription dies
// with the object.

template <class... Args> class Signal {
public:
  using Callback = std::function<void(Args...)>;

private:
  struct Slot {
    std::uint64_t id;
    Callback callback;
  };
  struct State {
    std::vector<Slot> slots;
    std::uint64_t nextId = 0;
    // Non-zero while emit() is dispatching (nested emits are counted).
    int dispatchDepth = 0;
  };

public:
  class ScopedConnection {
  public:
    ScopedConnection() = default;
    ScopedConnection(std::weak_ptr<State> state, std::uint64_t id) : m_state(std::move(state)), m_id(id) {}
    ~ScopedConnection() { disconnect(); }

    ScopedConnection(const ScopedConnection&) = delete;
    ScopedConnection& operator=(const ScopedConnection&) = delete;

    ScopedConnection(ScopedConnection&& other) noexcept : m_state(std::move(other.m_state)), m_id(other.m_id) {
      other.m_id = 0;
    }
    ScopedConnection& operator=(ScopedConnection&& other) noexcept {
      if (this != &other) {
        disconnect();
        m_state = std::move(other.m_state);
        m_id = other.m_id;
        other.m_id = 0;
      }
      return *this;
    }

    void disconnect() {
      if (m_id == 0) {
        return;
      }
      if (auto state = m_state.lock()) {
        auto& slots = state->slots;
        const auto it =
            std::find_if(slots.begin(), slots.end(), [id = m_id](const Slot& slot) { return slot.id == id; });
        if (it != slots.end()) {
          if (state->dispatchDepth > 0) {
            // A dispatch is walking this list: tombstone so the walk skips it
            // and keeps its position. Reaped when the dispatch unwinds.
            it->callback = nullptr;
          } else {
            slots.erase(it);
          }
        }
      }
      m_id = 0;
    }

  private:
    std::weak_ptr<State> m_state;
    std::uint64_t m_id = 0;
  };

  Signal() : m_state(std::make_shared<State>()) {}

  Signal(const Signal&) = delete;
  Signal& operator=(const Signal&) = delete;
  Signal(Signal&&) = delete;
  Signal& operator=(Signal&&) = delete;

  [[nodiscard]] ScopedConnection connect(Callback callback) {
    const auto id = ++m_state->nextId;
    m_state->slots.push_back({id, std::move(callback)});
    return ScopedConnection{std::weak_ptr<State>(m_state), id};
  }

  void emit(Args... args) {
    // Hold the state alive for the whole dispatch: a callback may destroy the
    // object that owns this Signal.
    auto state = m_state;
    ++state->dispatchDepth;

    // Slots connected during this dispatch are appended past `count` and are
    // deliberately not called until the next emit.
    const std::size_t count = state->slots.size();
    for (std::size_t i = 0; i < count && i < state->slots.size(); ++i) {
      // Re-read here: an earlier callback may have tombstoned this slot by
      // destroying its owner, and the vector may have grown (reallocated).
      if (!state->slots[i].callback) {
        continue;
      }
      // Copy before invoking: the callback may connect new slots and
      // reallocate the vector out from under us.
      Callback callback = state->slots[i].callback;
      callback(args...);
    }

    if (--state->dispatchDepth == 0) {
      auto& slots = state->slots;
      slots.erase(std::remove_if(slots.begin(), slots.end(), [](const Slot& s) { return !s.callback; }), slots.end());
    }
  }

private:
  std::shared_ptr<State> m_state;
};
