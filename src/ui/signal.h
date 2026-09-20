#pragma once

#include <algorithm>
#include <deque>
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
    // Disconnected while a dispatch was in flight. The callable is *kept* until
    // the dispatch unwinds: a slot can be disconnected by its own callback, and
    // destroying the std::function while it runs would pull the closure out
    // from under it.
    bool dead = false;
  };
  struct State {
    // Deque, not vector: addresses stay valid when a callback connects new
    // slots mid-dispatch, so emit() can invoke the stored callable directly
    // rather than copying it (that copy was a heap allocation per slot per
    // emit, and this signal carries palette updates).
    std::deque<Slot> slots;
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
            // A dispatch is walking this list: mark it so the walk skips it and
            // keeps its position. The callable stays alive until the dispatch
            // unwinds (it may be the one currently executing).
            it->dead = true;
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
    m_state->slots.push_back(Slot{.id = id, .callback = std::move(callback), .dead = false});
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
      // Re-read each step: an earlier callback may have marked this slot dead by
      // destroying its owner. Deque storage means the element itself never moves,
      // so the callable can be invoked in place.
      Slot& slot = state->slots[i];
      if (slot.dead || !slot.callback) {
        continue;
      }
      slot.callback(args...);
    }

    if (--state->dispatchDepth == 0) {
      auto& slots = state->slots;
      std::erase_if(slots, [](const Slot& s) { return s.dead || !s.callback; });
    }
  }

private:
  std::shared_ptr<State> m_state;
};
