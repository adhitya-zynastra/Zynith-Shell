.pragma library

// How long a notification's popup stays up, from what its sender asked for (the freedesktop notification spec's
// expire_timeout, in ms): -1 is "the server's default", 0 is "never" (stays until handled), more is that long.
// Critical and resident ones also stay. A user rule's timeout comes first, except over those that stay.
//
// 0 taken as "the default" was a real failure: blueman's Bluetooth pairing request (Confirm/Deny) asks for 0; it
// left the screen after the default 6 s, BlueZ cancelled the unanswered pairing, and the device never paired.
//
//   e: { urgency (0 low · 1 normal · 2 critical), resident, expireTimeout, timeoutOverride (a rule's, 0: none) }
//   defaultMs: the server's default for a normal one (low ones get 70 % of it)
//   returns ms, 0 for "stays"

const LOW = 0;
const CRITICAL = 2;

function popupTimeout(e, defaultMs) {
    if (e.urgency === CRITICAL || e.resident || e.expireTimeout === 0)
        return 0;
    if (e.timeoutOverride > 0)
        return e.timeoutOverride;
    if (e.expireTimeout > 0)
        return Math.max(2000, e.expireTimeout);
    return e.urgency === LOW ? defaultMs * 0.7 : defaultMs;
}
