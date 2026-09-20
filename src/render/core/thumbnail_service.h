#pragma once

#include "app/poll_source.h"
#include "render/core/texture_handle.h"

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <functional>
#include <list>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <vector>

class TextureManager;

// Shared async thumbnail loader for image-backed UI. Worker threads decode and
// downsample images off the main thread; the main loop uploads finished
// pixmaps through TextureManager via uploadPending(). The service keeps
// explicit in-memory acquire/release ownership while persisting resized WebP
// files in the on-disk thumbnail cache.
class ThumbnailService : public PollSource {
public:
  using PendingUploadCallback = std::function<void()>;
  using ReadyCallback = std::function<void(const std::string& path, TextureHandle handle)>;

  // Default thumbnail long-edge in pixels. Callers wanting a sharper preview in
  // a larger box pass an explicit targetPx; each distinct size is cached
  // separately (in memory and on disk).
  static constexpr int kDefaultTargetPx = 192;

  class Subscription {
  public:
    Subscription() = default;
    ~Subscription();

    Subscription(const Subscription&) = delete;
    Subscription& operator=(const Subscription&) = delete;

    Subscription(Subscription&& other) noexcept;
    Subscription& operator=(Subscription&& other) noexcept;

    void disconnect();

  private:
    friend class ThumbnailService;

    explicit Subscription(std::function<void()> disconnect);

    std::function<void()> m_disconnect;
  };

  ThumbnailService();
  ~ThumbnailService() override;

  ThumbnailService(const ThumbnailService&) = delete;
  ThumbnailService& operator=(const ThumbnailService&) = delete;

  // Decode completion is only a wakeup: consumers should schedule an update,
  // call uploadPending() with their current render context, then re-query
  // visible thumbnail handles.
  [[nodiscard]] Subscription subscribePendingUpload(PendingUploadCallback callback);
  [[nodiscard]] Subscription
  subscribeReady(const std::string& path, ReadyCallback callback, int targetPx = kDefaultTargetPx);

  // Returns the uploaded handle if already decoded, or {0} if a decode is
  // pending. Each acquire must be paired with a release() using the same
  // (path, targetPx).
  [[nodiscard]] TextureHandle acquire(const std::string& path, int targetPx = kDefaultTargetPx);

  // Non-owning lookup used while refreshing an already-acquired thumbnail.
  [[nodiscard]] TextureHandle peek(const std::string& path, int targetPx = kDefaultTargetPx) const;

  // Releases one acquire() owner. When the last owner releases it the entry
  // does not die immediately: it moves to a small bounded idle set (LRU, capped
  // by texture bytes and count) so a consumer that scrolls back over content it
  // just left re-acquires the existing texture instead of decoding it again.
  // Idle entries own no consumer state and are evicted oldest-first.
  void release(const std::string& path, int targetPx = kDefaultTargetPx);

  // Drops every idle (zero-owner) entry and its texture, whoever parked it.
  void trimIdle();

  // ── Browsing sessions ────────────────────────────────────────────────────
  // A surface that browses a large library (the wallpaper carousel) opens a
  // session for as long as it is on screen. While one is open the idle set may
  // grow to `idleBudgetBytes`, so sweeping back and forth over content reuses
  // textures instead of re-decoding them; a user can cross 20+ items a second
  // and must not trigger a decode storm.
  //
  // Entries acquired during a session are tagged with it. endSession() drops
  // only the *idle* entries carrying that tag: anything another component still
  // holds (refCount > 0) is untouched, and so is anything another component
  // parked. The desktop wallpaper is not affected at all — it lives in
  // SharedTextureCache, not here.
  using SessionId = std::uint64_t;
  [[nodiscard]] SessionId beginSession(std::size_t idleBudgetBytes, std::size_t idleBudgetEntries);
  void endSession(SessionId session);

  struct Stats {
    std::size_t decodes = 0;    // images sent to a worker
    std::size_t idleHits = 0;   // re-acquired from the idle set (decode avoided)
    std::size_t evictions = 0;  // idle entries dropped for budget
    std::size_t peakIdleBytes = 0;
  };
  [[nodiscard]] const Stats& stats() const noexcept { return m_stats; }
  void resetStats() noexcept { m_stats = Stats{}; }

  // Decode gate. While paused, acquire() still ref-counts and still returns
  // anything already decoded (including idle-set hits), but a miss only records
  // the intent instead of queueing work. resumeDecodes() queues what is still
  // wanted. A surface that flings through content uses this so a fast traversal
  // decodes what it lands on, not every frame it passed through. Calls nest.
  void pauseDecodes();
  void resumeDecodes();
  [[nodiscard]] bool decodesPaused() const noexcept { return m_decodePauseDepth > 0; }

  // Diagnostics: how much the idle set currently holds.
  [[nodiscard]] std::size_t idleCount() const noexcept { return m_idleOrder.size(); }
  [[nodiscard]] std::size_t idleBytes() const noexcept { return m_idleBytes; }

  // Uploads decoded pixmaps to textures. Must run on the main thread with the
  // owning render context current.
  [[nodiscard]] bool uploadPending(TextureManager& textures);
  void abandonGpuResources() noexcept;
  void invalidateGpuResources(TextureManager& textures);

  [[nodiscard]] int pollTimeoutMs() const override { return -1; }
  void dispatch(const std::vector<pollfd>& fds, std::size_t startIdx) override;

protected:
  void doAddPollFds(std::vector<pollfd>& fds) override;

private:
  // Identifies a cached thumbnail: same source decoded at different long-edge
  // sizes are independent entries.
  struct RequestKey {
    std::string path;
    int targetPx = kDefaultTargetPx;

    bool operator==(const RequestKey& other) const = default;
  };

  struct RequestKeyHash {
    std::size_t operator()(const RequestKey& key) const noexcept;
  };

  struct DecodedJob {
    RequestKey key;
    std::vector<std::uint8_t> rgba;
    int width = 0;
    int height = 0;
    bool failed = false;
  };

  void workerLoop();
  void signalMain();
  void pushResult(DecodedJob job);
  void deleteAllTextures();
  void notifyPendingUpload();
  void notifyReady(const RequestKey& key, TextureHandle handle);
  void enqueueDecodeIfNeeded(const RequestKey& key);

  struct CacheEntry {
    TextureHandle handle;
    std::size_t refCount = 0;
    bool failed = false;
    // Texture footprint, used as the idle set's eviction budget.
    std::size_t bytes = 0;
    // Valid only while refCount == 0: position in m_idleOrder (oldest first).
    std::list<RequestKey>::iterator idleIt;
    bool idle = false;
    // An acquire() wanted this while the decode gate was closed.
    bool deferredDecode = false;
    // Session that last acquired this entry (0 = none/outside a session).
    SessionId session = 0;
  };

  // Idle-set budget: enough to cover a browse surface's working set plus the
  // few items just scrolled past, and small enough to stay irrelevant next to
  // the shell's baseline RSS.
  static constexpr std::size_t kMaxIdleBytes = 24U * 1024U * 1024U;
  static constexpr std::size_t kMaxIdleEntries = 24;

  void dropEntry(std::unordered_map<RequestKey, CacheEntry, RequestKeyHash>::iterator it);
  void retireToIdle(const RequestKey& key, CacheEntry& entry);
  void reviveFromIdle(const RequestKey& key, CacheEntry& entry);
  void evictIdleOverBudget();

  struct PendingListener {
    PendingUploadCallback callback;
  };

  struct ReadyListener {
    RequestKey key;
    ReadyCallback callback;
  };

  int m_eventFd = -1;
  std::vector<std::thread> m_workers;
  std::atomic<bool> m_shutdown{false};

  mutable std::mutex m_queueMutex;
  std::condition_variable m_queueCv;
  std::deque<RequestKey> m_jobQueue;
  std::unordered_set<RequestKey, RequestKeyHash> m_inFlight;
  std::unordered_set<RequestKey, RequestKeyHash> m_canceled;

  mutable std::mutex m_resultMutex;
  std::deque<DecodedJob> m_results;

  // Main thread only state.
  TextureManager* m_textureManager = nullptr;
  std::unordered_map<RequestKey, CacheEntry, RequestKeyHash> m_entries;
  // Oldest first; every element is an m_entries key with refCount == 0.
  std::list<RequestKey> m_idleOrder;
  std::size_t m_idleBytes = 0;
  int m_decodePauseDepth = 0;
  // Effective idle budget: the base above, or a session's while one is open.
  std::size_t m_idleBudgetBytes = kMaxIdleBytes;
  std::size_t m_idleBudgetEntries = kMaxIdleEntries;
  SessionId m_activeSession = 0;
  SessionId m_nextSession = 1;
  Stats m_stats;
  std::unordered_map<std::uint64_t, PendingListener> m_pendingListeners;
  std::unordered_map<std::uint64_t, ReadyListener> m_readyListeners;
  std::uint64_t m_nextListenerId = 1;
  std::shared_ptr<bool> m_lifetimeToken = std::make_shared<bool>(true);
};
